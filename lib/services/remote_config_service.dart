// ─────────────────────────────────────────────────────────────────────────────
// remote_config_service.dart — Phase 3 (v2.7.0)
//
// Single source of truth for all remote configuration.
//
// Behaviour:
//   • fetch() called once on every app open — non-blocking, 3s timeout
//   • On success  → store in memory + persist to SharedPrefs (1hr TTL)
//   • On failure  → load from SharedPrefs cache
//   • No cache    → use hardcoded defaults
//   • Never throws — always falls back silently
//
// Force update rule (minor version diff):
//   diff = min_minor - current_minor
//   diff <= 5 → softUpdate  — show banner, user can dismiss
//   diff  > 5 → hardBlock   — no bypass, must update
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Hardcoded defaults — used when Supabase unreachable AND no cache ──────────
const _kDefaults = <String, String>{
  'min_version':        '2.6.0',
  'latest_version':     '2.6.0',
  'force_update_msg':   'A required update is available. Please update the app.',
  'maintenance_mode':   'false',
  'maintenance_msg':    'System maintenance in progress. Back shortly.',
  'trial_days':         '7',
  'support_phone':      '',
  'apk_url':            '',
  'feature_barcode':    'false',
  'feature_analytics':  'false',
  'feature_ios':        'false',
  'feature_web':        'false',
  'max_staff_per_shop': '20',
  'max_items_per_shop': '250',
  'feedback_enabled':   'true',
  'feedback_min_chars': '5',
  'feedback_max_chars': '1000',
};

const _kCacheKey     = 'remote_config_cache';
const _kCacheTimeKey = 'remote_config_fetched_at';
const _kCacheTtl     = Duration(minutes: 1);
const _kFetchTimeout = Duration(seconds: 3);

// ── Force update result ───────────────────────────────────────────────────────
enum ForceUpdateStatus {
  upToDate,   // current >= min_version
  softUpdate, // minor diff <= 5 — banner, dismissable
  hardBlock,  // minor diff  > 5 — no bypass
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  Map<String, String> _config  = Map.from(_kDefaults);
  bool                _fetched = false;

  // ── Public getters ─────────────────────────────────────────────────────────

  String get(String key, [String? fallback]) =>
      _config[key] ?? fallback ?? _kDefaults[key] ?? '';

  bool   isFeatureEnabled(String key) => get(key) == 'true';

  bool   get maintenanceMode => get('maintenance_mode') == 'true';
  String get maintenanceMsg  => get('maintenance_msg');
  String get minVersion      => get('min_version');
  String get latestVersion   => get('latest_version');
  String get forceUpdateMsg  => get('force_update_msg');
  int    get trialDays       => int.tryParse(get('trial_days')) ?? 7;
  String get supportPhone    => get('support_phone');
  String get apkUrl          => get('apk_url');
   // ── Feedback feature flag ──────────────────────────────────────────────────
  bool get feedbackEnabled  => isFeatureEnabled('feedback_enabled');
  int  get feedbackMinChars => int.tryParse(get('feedback_min_chars', '5'))    ?? 5;
  int  get feedbackMaxChars => int.tryParse(get('feedback_max_chars', '1000')) ?? 1000;

  // ── Force update check ─────────────────────────────────────────────────────

  /// Pass current app version string e.g. '2.7.0'
  ForceUpdateStatus checkForceUpdate(String currentVersion) {
    try {
      final current = _parseVersionInt(currentVersion);
      final minimum = _parseVersionInt(minVersion);
      if (current >= minimum) return ForceUpdateStatus.upToDate;
      final diff = minimum - current;
      return diff <= 5
          ? ForceUpdateStatus.softUpdate
          : ForceUpdateStatus.hardBlock;
    } catch (e) {
      debugPrint('RemoteConfigService.checkForceUpdate error: $e');
      return ForceUpdateStatus.upToDate;
    }
  }

  /// '2.6.2' → 206 (major * 100 + minor, ignores patch)
  int _parseVersionInt(String version) {
    final parts = version.trim().split('.');
    if (parts.length < 2) return 0;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = int.tryParse(parts[1]) ?? 0;
    return major * 100 + minor;
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Called once on every app open. Non-blocking — never throws.
  Future<void> fetch() async {
    if (_fetched) return;
    if (await _loadFromCache()) return;

    try {
      final rows = await Supabase.instance.client
          .from('app_config')
          .select()
          .timeout(_kFetchTimeout);

      final fetched = <String, String>{};
      for (final row in rows) {
        final key   = row['key']?.toString();
        final value = row['value']?.toString();
        if (key != null && value != null) fetched[key] = value;
      }

      if (fetched.isNotEmpty) {
        _config  = {..._kDefaults, ...fetched};
        _fetched = true;
        await _persistCache();
        debugPrint('RemoteConfigService: fetched ${fetched.length} keys');
      }
    } catch (e) {
      debugPrint('RemoteConfigService.fetch: unreachable ($e)');
    }
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<bool> _loadFromCache() async {
    try {
      final prefs      = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_kCacheKey);
      final cachedTime = prefs.getString(_kCacheTimeKey);
      if (cachedJson == null || cachedTime == null) return false;

      final fetchedAt = DateTime.tryParse(cachedTime);
      if (fetchedAt == null) return false;

      if (DateTime.now().toUtc().difference(fetchedAt) > _kCacheTtl) {
        debugPrint('RemoteConfigService: cache expired');
        return false;
      }

      final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
      _config  = {
        ..._kDefaults,
        ...decoded.map((k, v) => MapEntry(k, v.toString())),
      };
      _fetched = true;
      debugPrint('RemoteConfigService: loaded from cache');
      return true;
    } catch (e) {
      debugPrint('RemoteConfigService._loadFromCache error: $e');
      return false;
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey,     jsonEncode(_config));
      await prefs.setString(_kCacheTimeKey, DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      debugPrint('RemoteConfigService._persistCache error: $e');
    }
  }

  /// Force re-fetch on next call — call after maintenance retry tap
  void invalidateCache() {
    _fetched = false;
    debugPrint('RemoteConfigService: cache invalidated');
  }
}
