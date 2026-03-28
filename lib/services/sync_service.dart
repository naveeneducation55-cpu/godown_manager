// ─────────────────────────────────────────────────────────────────────────────
// sync_service.dart — Checkpoint 3
//
// Fixes:
//   • SyncFirstResult enum — success / supabaseEmpty / unreachable
//   • _isReachableCached() cleared IMMEDIATELY on connectivity restore
//     → pending movements flush the moment internet comes back
//   • _pullAndMerge() overlap buffer 5 min (was 2 min)
//     → movements missed during long offline periods are caught on reconnect
//   • onStockInvalidated callback — provider refreshes stock after remote merge
//   • Periodic sync 30s (was 90s) for more responsive live updates
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../config/app_config.dart';
import 'supabase_service.dart';

enum SyncStatus { idle, syncing, done, error }

// Checkpoint 3: Replaces bool return from firstSyncFromRemote()
enum SyncFirstResult { success, supabaseEmpty, unreachable }

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

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

  void Function(Map<String,dynamic>)? _onRemoteMovement;
<<<<<<< Updated upstream
  // Callback — called after successful push so provider updates in-memory sync status
  void Function(List<String> ids)? _onMovementsSynced;
=======
  void Function(List<String> ids)?    _onMovementsSynced;
  void Function()?                    _onMasterDataChanged;
  void Function()?                    _onStockInvalidated;   // Checkpoint 3
>>>>>>> Stashed changes

  Timer?               _periodicTimer;
  StreamSubscription?  _connectivitySub;

  bool?     _lastReachable;
  DateTime? _lastReachableCheck;
  static const _reachableCacheDuration = Duration(seconds: 30);

  Future<bool> _isReachableCached() async {
    if (_lastReachableCheck != null &&
        DateTime.now().difference(_lastReachableCheck!) < _reachableCacheDuration &&
        _lastReachable != null) {
      return _lastReachable!;
    }
    final result        = await SupabaseService.instance.isReachable();
    _lastReachable      = result;
    _lastReachableCheck = DateTime.now();
    return result;
  }

  void _invalidateReachabilityCache() {
    _lastReachable      = null;
    _lastReachableCheck = null;
  }

  Future<bool> isSupabaseReachable() => _isReachableCached();

  // ═══════════════════════════════════════════════════════════════════════════
  // FIRST SYNC
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
      if (!result.isSuccess) {
        debugPrint('SyncService.firstSyncFromRemote: pull failed — ${result.error}');
        return SyncFirstResult.unreachable;
      }

      final data         = result.data!;
      final itemRows     = data['items']     as List? ?? [];
      final locationRows = data['locations'] as List? ?? [];
      final staffRows    = data['staff']     as List? ?? [];
      final movementRows = data['movements'] as List? ?? [];

      if (itemRows.isEmpty && locationRows.isEmpty && staffRows.isEmpty) {
        debugPrint('SyncService.firstSyncFromRemote: Supabase empty — seed locally');
        return SyncFirstResult.supabaseEmpty;
      }

      final db = DatabaseHelper.instance;
      for (final row in itemRows)     { await db.upsertItemFromRemote(row as Map<String,dynamic>); }
      for (final row in locationRows) { await db.upsertLocationFromRemote(row as Map<String,dynamic>); }
      for (final row in staffRows)    { await db.upsertStaffFromRemote(row as Map<String,dynamic>); }
      for (final row in movementRows) { await db.upsertMovementFromRemote(row as Map<String,dynamic>); }

      _lastSyncAt      = DateTime.now();
      _masterDataDirty = false;

      debugPrint('SyncService.firstSyncFromRemote: done — '
          'items:${itemRows.length} locations:${locationRows.length} '
          'staff:${staffRows.length} movements:${movementRows.length}');
      return SyncFirstResult.success;

    } catch (e, st) {
      debugPrint('SyncService.firstSyncFromRemote error: $e\n$st');
      return SyncFirstResult.unreachable;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // START AUTO SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  void startAutoSync({
    void Function(Map<String,dynamic>)? onRemoteMovement,
    void Function(List<String> ids)?    onMovementsSynced,
<<<<<<< Updated upstream
=======
    void Function()?                    onMasterDataChanged,
    void Function()?                    onStockInvalidated,
>>>>>>> Stashed changes
  }) {
    if (!AppConfig.isSyncEnabled) {
      debugPrint('SyncService: disabled — keys not configured');
      return;
    }

<<<<<<< Updated upstream
    _onRemoteMovement  = onRemoteMovement;
    _onMovementsSynced = onMovementsSynced;

    // 1. Realtime subscription — instant updates from other devices
    SupabaseService.instance.subscribeToMovements(
      onInsert: _handleRemoteMovement,
      onUpdate: _handleRemoteMovement,
    );

    // 2. Periodic sync every 60s — catches missed realtime events
=======
    _onRemoteMovement    = onRemoteMovement;
    _onMovementsSynced   = onMovementsSynced;
    _onMasterDataChanged = onMasterDataChanged;
    _onStockInvalidated  = onStockInvalidated;

    SupabaseService.instance.subscribeToAll(
      onMovementInsert:    _handleRemoteMovement,
      onMovementUpdate:    _handleRemoteMovement,
      onMasterDataChanged: _handleMasterDataChanged,
    );

    // 30s periodic — faster catchup for missed realtime events
>>>>>>> Stashed changes
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sync(silent: true),
    );

<<<<<<< Updated upstream
    // 3. Sync immediately on network restore
    // connectivity_plus 5.0.2 on Android emits single ConnectivityResult
=======
    // Checkpoint 3: clear reachability cache immediately on reconnect
    // so pending movements flush right away — not after 30s cache window
>>>>>>> Stashed changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online) {
        debugPrint('SyncService: network restored — clearing cache + syncing');
        _invalidateReachabilityCache();
        sync(silent: true);
      }
    });

<<<<<<< Updated upstream
    // 4. Initial sync on startup
=======
>>>>>>> Stashed changes
    Future.delayed(const Duration(seconds: 3), () => sync(silent: true));
    debugPrint('SyncService: started — realtime + periodic(30s)');
  }

  void stopAutoSync() {
<<<<<<< Updated upstream
    SupabaseService.instance.unsubscribeFromMovements();
=======
    SupabaseService.instance.unsubscribeAll();
>>>>>>> Stashed changes
    _periodicTimer?.cancel();
    _connectivitySub?.cancel();
    _periodicTimer   = null;
    _connectivitySub = null;
  }

  void dispose() {
    stopAutoSync();
    _statusCtrl.close();
  }

  // Checkpoint 3: triggers stock refresh after every realtime movement merge
  Future<void> _handleRemoteMovement(Map<String,dynamic> row) async {
    try {
      final changed = await DatabaseHelper.instance.upsertMovementFromRemote(row);
      // Only notify provider if data actually changed — prevents echo loop
      // when this device's own push comes back via realtime subscription
      if (changed) {
        _onRemoteMovement?.call(row);
        _onStockInvalidated?.call();   // ← stock screen updates instantly
        debugPrint('SyncService: realtime movement merged — ${row['movement_id']}');
      } else {
        debugPrint('SyncService: realtime echo skipped — ${row['movement_id']}');
      }
    } catch (e) {
      debugPrint('SyncService._handleRemoteMovement error: $e');
    }
  }

<<<<<<< Updated upstream
  // ── Broadcast status ───────────────────────────────────────────────────────
=======
  Timer? _masterDataDebounce;
  void _handleMasterDataChanged() {
    _masterDataDebounce?.cancel();
    _masterDataDebounce = Timer(const Duration(milliseconds: 500), () {
      debugPrint('SyncService: master data changed — pulling from Supabase');
      _pullMasterData().then((_) => _onMasterDataChanged?.call());
    });
  }

>>>>>>> Stashed changes
  void _setStatus(SyncStatus s, {String? error}) {
    _status    = s;
    _lastError = error;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<_SyncSummary>> sync({bool silent = false}) async {
    if (_isSyncing) {
      debugPrint('SyncService: already syncing — skipped');
      return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    }
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
      final pulled     = pullResult.data ?? 0;
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

<<<<<<< Updated upstream
  // ── Push master data — items, locations, staff ────────────────────────────
  // Runs on first sync always, then throttled to once every 5 minutes.
  // Uses upsert — existing records update, new records insert. Safe to re-run.
  DateTime? _lastMasterPush;

  Future<void> _pushMasterData() async {
    final now = DateTime.now();
    if (_lastMasterPush != null &&
        now.difference(_lastMasterPush!).inMinutes < 5) {
      return;
    }

    try {
=======
  DateTime? _lastMasterPush;
  bool      _masterDataDirty = true;

  void markMasterDirty() => _masterDataDirty = true;

  Future<void> _pushMasterData() async {
    if (!_masterDataDirty) return;
    final now = DateTime.now();
    if (_lastMasterPush != null &&
        now.difference(_lastMasterPush!).inSeconds < 120) return;

    try {
      _lastMasterPush  = now;
      _masterDataDirty = false;

>>>>>>> Stashed changes
      final db      = DatabaseHelper.instance;
      // Set timestamp before push — prevents second call within 5 min
      // even if this call is still in progress
      _lastMasterPush = now;

      final results = await Future.wait([
        db.getAllItems(),
        db.getAllLocations(),
        db.getStaff(),
      ]);

      await SupabaseService.instance.pushItems(_serialiseMaster(results[0]));
      await SupabaseService.instance.pushLocations(_serialiseMaster(results[1]));
      await SupabaseService.instance.pushStaff(_serialiseMaster(results[2]));
      debugPrint('SyncService: master data pushed');
    } catch (e) {
<<<<<<< Updated upstream
=======
      _masterDataDirty = true;
>>>>>>> Stashed changes
      debugPrint('SyncService._pushMasterData: $e');
    }
  }

  // Checkpoint 3: 5-min overlap buffer (was 2 min) — catches movements
  // missed during long offline gaps when device comes back online
  Future<SyncResult<int>> _pullAndMerge() async {
    try {
      final db    = DatabaseHelper.instance;
      // Pull since last sync — or last 7 days if never synced
      final since = _lastSyncAt != null
          ? _lastSyncAt!.subtract(const Duration(minutes: 5))
          : DateTime.now().subtract(const Duration(days: 30));

<<<<<<< Updated upstream
      final result =
          await SupabaseService.instance.pullMovementsSince(since);
=======
      await _pullMasterData();

      final result = await SupabaseService.instance.pullMovementsSince(since);
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
  // ── Serialise helpers — top-level for compute() ───────────────────────────
  static List<Map<String,dynamic>> _serialiseMovements(
    List<Map<String,dynamic>> rows,
  ) =>
=======
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
        _onMasterDataChanged?.call();
      }
    } catch (e) {
      debugPrint('SyncService._pullMasterData error: $e');
    }
  }

  static List<Map<String,dynamic>> _serialiseMovements(List<Map<String,dynamic>> rows) =>
>>>>>>> Stashed changes
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

  static List<Map<String,dynamic>> _serialiseMaster(List<Map<String,dynamic>> rows) =>
      rows.map((r) => Map<String,dynamic>.from(r)).toList();
}

class _SyncSummary {
  final int pushed;
  final int pulled;
  const _SyncSummary({required this.pushed, required this.pulled});
}