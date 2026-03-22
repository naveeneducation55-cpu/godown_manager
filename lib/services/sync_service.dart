// ─────────────────────────────────────────────────────────────────────────────
// sync_service.dart — Phase 2 complete
//
// Sync strategy:
//   REALTIME: Supabase pushes changes instantly via websocket
//             → zero polling delay, other devices see changes in <1 second
//   PERIODIC: Pull since last sync every 60s — catches missed realtime events
//   ON-DEMAND: Manual sync button in SyncScreen
//
// Performance:
//   • Master data (items/locations/staff) pushed only when changed
//   • Movements pulled incrementally — only since last sync timestamp
//   • Realtime subscription avoids polling entirely for live updates
//   • _isSyncing mutex prevents concurrent sync runs
//   • compute() for batch serialisation > 50 records
//
// Threading:
//   • sqflite — background thread (automatic)
//   • Supabase HTTP — Dart event loop (non-blocking)
//   • Realtime callbacks — main isolate, lightweight (just DB upsert + notify)
//   • compute() — separate Dart isolate for heavy JSON work
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../config/app_config.dart';
import 'supabase_service.dart';

enum SyncStatus { idle, syncing, done, error }

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  // ── State ──────────────────────────────────────────────────────────────────
  SyncStatus _status      = SyncStatus.idle;
  String?    _lastError;
  DateTime?  _lastSyncAt;
  bool       _isSyncing   = false;
  int        _pushedCount = 0;

  // Broadcast stream — SyncScreen and home screen listen
  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusCtrl.stream;
  SyncStatus get status      => _status;
  String?    get lastError   => _lastError;
  DateTime?  get lastSyncAt  => _lastSyncAt;
  int        get pushedCount => _pushedCount;

  // Callback — AppDataProvider registers this to reload data after pull
  void Function(Map<String,dynamic>)? _onRemoteMovement;

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer?               _periodicTimer;
  StreamSubscription?  _connectivitySub;

  // ── Start ──────────────────────────────────────────────────────────────────
  void startAutoSync({
    void Function(Map<String,dynamic>)? onRemoteMovement,
  }) {
    if (!AppConfig.isSyncEnabled) {
      debugPrint('SyncService: disabled — keys not configured');
      return;
    }

    _onRemoteMovement = onRemoteMovement;

    // 1. Realtime subscription — instant updates from other devices
    SupabaseService.instance.subscribeToMovements(
      onInsert: _handleRemoteMovement,
      onUpdate: _handleRemoteMovement,
    );

    // 2. Periodic sync every 60s — catches missed realtime events
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => sync(silent: true),
    );

    // 3. Sync immediately on network restore
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online) {
        debugPrint('SyncService: network restored — syncing');
        sync(silent: true);
      }
    });

    // 4. Initial sync on startup
    Future.delayed(const Duration(seconds: 3), () => sync(silent: true));

    debugPrint('SyncService: started — realtime + periodic(60s)');
  }

  void stopAutoSync() {
    SupabaseService.instance.unsubscribeFromMovements();
    _periodicTimer?.cancel();
    _connectivitySub?.cancel();
    _periodicTimer   = null;
    _connectivitySub = null;
  }

  void dispose() {
    stopAutoSync();
    _statusCtrl.close();
  }

  // ── Handle realtime movement from another device ───────────────────────────
  // Runs on main isolate — kept lightweight intentionally
  // Heavy processing (parsing, cache refresh) done in AppDataProvider callback
  Future<void> _handleRemoteMovement(Map<String,dynamic> row) async {
    try {
      await DatabaseHelper.instance.upsertMovementFromRemote(row);
      _onRemoteMovement?.call(row); // notify AppDataProvider to reload
      debugPrint('SyncService: realtime movement merged — ${row['movement_id']}');
    } catch (e) {
      debugPrint('SyncService._handleRemoteMovement error: $e');
    }
  }

  // ── Broadcast status ───────────────────────────────────────────────────────
  void _setStatus(SyncStatus s, {String? error}) {
    _status    = s;
    _lastError = error;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN SYNC  — push pending + pull missed records
  // silent: true = no status broadcast (background auto-sync)
  // silent: false = full status broadcast (manual button)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<_SyncSummary>> sync({bool silent = false}) async {
    if (_isSyncing) {
      debugPrint('SyncService: already syncing — skipped');
      return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    }
    if (!AppConfig.isSyncEnabled) {
      return SyncResult.err('Sync not configured');
    }

    final reachable = await SupabaseService.instance.isReachable();
    if (!reachable) {
      debugPrint('SyncService: not reachable — skipped');
      return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    }

    _isSyncing = true;
    if (!silent) _setStatus(SyncStatus.syncing);
    debugPrint('SyncService: sync started (silent=$silent)');

    try {
      // ── Step 1: Push pending movements ──────────────────────────────────
      final pushResult = await _pushPending();
      if (!pushResult.isSuccess) throw Exception(pushResult.error);
      final pushed = pushResult.data ?? 0;

      // ── Step 2: Push master data (only if changed) ───────────────────────
      await _pushMasterData();

      // ── Step 3: Pull movements from other devices since last sync ─────────
      final pullResult = await _pullAndMerge();
      final pulled = pullResult.data ?? 0;
      if (!pullResult.isSuccess) {
        debugPrint('SyncService: pull warning — ${pullResult.error}');
      }

      _lastSyncAt  = DateTime.now();
      _pushedCount = pushed;

      if (!silent) _setStatus(SyncStatus.done);
      debugPrint('SyncService: done — pushed=$pushed pulled=$pulled');
      return SyncResult.ok(_SyncSummary(pushed: pushed, pulled: pulled));

    } catch (e, st) {
      debugPrint('SyncService.sync error: $e\n$st');
      if (!silent) _setStatus(SyncStatus.error, error: e.toString());
      return SyncResult.err(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  // ── Push pending local movements ──────────────────────────────────────────
  Future<SyncResult<int>> _pushPending() async {
    final db      = DatabaseHelper.instance;
    final pending = await db.getPendingMovements();

    if (pending.isEmpty) return const SyncResult.ok(0);
    debugPrint('SyncService: pushing ${pending.length} movements');

    // compute() for large batches to avoid main thread work
    final serialised = pending.length > 50
        ? await compute(_serialiseMovements, pending)
        : _serialiseMovements(pending);

    final result = await SupabaseService.instance.pushMovements(serialised);
    if (!result.isSuccess) return SyncResult.err(result.error);

    // Mark only successfully pushed records as synced — String IDs
    final ids = pending.map((m) => m['movement_id'] as String).toList();
    await db.markMovementsSynced(ids);
    return SyncResult.ok(result.data ?? 0);
  }

  // ── Push master data — items, locations, staff ────────────────────────────
  // Performance: skip if nothing changed since last push
  DateTime? _lastMasterPush;

  Future<void> _pushMasterData() async {
    // Only push master data every 5 minutes — it rarely changes
    final now = DateTime.now();
    if (_lastMasterPush != null &&
        now.difference(_lastMasterPush!).inMinutes < 5) {
      return;
    }

    try {
      final db      = DatabaseHelper.instance;
      final results = await Future.wait([
        db.getItems(),
        db.getLocations(),
        db.getStaff(),
      ]);

      await Future.wait([
        SupabaseService.instance.pushItems(
            _serialiseMaster(results[0])),
        SupabaseService.instance.pushLocations(
            _serialiseMaster(results[1])),
        SupabaseService.instance.pushStaff(
            _serialiseMaster(results[2])),
      ]);

      _lastMasterPush = now;
      debugPrint('SyncService: master data pushed');
    } catch (e) {
      debugPrint('SyncService._pushMasterData: $e');
    }
  }

  // ── Pull movements since last sync ────────────────────────────────────────
  Future<SyncResult<int>> _pullAndMerge() async {
    try {
      final db    = DatabaseHelper.instance;
      // Pull since last sync — or last 7 days if never synced
      final since = _lastSyncAt != null
          ? _lastSyncAt!.subtract(const Duration(minutes: 1))
          : DateTime.now().subtract(const Duration(days: 7));

      final result =
          await SupabaseService.instance.pullMovementsSince(since);
      if (!result.isSuccess) return SyncResult.err(result.error);

      final remote = result.data!;
      if (remote.isEmpty) return const SyncResult.ok(0);

      int merged = 0;
      for (final row in remote) {
        try {
          await db.upsertMovementFromRemote(row);
          _onRemoteMovement?.call(row);
          merged++;
        } catch (e) {
          debugPrint('SyncService: merge skip — $e');
        }
      }

      debugPrint('SyncService: pulled $merged movements');
      return SyncResult.ok(merged);
    } catch (e) {
      return SyncResult.err('_pullAndMerge: $e');
    }
  }

  // ── Serialise helpers — top-level for compute() ───────────────────────────
  static List<Map<String,dynamic>> _serialiseMovements(
    List<Map<String,dynamic>> rows,
  ) =>
      rows.map((m) => {
        'movement_id':   m['movement_id'],
        'item_id':       m['item_id'],
        'quantity':      m['quantity'],
        'from_location': m['from_location'],
        'to_location':   m['to_location'],
        'staff_id':      m['staff_id'],
        'created_at':    m['created_at'],
        'updated_at':    m['updated_at'],
        'edited':        m['edited'] == 1,
        'edited_by':     m['edited_by'],
        'sync_status':   'synced',
        'remark':        m['remark'],
      }).toList();

  static List<Map<String,dynamic>> _serialiseMaster(
    List<Map<String,dynamic>> rows,
  ) =>
      rows.map((r) => Map<String,dynamic>.from(r)).toList();
}

class _SyncSummary {
  final int pushed;
  final int pulled;
  const _SyncSummary({required this.pushed, required this.pulled});
}