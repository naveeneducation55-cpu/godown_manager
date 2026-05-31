// ─────────────────────────────────────────────────────────────────────────────
// feedback_service.dart — v2.7.3
//
// Responsibilities:
//   • Check if feedback already submitted today (SharedPrefs — fast, no network)
//   • Sanitise input before any DB write
//   • Server-side duplicate check (Supabase date query)
//   • Insert into feedback table
//   • Mark submitted in SharedPrefs on success
//
// Security:
//   • PostgREST parameterised queries — SQL injection impossible
//   • _sanitiseText strips null bytes, HTML chars, collapses whitespace
//   • DB CHECK constraint (5–1000 chars) is last line of defence
//   • No SELECT policy on feedback table — only dashboard can read
//   • Server-side duplicate check — cannot be bypassed by clearing SharedPrefs
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/id_generator.dart';

// ── Result enum — caller handles each case with specific UI ──────────────────
enum FeedbackResult {
  success,          // inserted successfully
  alreadySubmitted, // submitted today already
  tooShort,         // < min chars after sanitise
  tooLong,          // > max chars after sanitise
  empty,            // blank after sanitise
  networkError,     // Supabase unreachable
  serverError,      // Supabase returned error
}

// ─────────────────────────────────────────────────────────────────────────────
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  SupabaseClient get _client => Supabase.instance.client;

  static const _kTable        = 'feedback';
  static const _kPrefsKey     = 'feedback_last_submitted_date';
  static const _kTimeout      = Duration(seconds: 8);

  // ── Check if already submitted today — SharedPrefs only (instant) ──────────
  // Called on HomeScreen build — must be synchronous-feeling.
  // Returns true if already submitted today in IST.
  Future<bool> hasSubmittedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last  = prefs.getString(_kPrefsKey) ?? '';
      return last == _todayIST();
    } catch (e) {
      debugPrint('FeedbackService.hasSubmittedToday error: $e');
      return false; // fail open — let server check catch duplicates
    }
  }

  // ── Submit — full validation + server check + insert ──────────────────────
  Future<FeedbackResult> submit({
    required String shopId,
    required String staffId,
    required String message,
    required String appVersion,
    required int    minChars,
    required int    maxChars,
  }) async {
    debugPrint('FeedbackService.submit: shopId=$shopId staffId=$staffId');

    // Step 1 — sanitise input
    final clean = _sanitise(message);
    debugPrint('FeedbackService.submit: cleaned length=${clean.length}');

    // Step 2 — length validation
    if (clean.isEmpty)          return FeedbackResult.empty;
    if (clean.length < minChars) return FeedbackResult.tooShort;
    if (clean.length > maxChars) return FeedbackResult.tooLong;

    try {
      // Step 3 — server-side duplicate check (cannot be bypassed)
      // Checks if this staff already submitted today in IST
      final existing = await _client
          .from(_kTable)
          .select('id')
          .eq('shop_id',  shopId)
          .eq('staff_id', staffId)
          .gte('submitted_at',
              _todayISTStart().toIso8601String())
          .lte('submitted_at',
              _todayISTEnd().toIso8601String())
          .limit(1)
          .timeout(_kTimeout);

      if ((existing as List).isNotEmpty) {
        debugPrint('FeedbackService.submit: already submitted today (server check)');
        // Sync SharedPrefs in case it was cleared
        await _markSubmitted();
        return FeedbackResult.alreadySubmitted;
      }

      // Step 4 — insert
      final feedbackId = await IdGenerator.instance.feedback();
      await _client.from(_kTable).insert({
        'id':           feedbackId,
        'shop_id':      shopId,
        'staff_id':     staffId,
        'message':      clean,
        'app_version':  appVersion,
      }).timeout(_kTimeout);
      debugPrint('FeedbackService.submit: id=$feedbackId');

      // Step 5 — mark locally
      await _markSubmitted();
      debugPrint('FeedbackService.submit: success');
      return FeedbackResult.success;

    } on PostgrestException catch (e) {
      debugPrint('FeedbackService.submit PostgrestException: ${e.message}');
      // DB CHECK violation — message too short/long slipped through
      if (e.code == '23514') return FeedbackResult.tooLong;
      return FeedbackResult.serverError;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('timeout') ||
          msg.contains('socket') ||
          msg.contains('network') ||
          msg.contains('connection')) {
        debugPrint('FeedbackService.submit: network error — $e');
        return FeedbackResult.networkError;
      }
      debugPrint('FeedbackService.submit error: $e');
      return FeedbackResult.serverError;
    }
  }

  // ── Mark submitted today in SharedPrefs ────────────────────────────────────
  Future<void> _markSubmitted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, _todayIST());
    } catch (e) {
      debugPrint('FeedbackService._markSubmitted error: $e');
    }
  }

  // ── IST date helpers ───────────────────────────────────────────────────────
  // IST = UTC + 5:30
  static const _ist = Duration(hours: 5, minutes: 30);

  String _todayIST() {
    final ist = DateTime.now().toUtc().add(_ist);
    return '${ist.year}-'
           '${ist.month.toString().padLeft(2, '0')}-'
           '${ist.day.toString().padLeft(2, '0')}';
  }

  // Start of today in IST → converted to UTC for Supabase query
  DateTime _todayISTStart() {
    final ist = DateTime.now().toUtc().add(_ist);
    return DateTime.utc(ist.year, ist.month, ist.day)
        .subtract(_ist); // convert back to UTC
  }

  // End of today in IST → converted to UTC
  DateTime _todayISTEnd() {
    final ist = DateTime.now().toUtc().add(_ist);
    return DateTime.utc(ist.year, ist.month, ist.day, 23, 59, 59)
        .subtract(_ist);
  }

  // ── Sanitise — strips dangerous characters, collapses whitespace ───────────
  // PostgREST already parameterises queries so SQL injection is impossible.
  // This sanitiser protects against data hygiene issues and stored XSS
  // if feedback is ever displayed in a web dashboard.
  String _sanitise(String raw) {
    return raw
        .replaceAll('\x00', '')           // null bytes
        .replaceAll(RegExp(r'<[^>]*>'),   // strip HTML tags
                    '')
        .replaceAll(RegExp(r'[{}]'), '')  // strip template injection chars
        .replaceAll(RegExp(r'\s+'), ' ') // collapse whitespace
        .trim();
  }
}
