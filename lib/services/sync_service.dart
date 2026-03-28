// ─────────────────────────────────────────────────────────────────────────────
// sync_service.dart — Checkpoint 3
//
// Changes from Checkpoint 2:
//   • startAutoSync() accepts onMasterDataChanged + onStockInvalidated callbacks
//   • subscribeToAll() used — single channel for all 4 tables
//   • _invalidateReachabilityCache() called on network restore
//     → pending movements flush immediately when internet returns
//   • firstSyncFromRemote() returns SyncFirstResult enum
//     → success / supabaseEmpty / unreachable — no ambiguous bool
//   • Periodic sync interval kept at 30s
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../config/app_config.dart';
import 'supabase_service.dart';

enum SyncStatus      { idle, syncing, done, error }
enum SyncFirstResult { success, supabaseEmpty, unreachable }

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  // ── State ──────────────────────────────────────────────────────────────────
  SyncStatus _status      = SyncStatus.idle;
  String?    _lastError;
  DateTime?  _lastSyncAt;
  bool       _isSyncing   = false;
  int        _pushedCount = 0;

  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusCtrl.stream;
  SyncStatus get status      => _status;
  String?    get lastError   => _lastError;
  DateTime?  get lastSyncAt  => _lastSyncAt;
  int        get pushedCount => _pushedCount;

  // ── Callbacks ──────────────────────────────────────────────────────────────
  void Function(Map<String,dynamic>)? _onRemoteMovement;
  void Function(List<String> ids)?    _onMovementsSynced;
  void Function()?                    _onMasterDataChanged;
  void Function()?                    _onStockInvalidated;

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer?              _periodicTimer;
  StreamSubscription? _connectivitySub;

  // ── Reachability cache ─────────────────────────────────────────────────────
  bool?     _reachableCache;
  DateTime? _reachableCacheTime;
  static const _reachableCacheTtl = Duration(seconds: 30);

  Future<bool> _isReachableCached() async {
    final now = DateTime.now();
    if (_reachableCache != null &&
        _reachableCacheTime != null &&
        now.difference(_reachableCacheTime!) < _reachableCacheTtl) {
      return _reachableCache!;
    }
    final result = await SupabaseService.instance.isReachable();
    _reachableCache     = result;
    _reachableCacheTime = now;
    return result;
  }

  void _invalidateReachabilityCache() {
    _reachableCache     = null;
    _reachableCacheTime = null;
  }

  // ── Start ──────────────────────────────────────────────────────────────────
  void startAutoSync({
    void Function(Map<String,dynamic>)? onRemoteMovement,
    void Function(List<String> ids)?    onMovementsSynced,
    void Function()?                    onMasterDataChanged,
    void Function()?                    onStockInvalidated,
  }) {
    if (!AppConfig.isSyncEnabled) {
      debugPrint('SyncService: disabled — keys not configured');
      return;
    }

    _onRemoteMovement    = onRemoteMovement;
    _onMovementsSynced   = onMovementsSynced;
    _onMasterDataChanged = onMasterDataChanged;
    _onStockInvalidated  = onStockInvalidated;

    // Single channel — movements + master data
    SupabaseService.instance.subscribeToAll(
      onMovementInsert:  _handleRemoteMovement,
      onMovementUpdate:  _handleRemoteMovement,
      onMasterDataChanged: _handleMasterDataChanged,
    );

    // Periodic sync every 30s — catches missed realtime events
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sync(silent: true),
    );

    // Sync immediately on network restore — clear cache first
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online) {
        debugPrint('SyncService: network restored — clearing cache + syncing');
        _invalidateReachabilityCache();
        sync(silent: true);
      }
    });

    // Initial sync after 3s startup delay
    Future.delayed(const Duration(seconds: 3), () => sync(silent: true));

    debugPrint('SyncService: started — realtime + periodic(30s)');
  }

  void stopAutoSync() {
    SupabaseService.instance.unsubscribeAll();
    _periodicTimer?.cancel();
    _connectivitySub?.cancel();
    _periodicTimer   = null;
    _connectivitySub = null;
  }

  void dispose() {
    stopAutoSync();
    _statusCtrl.close();
  }

  // ── Handle realtime movement ───────────────────────────────────────────────
  Future<void> _handleRemoteMovement(Map<String,dynamic> row) async {
    try {
      final changed = await DatabaseHelper.instance.upsertMovementFromRemote(row);
      if (changed) {
        _onRemoteMovement?.call(row);
        _onStockInvalidated?.call();
        debugPrint('SyncService: realtime movement merged — ${row['movement_id']}');
      } else {
        debugPrint('SyncService: realtime echo skipped — ${row['movement_id']}');
      }
    } catch (e) {
      debugPrint('SyncService._handleRemoteMovement error: $e');
    }
  }

  // ── Handle realtime master data change ────────────────────────────────────
  Timer? _masterDataDebounce;
  void _handleMasterDataChanged() {
    _masterDataDebounce?.cancel();
    _masterDataDebounce = Timer(const Duration(milliseconds: 500), () {
      debugPrint('SyncService: master data changed — pulling');
      _pullMasterData().then((_) => _onMasterDataChanged?.call());
    });
  }

  // ── Broadcast status ───────────────────────────────────────────────────────
  void _setStatus(SyncStatus s, {String? error}) {
    _status    = s;
    _lastError = error;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  // ── Master data dirty flag ─────────────────────────────────────────────────
  bool      _masterDataDirty = true;
  DateTime? _lastMasterPush;

  void markMasterDirty() => _masterDataDirty = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // FIRST SYNC — fresh install only
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncFirstResult> firstSyncFromRemote() async {
    if (!AppConfig.isSyncEnabled) return SyncFirstResult.unreachable;

    final reachable = await SupabaseService.instance.isReachable();
    if (!reachable) {
      debugPrint('SyncService.firstSyncFromRemote: not reachable');
      return SyncFirstResult.unreachable;
    }

    try {
      debugPrint('SyncService: first sync — pulling all data from Supabase');
      final result = await SupabaseService.instance.pullAllData();
      if (!result.isSuccess) return SyncFirstResult.unreachable;

      final data = result.data!;
      final db   = DatabaseHelper.instance;

      final items     = data['items']     ?? [];
      final locations = data['locations'] ?? [];
      final staff     = data['staff']     ?? [];
      final movements = data['movements'] ?? [];

      // Supabase is reachable but empty — first device ever
      if (items.isEmpty && staff.isEmpty) {
        return SyncFirstResult.supabaseEmpty;
      }

      // Write all data to local SQLite
      for (final row in items)     { await db.upsertItemFromRemote(row); }
      for (final row in locations) { await db.upsertLocationFromRemote(row); }
      for (final row in staff)     { await db.upsertStaffFromRemote(row); }
      for (final row in movements) { await db.upsertMovementFromRemote(row); }

      debugPrint('SyncService.firstSyncFromRemote: done — '
          'items:${items.length} locations:${locations.length} '
          'staff:${staff.length} movements:${movements.length}');

      _lastSyncAt = DateTime.now();
      return SyncFirstResult.success;

    } catch (e) {
      debugPrint('SyncService.firstSyncFromRemote error: $e');
      return SyncFirstResult.unreachable;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<_SyncSummary>> sync({bool silent = false}) async {
    if (_isSyncing) return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    if (!AppConfig.isSyncEnabled) return SyncResult.err('Sync not configured');

    final reachable = await _isReachableCached();
    if (!reachable) {
      debugPrint('SyncService: not reachable — skipped');
      return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    }

    _isSyncing = true;
    if (!silent) _setStatus(SyncStatus.syncing);
    debugPrint('SyncService: sync started (silent=$silent)');

    try {
      await _pushMasterData();

      final pushResult = await _pushPending();
      if (!pushResult.isSuccess) throw Exception(pushResult.error);
      final pushed = pushResult.data ?? 0;

      final pullResult = await _pullAndMerge();
      final pulled = pullResult.data ?? 0;

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

  // ── Push pending movements ─────────────────────────────────────────────────
  Future<SyncResult<int>> _pushPending() async {
    final db      = DatabaseHelper.instance;
    final pending = await db.getPendingMovements();
    if (pending.isEmpty) return const SyncResult.ok(0);

    debugPrint('SyncService: pushing ${pending.length} movements');

    final serialised = pending.length > 50
        ? await compute(_serialiseMovements, pending)
        : _serialiseMovements(pending);

    final result = await SupabaseService.instance.pushMovements(serialised);
    if (!result.isSuccess) return SyncResult.err(result.error);

    final ids = pending.map((m) => m['movement_id'] as String).toList();
    await db.markMovementsSynced(ids);
    _onMovementsSynced?.call(ids);
    return SyncResult.ok(result.data ?? 0);
  }

  // ── Push master data ───────────────────────────────────────────────────────
  Future<void> _pushMasterData() async {
    if (!_masterDataDirty) return;
    final now = DateTime.now();
    if (_lastMasterPush != null &&
        now.difference(_lastMasterPush!).inSeconds < 60) return;

    try {
      _lastMasterPush  = now;
      _masterDataDirty = false;

      final db      = DatabaseHelper.instance;
      final results = await Future.wait([
        db.getAllItems(), db.getAllLocations(), db.getStaff(),
      ]);

      await SupabaseService.instance.pushItems(_serialiseMaster(results[0]));
      await SupabaseService.instance.pushLocations(_serialiseMaster(results[1]));
      await SupabaseService.instance.pushStaff(_serialiseMaster(results[2]));

      debugPrint('SyncService: master data pushed');
    } catch (e) {
      _masterDataDirty = true;
      debugPrint('SyncService._pushMasterData: $e');
    }
  }

  // ── Pull movements since last sync ─────────────────────────────────────────
  Future<SyncResult<int>> _pullAndMerge() async {
    try {
      final db    = DatabaseHelper.instance;
      final since = _lastSyncAt != null
          ? _lastSyncAt!.subtract(const Duration(minutes: 5))
          : DateTime.now().subtract(const Duration(days: 30));

      await _pullMasterData();

      final result = await SupabaseService.instance.pullMovementsSince(since);
      if (!result.isSuccess) return SyncResult.err(result.error);

      final remote = result.data!;
      if (remote.isEmpty) return const SyncResult.ok(0);

      int merged = 0;
      for (final row in remote) {
        try {
          final changed = await db.upsertMovementFromRemote(row);
          if (changed) {
            _onRemoteMovement?.call(row);
            merged++;
          }
        } catch (e) {
          debugPrint('SyncService: merge skip — $e');
        }
      }

      if (merged > 0) _onStockInvalidated?.call();
      debugPrint('SyncService: pulled $merged movements');
      return SyncResult.ok(merged);
    } catch (e) {
      return SyncResult.err('_pullAndMerge: $e');
    }
  }

  // ── Pull master data ───────────────────────────────────────────────────────
  Future<void> _pullMasterData() async {
    try {
      final since = _lastSyncAt != null
          ? _lastSyncAt!.subtract(const Duration(minutes: 5))
          : DateTime.now().subtract(const Duration(days: 30));

      final result = await SupabaseService.instance.pullMasterDataSince(since);
      if (!result.isSuccess) {
        debugPrint('SyncService._pullMasterData: ${result.error}');
        return;
      }

      final data = result.data!;
      final db   = DatabaseHelper.instance;

      for (final row in data['items']     ?? []) { await db.upsertItemFromRemote(row); }
      for (final row in data['locations'] ?? []) { await db.upsertLocationFromRemote(row); }
      for (final row in data['staff']     ?? []) { await db.upsertStaffFromRemote(row); }

      final totalChanged = (data['items']?.length     ?? 0) +
                           (data['locations']?.length ?? 0) +
                           (data['staff']?.length     ?? 0);

      if (totalChanged > 0) {
        debugPrint('SyncService: pulled master data — $totalChanged records');
      }
    } catch (e) {
      debugPrint('SyncService._pullMasterData error: $e');
    }
  }

  // ── Serialise helpers ──────────────────────────────────────────────────────
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