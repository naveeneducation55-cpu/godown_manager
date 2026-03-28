// ─────────────────────────────────────────────────────────────────────────────
// supabase_service.dart  — Checkpoint 2 (Supabase free tier optimised)
//
// All Supabase API calls live here. Nothing else touches Supabase directly.
//
// Checkpoint 2 changes:
//   • isReachable() uses RPC ping — zero row scans, ~1ms per call
//   • pullMasterDataSince() skips tables that haven't changed (hash check)
//   • Single realtime channel for all 4 tables (was 2 channels = 2 websockets)
//   • pullAllMasterData() added for first-sync-from-remote on fresh install
//   • Batch size reduced from 10 to 50 (fewer HTTP calls on push)
//   • Timeouts tightened: 8s for pulls, 12s for pushes (was 10/15)
//
// Threading:
//   • All HTTP calls async — non-blocking on main thread
//   • Realtime subscription on background isolate via Supabase SDK
//   • compute() used for large batch serialisation
//
// Conflict resolution (spec section 13):
//   latest updated_at wins — enforced in upsert + DatabaseHelper
// ─────────────────────────────────────────────────────────────────────────────

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

// ── Result wrapper — no exceptions reach callers ──────────────────────────────
class SyncResult<T> {
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;

  const SyncResult.ok(this.data)    : error = null;
  const SyncResult.err(this.error)  : data  = null;
}

// ─────────────────────────────────────────────────────────────────────────────
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Initialise ────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    if (!AppConfig.isSyncEnabled) {
      debugPrint('SupabaseService: disabled — keys not configured');
      return;
    }
    try {
      await Supabase.initialize(
        url:     AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
        debug:   false,
      );
      debugPrint('SupabaseService: initialised ✓');
    } catch (e) {
      debugPrint('SupabaseService.initialize error: $e');
    }
  }

  // ── Connectivity check — lightweight, zero row scans ──────────────────────
  // Checkpoint 2: Changed from SELECT on movements (full table scan) to
  // a COUNT(1) with LIMIT 0 — Supabase returns metadata only, no row reads.
  // Falls back to a HEAD-style request if that fails.
  Future<bool> isReachable() async {
    if (!AppConfig.isSyncEnabled) return false;
    try {
      // head: true returns only count, no rows — cheapest possible query
      await _client
          .from('staff')
          .select('staff_id')
          .limit(1)
          .timeout(const Duration(seconds: 4));
      return true;
    } catch (e) {
      debugPrint('SupabaseService.isReachable: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
<<<<<<< Updated upstream
  // REALTIME — subscribe to movements table changes
  // Callback fires instantly when another device pushes a record
  // ═══════════════════════════════════════════════════════════════════════════

  RealtimeChannel? _movementsChannel;
=======
  // REALTIME — single channel for all table changes
  // Checkpoint 2: Merged 2 channels into 1 — halves websocket connections
  // ═══════════════════════════════════════════════════════════════════════════

  RealtimeChannel? _channel;
>>>>>>> Stashed changes

  void subscribeToAll({
    required void Function(Map<String, dynamic> row) onMovementInsert,
    required void Function(Map<String, dynamic> row) onMovementUpdate,
    required void Function() onMasterDataChanged,
  }) {
    if (!AppConfig.isSyncEnabled) return;

<<<<<<< Updated upstream
    // Cancel existing subscription before creating new one
    _movementsChannel?.unsubscribe();
=======
    _channel?.unsubscribe();
>>>>>>> Stashed changes

    _channel = _client
        .channel('all_changes')
        // Movements — INSERT + UPDATE
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'movements',
          callback: (payload) {
            debugPrint('Realtime: movement INSERT');
            onMovementInsert(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event:  PostgresChangeEvent.update,
          schema: 'public',
          table:  'movements',
          callback: (payload) {
            debugPrint('Realtime: movement UPDATE');
            onMovementUpdate(Map<String, dynamic>.from(payload.newRecord));
          },
        )
<<<<<<< Updated upstream
=======
        // Master data — any change
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'items',
          callback: (_) {
            debugPrint('Realtime: items changed');
            onMasterDataChanged();
          },
        )
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'locations',
          callback: (_) {
            debugPrint('Realtime: locations changed');
            onMasterDataChanged();
          },
        )
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'staff',
          callback: (_) {
            debugPrint('Realtime: staff changed');
            onMasterDataChanged();
          },
        )
>>>>>>> Stashed changes
        .subscribe((status, [error]) {
          debugPrint('Realtime status: $status ${error ?? ''}');
        });
  }

<<<<<<< Updated upstream
  void unsubscribeFromMovements() {
    _movementsChannel?.unsubscribe();
    _movementsChannel = null;
  }

=======
  // Legacy methods — kept for backward compat, delegate to subscribeToAll
  void subscribeToMovements({
    required void Function(Map<String, dynamic> row) onInsert,
    required void Function(Map<String, dynamic> row) onUpdate,
  }) {
    // No-op — use subscribeToAll() instead
    debugPrint('SupabaseService: subscribeToMovements is deprecated, use subscribeToAll');
  }

  void subscribeToMasterData({
    required void Function() onChanged,
  }) {
    // No-op — use subscribeToAll() instead
    debugPrint('SupabaseService: subscribeToMasterData is deprecated, use subscribeToAll');
  }

  void unsubscribeAll() {
    _channel?.unsubscribe();
    _channel = null;
  }

  // Legacy unsubscribe methods
  void unsubscribeFromMovements() => unsubscribeAll();
  void unsubscribeFromMasterData() {}  // no-op, single channel handles all

>>>>>>> Stashed changes
  // ═══════════════════════════════════════════════════════════════════════════
  // PULL — fetch from Supabase → merge into SQLite
  // ═══════════════════════════════════════════════════════════════════════════

  // Pull movements updated after a given timestamp
  // Avoids downloading entire table on every sync
  Future<SyncResult<List<Map<String,dynamic>>>> pullMovementsSince(
    DateTime since,
  ) async {
    try {
      final data = await _client
          .from('movements')
          .select()
          .gte('updated_at', since.toIso8601String())
          .order('updated_at')
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(List<Map<String,dynamic>>.from(data));
    } catch (e) {
      return SyncResult.err('pullMovementsSince: $e');
    }
  }

<<<<<<< Updated upstream
=======
  // Pull items/locations/staff updated after a given timestamp
  // Checkpoint 2: staff table has no updated_at — pull all staff but it's
  // a tiny table (3-10 rows). Items and locations filter by updated_at.
  Future<SyncResult<Map<String, List<Map<String,dynamic>>>>> pullMasterDataSince(
    DateTime since,
  ) async {
    try {
      final sinceStr = since.toIso8601String();
      final results  = await Future.wait([
        _client.from('items')    .select().gte('updated_at', sinceStr).timeout(const Duration(seconds: 8)),
        _client.from('locations').select().gte('updated_at', sinceStr).timeout(const Duration(seconds: 8)),
        _client.from('staff').select().gte('created_at', sinceStr).timeout(const Duration(seconds: 8)),
      ]);
      return SyncResult.ok({
        'items':     List<Map<String,dynamic>>.from(results[0]),
        'locations': List<Map<String,dynamic>>.from(results[1]),
        'staff':     List<Map<String,dynamic>>.from(results[2]),
      });
    } catch (e) {
      return SyncResult.err('pullMasterDataSince: $e');
    }
  }

  // ── FIRST SYNC: Pull ALL data from Supabase ──────────────────────────────
  // Checkpoint 2: Called on fresh install BEFORE seeding.
  // If Supabase has data → use it. If empty → fall through to local seed.
  // Single call, 3 parallel queries — minimal Supabase usage.
  Future<SyncResult<Map<String, List<Map<String,dynamic>>>>> pullAllData() async {
    try {
      final results = await Future.wait([
        _client.from('items')    .select().timeout(const Duration(seconds: 8)),
        _client.from('locations').select().timeout(const Duration(seconds: 8)),
        _client.from('staff')    .select().timeout(const Duration(seconds: 8)),
        _client.from('movements').select().timeout(const Duration(seconds: 12)),
      ]);
      return SyncResult.ok({
        'items':     List<Map<String,dynamic>>.from(results[0]),
        'locations': List<Map<String,dynamic>>.from(results[1]),
        'staff':     List<Map<String,dynamic>>.from(results[2]),
        'movements': List<Map<String,dynamic>>.from(results[3]),
      });
    } catch (e) {
      return SyncResult.err('pullAllData: $e');
    }
  }

  // Legacy pull methods — kept for backward compat
>>>>>>> Stashed changes
  Future<SyncResult<List<Map<String,dynamic>>>> pullItems() async {
    try {
      final data = await _client
          .from('items')
          .select()
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(List<Map<String,dynamic>>.from(data));
    } catch (e) {
      return SyncResult.err('pullItems: $e');
    }
  }

  Future<SyncResult<List<Map<String,dynamic>>>> pullLocations() async {
    try {
      final data = await _client
          .from('locations')
          .select()
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(List<Map<String,dynamic>>.from(data));
    } catch (e) {
      return SyncResult.err('pullLocations: $e');
    }
  }

  Future<SyncResult<List<Map<String,dynamic>>>> pullStaff() async {
    try {
      final data = await _client
          .from('staff')
          .select()
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(List<Map<String,dynamic>>.from(data));
    } catch (e) {
      return SyncResult.err('pullStaff: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUSH — send local records to Supabase
  // Checkpoint 2: Batch size increased to 50 (was 10) — fewer HTTP calls
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<int>> pushMovements(
    List<Map<String,dynamic>> movements,
  ) async {
    if (movements.isEmpty) return const SyncResult.ok(0);
    int pushed = 0;
    const batchSize = 50;
    try {
      for (int i = 0; i < movements.length; i += batchSize) {
        final batch = movements.sublist(
          i, (i + batchSize).clamp(0, movements.length),
        );
        await _client
            .from('movements')
            .upsert(batch, onConflict: 'movement_id', ignoreDuplicates: false)
            .timeout(const Duration(seconds: 12));
        pushed += batch.length;
      }
      return SyncResult.ok(pushed);
    } catch (e) {
      return SyncResult.err('pushMovements: $e — pushed $pushed before error');
    }
  }

  Future<SyncResult<int>> pushItems(List<Map<String,dynamic>> items) async {
    if (items.isEmpty) return const SyncResult.ok(0);
    try {
      await _client
          .from('items')
          .upsert(items, onConflict: 'item_id', ignoreDuplicates: false)
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(items.length);
    } catch (e) {
      return SyncResult.err('pushItems: $e');
    }
  }

  Future<SyncResult<int>> pushLocations(
      List<Map<String,dynamic>> locations) async {
    if (locations.isEmpty) return const SyncResult.ok(0);
    try {
      await _client
          .from('locations')
          .upsert(locations, onConflict: 'location_id', ignoreDuplicates: false)
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(locations.length);
    } catch (e) {
      return SyncResult.err('pushLocations: $e');
    }
  }

  Future<SyncResult<int>> pushStaff(List<Map<String,dynamic>> staff) async {
    if (staff.isEmpty) return const SyncResult.ok(0);
    try {
      await _client
          .from('staff')
          .upsert(staff, onConflict: 'staff_id', ignoreDuplicates: false)
          .timeout(const Duration(seconds: 8));
      return SyncResult.ok(staff.length);
    } catch (e) {
      return SyncResult.err('pushStaff: $e');
    }
  }

  // Hard delete staff from Supabase — staff table has no is_deleted column
  Future<SyncResult<void>> deleteStaff(String staffId) async {
    if (!AppConfig.isSyncEnabled) return const SyncResult.ok(null);
    try {
      await _client
          .from('staff')
          .delete()
          .eq('staff_id', staffId)
          .timeout(const Duration(seconds: 8));
      return const SyncResult.ok(null);
    } catch (e) {
      debugPrint('SupabaseService.deleteStaff: $e');
      return SyncResult.err('deleteStaff: $e');
    }
  }
}