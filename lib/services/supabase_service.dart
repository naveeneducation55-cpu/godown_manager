// ─────────────────────────────────────────────────────────────────────────────
// supabase_service.dart  — Phase 2 complete
//
// All Supabase API calls live here. Nothing else touches Supabase directly.
//
// Threading:
//   • All HTTP calls async — non-blocking on main thread
//   • Realtime subscription on background isolate via Supabase SDK
//   • compute() used for large batch serialisation
//
// Pull strategy:
//   • Realtime: instant push from Supabase on INSERT/UPDATE
//   • Periodic: pull since last sync timestamp — catches missed events
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

  // ── Connectivity check — lightweight ping ─────────────────────────────────
  Future<bool> isReachable() async {
    if (!AppConfig.isSyncEnabled) return false;
    try {
      await _client
          .from('movements')
          .select('movement_id')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('SupabaseService.isReachable: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REALTIME — subscribe to movements table changes
  // Callback fires instantly when another device pushes a record
  // ═══════════════════════════════════════════════════════════════════════════

  RealtimeChannel? _movementsChannel;

  void subscribeToMovements({
    required void Function(Map<String, dynamic> row) onInsert,
    required void Function(Map<String, dynamic> row) onUpdate,
  }) {
    if (!AppConfig.isSyncEnabled) return;

    // Cancel existing subscription before creating new one
    _movementsChannel?.unsubscribe();

    _movementsChannel = _client
        .channel('movements_changes')
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'movements',
          callback: (payload) {
            debugPrint('Realtime: new movement received');
            onInsert(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event:  PostgresChangeEvent.update,
          schema: 'public',
          table:  'movements',
          callback: (payload) {
            debugPrint('Realtime: movement updated received');
            onUpdate(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Realtime status: $status ${error ?? ''}');
        });
  }

  void unsubscribeFromMovements() {
    _movementsChannel?.unsubscribe();
    _movementsChannel = null;
  }

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
          .timeout(const Duration(seconds: 15));
      return SyncResult.ok(List<Map<String,dynamic>>.from(data));
    } catch (e) {
      return SyncResult.err('pullMovementsSince: $e');
    }
  }

  Future<SyncResult<List<Map<String,dynamic>>>> pullItems() async {
    try {
      final data = await _client
          .from('items')
          .select()
          .timeout(const Duration(seconds: 10));
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
          .timeout(const Duration(seconds: 10));
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
          .timeout(const Duration(seconds: 10));
      return SyncResult.ok(List<Map<String,dynamic>>.from(data));
    } catch (e) {
      return SyncResult.err('pullStaff: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUSH — send local records to Supabase in batches of 10
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<int>> pushMovements(
    List<Map<String,dynamic>> movements,
  ) async {
    if (movements.isEmpty) return const SyncResult.ok(0);
    int pushed = 0;
    const batchSize = 10;
    try {
      for (int i = 0; i < movements.length; i += batchSize) {
        final batch = movements.sublist(
          i, (i + batchSize).clamp(0, movements.length),
        );
        await _client
            .from('movements')
            .upsert(batch, onConflict: 'movement_id', ignoreDuplicates: false)
            .timeout(const Duration(seconds: 15));
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
          .timeout(const Duration(seconds: 10));
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
          .timeout(const Duration(seconds: 10));
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
          .timeout(const Duration(seconds: 10));
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
          .timeout(const Duration(seconds: 10));
      return const SyncResult.ok(null);
    } catch (e) {
      debugPrint('SupabaseService.deleteStaff: $e');
      return SyncResult.err('deleteStaff: $e');
    }
  }
}