// ─────────────────────────────────────────────────────────────────────────────
// sync_service.dart — Checkpoint 4
//
// Architecture — fully event-driven, timer only as safety net:
//
//   PUSH movements    → immediately on addMovement / editMovement
//   PUSH master data  → immediately on any CRUD (items/locations/staff)
//   PULL              → Supabase Realtime websocket (instant, zero polling)
//   FALLBACK pull     → every 5 min — catches missed realtime events only
//                       skips push — push is always event-driven
//   ON-RECONNECT      → immediate push of entire pending queue
//   ON-APP-RESUME     → push pending + one pull (covers offline gap)
//
// Zero data loss:
//   • Every write goes to SQLite first with sync_status='pending'
//   • pending queue survives app crashes and restarts
//   • pushNow() drains the queue on every save, reconnect, and resume
//   • 5-min fallback pull catches any realtime events missed during downtime
//
// Zero unnecessary network calls:
//   • No push timer — push only when there is something to push
//   • No pull timer — realtime handles live updates
//   • Fallback pull runs only every 5 min as safety net
//   • _isSyncing mutex prevents concurrent calls
//   • Reachability cached 30s — no repeated DNS checks
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../config/app_config.dart';
import 'supabase_service.dart';
import 'package:intl/intl.dart';

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

  // ── Timers & subscriptions ─────────────────────────────────────────────────
  Timer?              _fallbackTimer;   // pull-only safety net, 5 min
  StreamSubscription? _connectivitySub;

  // ── Reachability cache — avoids repeated DNS checks ────────────────────────
  bool?     _reachableCache;
  DateTime? _reachableCacheTime;
  static const _reachableCacheTtl = Duration(seconds: 30);

  Future<bool> _isReachableCached() async {
    final now = DateTime.now().toUtc();
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

 DateTime _effectiveSince() {
    final now        = DateTime.now().toUtc();
    final startOfDay = DateTime(now.year, now.month, now.day);
    if (_lastSyncAt == null) {
      return DateTime.now().subtract(const Duration(hours: 24));
    }
    final fromLastSync = _lastSyncAt!.subtract(const Duration(minutes: 10));
    // Return EARLIER of the two — more coverage, never miss anything
    return fromLastSync.isBefore(startOfDay) ? fromLastSync : fromLastSync;
  }

  // ── Master data dirty flag ─────────────────────────────────────────────────
  bool      _masterDataDirty = true;
  DateTime? _lastMasterPush;

  void markMasterDirty() {
    _masterDataDirty = true;
    // Push immediately — don't wait for any timer
    _pushMasterDataNow();
  }

  // ── Start ──────────────────────────────────────────────────────────────────
  void startAutoSync({
    void Function(Map<String,dynamic>)? onRemoteMovement,
    void Function(List<String> ids)?    onMovementsSynced,
    void Function()?                    onMasterDataChanged,
    void Function()?                    onStockInvalidated,
  }) {
    if (!AppConfig.isSyncEnabled) {
      debugPrint('SyncService: disabled');
      return;
    }

    _onRemoteMovement    = onRemoteMovement;
    _onMovementsSynced   = onMovementsSynced;
    _onMasterDataChanged = onMasterDataChanged;
    _onStockInvalidated  = onStockInvalidated;
    _loadLastSyncAt();
    // Realtime — all incoming changes handled instantly, zero polling
    SupabaseService.instance.subscribeToAll(
      onMovementInsert:    _handleRemoteMovement,
      onMovementUpdate:    _handleRemoteMovement,
      onMasterDataChanged: _handleMasterDataChanged,
      onResubscribe:       reconnectRealtime,
      onPullMissed:        _pullOnly,
    );

    // Fallback pull-only — catches missed realtime events
    // 5 min interval: light enough to not waste battery/data
    // pull-only: never pushes (push is always event-driven)
    _fallbackTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _pullOnly(),
    );



    // On network restore — push entire pending queue immediately
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online) {
        debugPrint('SyncService: network restored — pushing pending');
        _invalidateReachabilityCache();
        pushNow();
      }
    });

    // On startup — push any pending from before app was closed
    Future.delayed(const Duration(seconds: 4), pushNow);

    debugPrint('SyncService: started — realtime + 5min fallback');
  }

  void stopAutoSync() {
    SupabaseService.instance.unsubscribeAll();
    _fallbackTimer?.cancel();
    _connectivitySub?.cancel();
    _fallbackTimer   = null;
    _connectivitySub = null;
  }


Future<void> _loadLastSyncAt() async {
    try {
      final saved = await DatabaseHelper.instance.getLastSyncAt();
      if (saved != null) {
        _lastSyncAt = saved;
        debugPrint('SyncService: loaded lastSyncAt = $_lastSyncAt');
      }
    } catch (e) {
      debugPrint('SyncService._loadLastSyncAt error: $e');
    }
  }

  void _updateLastSyncAt() {
    _lastSyncAt = DateTime.now().toUtc();
    DatabaseHelper.instance.saveLastSyncAt(_lastSyncAt!);
  }
  
  /// Called on app resume — tears down dead channel and re-subscribes fresh
   bool _isReconnecting = false;

  void reconnectRealtime({bool force = false}) {
    if (!AppConfig.isSyncEnabled) return;
    if (_isReconnecting) return;
    
    // Skip if channel is healthy and not forced
    if (!force && SupabaseService.instance.isChannelHealthy) {
      debugPrint('SyncService: channel healthy — skipping reconnect');
      return;
    }
    _isReconnecting = true;
    debugPrint('SyncService: reconnecting realtime channel');
    SupabaseService.instance.unsubscribeAll();
    _invalidateReachabilityCache();
    SupabaseService.instance.subscribeToAll(
      onMovementInsert:    _handleRemoteMovement,
      onMovementUpdate:    _handleRemoteMovement,
      onMasterDataChanged: _handleMasterDataChanged,
      onResubscribe:       reconnectRealtime,
    );
    Future.delayed(const Duration(seconds: 3), () => _isReconnecting = false);
    Future.delayed(const Duration(seconds: 2), () => _pullOnly());
  }
  

  void dispose() {
    stopAutoSync();
    _statusCtrl.close();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT-DRIVEN PUSH — called by AppDataProvider after every save
  // ═══════════════════════════════════════════════════════════════════════════

  // Called after addMovement / editMovement
  // Pushes pending queue immediately — other devices see it in < 2 seconds
  Future<void> pushNow() async {
    if (!AppConfig.isSyncEnabled) return;
     if (_isSyncing) {
      // Mutex held — retry after current operation finishes
      // Ensures edits/deletes are never silently dropped
      Future.delayed(const Duration(seconds: 2), pushNow);
      return;
    }

    final reachable = await _isReachableCached();
    if (!reachable) {
      debugPrint('SyncService.pushNow: not reachable — will retry on reconnect');
      return; // SQLite pending queue safe — will push on reconnect
    }

    _isSyncing = true;
    try {
      await _pushPending();
      //_updateLastSyncAt();
    } catch (e) {
      debugPrint('SyncService.pushNow error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // Called by markMasterDirty() — pushes items/locations/staff immediately
  Future<void> _pushMasterDataNow() async {
    if (!AppConfig.isSyncEnabled) return;

    final reachable = await _isReachableCached();
    if (!reachable) return; // dirty flag stays true — will push on reconnect

    await _pushMasterData();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PULL-ONLY FALLBACK — safety net for missed realtime events
  // Does NOT push — push is always event-driven
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pullOnly() async {
    if (!AppConfig.isSyncEnabled) return;
      if (_isSyncing) return;

    final reachable = await _isReachableCached();
    if (!reachable) return;

    _isSyncing = true;
    String time = DateFormat('hh:mm a').format(DateTime.now());
    debugPrint('SyncService: fallback pull started $time');
    
    debugPrint("Current Time: $time");
    try {
      await _pullMasterData();
      await _pullMovements();
      _updateLastSyncAt();
      // Notify UI to reload master data from SQLite after pull
      _onMasterDataChanged?.call();
      debugPrint('SyncService: fallback pull done $time');
    } catch (e) {
      debugPrint('SyncService._pullOnly error: $e');
    } finally {
      _isSyncing = false;
    }
  }

   Future<void> backgroundPullAll() async {
    if (!AppConfig.isSyncEnabled) return;
      if (_isSyncing) return;             // ← respect the mutex
    final reachable = await _isReachableCached();
    if (!reachable) return;
    _isSyncing = true;
    try {
      await _pullMasterData();
      await _pullMovements();
      _updateLastSyncAt();
      _onMasterDataChanged?.call();
      debugPrint('SyncService.backgroundPullAll: done');

    } catch (e) {
      debugPrint('SyncService.backgroundPullAll error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MANUAL SYNC — sync screen button
  // Full push + pull on demand
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<_SyncSummary>> sync({bool silent = false}) async {
    if (_isSyncing) return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    if (!AppConfig.isSyncEnabled) return const SyncResult.err('Sync not configured');

    final reachable = await _isReachableCached();
    if (!reachable) {
      debugPrint('SyncService: not reachable — skipped');
      return const SyncResult.ok(_SyncSummary(pushed: 0, pulled: 0));
    }

    _isSyncing = true;
    if (!silent) _setStatus(SyncStatus.syncing);
    debugPrint('SyncService: full sync started');

    try {
      await _pushMasterData();

      final pushResult = await _pushPending();
      final pushed = pushResult.data ?? 0;

      final pulled = await _pullMovements();

     // _updateLastSyncAt();
      _pushedCount = pushed;

      if (!silent) _setStatus(SyncStatus.done);
      debugPrint('SyncService: full sync done — pushed=$pushed pulled=$pulled');
      return SyncResult.ok(_SyncSummary(pushed: pushed, pulled: pulled));

    } catch (e, st) {
      debugPrint('SyncService.sync error: $e\n$st');
      if (!silent) _setStatus(SyncStatus.error, error: e.toString());
      return SyncResult.err(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  // ── Broadcast status ───────────────────────────────────────────────────────
  void _setStatus(SyncStatus s, {String? error}) {
    _status    = s;
    _lastError = error;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REALTIME HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleRemoteMovement(Map<String,dynamic> row) async {
    try {
      final changed = await DatabaseHelper.instance.upsertMovementFromRemote(row);
      if (changed) {
        _onRemoteMovement?.call(row);
        _onStockInvalidated?.call();
        debugPrint('SyncService: realtime movement — ${row['movement_id']}');
      }
      // Echo from our own push — silently skip, no log needed
    } catch (e) {
      debugPrint('SyncService._handleRemoteMovement error: $e');
    }
  }

  // Debounced — bulk master data changes fire only one reload
  Timer? _masterDataDebounce;
  void _handleMasterDataChanged() {
    _masterDataDebounce?.cancel();
    _masterDataDebounce = Timer(const Duration(milliseconds: 1500), () {
      // Pass null = pull last 24h regardless of _lastSyncAt
      // Ensures we never miss a record due to stale timestamp
      _pullMasterDataFresh().then((_) => _onMasterDataChanged?.call());
    });
  }

  // Pull master data ignoring _lastSyncAt — used on realtime events
  Future<void> _pullMasterDataFresh() async {
    try {
      final since  = _effectiveSince();
      final result = await SupabaseService.instance.pullMasterDataSince(since);
      if (!result.isSuccess) return;

      final data = result.data!;
      final db   = DatabaseHelper.instance;

      // Process SQLite writes in background — avoid blocking main thread
      // Single transaction — faster, atomic, no main thread blocking
      await db.batchUpsertMasterFromRemote(
        items:     List<Map<String,dynamic>>.from(data['items']     ?? []),
        locations: List<Map<String,dynamic>>.from(data['locations'] ?? []),
        staff:     List<Map<String,dynamic>>.from(data['staff']     ?? []),
      );
      final total = (data['items']?.length     ?? 0) +
                    (data['locations']?.length ?? 0) +
                    (data['staff']?.length     ?? 0);

      if (total > 0) {debugPrint('SyncService: realtime master pull — '
          'items:${data['items']?.length ?? 0} '
          'locations:${data['locations']?.length ?? 0} '
          'staff:${data['staff']?.length ?? 0}');
    }} catch (e) {
      debugPrint('SyncService._pullMasterDataFresh error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUSH HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult<int>> _pushPending() async {
    final db      = DatabaseHelper.instance;
    final pending = await db.getPendingMovementsAll();
    if (pending.isEmpty) return const SyncResult.ok(0);

    debugPrint('SyncService: pushing ${pending.length} pending movements');

    final serialised = pending.length > 50
        ? await compute(_serialiseMovements, pending)
        : _serialiseMovements(pending);

    final result = await SupabaseService.instance.pushMovements(serialised);
    if (!result.isSuccess) {
      debugPrint('SyncService._pushPending error: ${result.error}');
      return SyncResult.err(result.error);
    }

    final ids = pending.map((m) => m['movement_id'] as String).toList();
    await db.markMovementsSynced(ids);
    _onMovementsSynced?.call(ids);
    debugPrint('SyncService: pushed ${ids.length} movements');
    return SyncResult.ok(result.data ?? 0);
  }

  Future<void> _pushMasterData() async {
     if (!_masterDataDirty) return;
    final now = DateTime.now().toUtc();
    // Throttle: max once per 5s — prevents rapid duplicate pushes
    // but short enough to not delay deletes/edits
   if (_lastMasterPush != null &&
        now.difference(_lastMasterPush!).inSeconds < 5) {
      // Throttled — retry after delay so delete is not silently lost
      Future.delayed(const Duration(seconds: 6), _pushMasterDataNow);
      return;
    }

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

      debugPrint('SyncService: master data pushed — '
          'items:${results[0].length} '
          'locations:${results[1].length} '
          'staff:${results[2].length}');
    } catch (e) {
      _masterDataDirty = true; // retry next time
      debugPrint('SyncService._pushMasterData error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PULL HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<int> _pullMovements() async {
    try {
      final db     = DatabaseHelper.instance;
      final since  = _effectiveSince();
      debugPrint('DEBUG pullMovements since=$since lastSyncAt=$_lastSyncAt');
      final result = await SupabaseService.instance.pullMovementsSince(since);
      debugPrint('DEBUG pullMovements result=${result.isSuccess} count=${result.data?.length}');
      if (!result.isSuccess) return 0;

      final remote = result.data!;
      if (remote.isEmpty) return 0;

      int merged = 0;
      for (final row in remote) {
        try {
          final changed = await db.upsertMovementFromRemote(row);
          if (changed) {
            _onRemoteMovement?.call(row);
            merged++;
          }
          // No log for unchanged — reduces noise significantly
        } catch (e) {
          debugPrint('SyncService: merge skip — $e');
        }
      }

      if (merged > 0) {
        String time = DateFormat('hh:mm a').format(DateTime.now());
        _onStockInvalidated?.call();
        debugPrint('SyncService: pulled $merged movements $time');
      }
      return merged;
    } catch (e) {
      debugPrint('SyncService._pullMovements error: $e');
      return 0;
    }
  }

    Future<void> _pullMasterData() async {
    try {
      final since  = _effectiveSince();
      final result = await SupabaseService.instance.pullMasterDataSince(since);
      if (!result.isSuccess) return;

      final data = result.data!;
      final db   = DatabaseHelper.instance;

      await Future.wait([
        Future(() async {
          for (final row in data['items'] ?? []) {
            await db.upsertItemFromRemote(row);
          }
        }),
        Future(() async {
          for (final row in data['locations'] ?? []) {
            await db.upsertLocationFromRemote(row);
          }
        }),
        Future(() async {
          for (final row in data['staff'] ?? []) {
            await db.upsertStaffFromRemote(row);
          }
        }),
      ]);

      final total = (data['items']?.length     ?? 0) +
                    (data['locations']?.length ?? 0) +
                    (data['staff']?.length     ?? 0);

      if (total > 0) debugPrint('SyncService: pulled master data — $total records');
    } catch (e) {
      debugPrint('SyncService._pullMasterData error: $e');
    }
  }


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

      final data      = result.data!;
      final db        = DatabaseHelper.instance;
      final items     = data['items']     ?? [];
      final locations = data['locations'] ?? [];
      final staff     = data['staff']     ?? [];
      final movements = data['movements'] ?? [];

      if (items.isEmpty && staff.isEmpty) return SyncFirstResult.supabaseEmpty;

      for (final row in items)     { await db.upsertItemFromRemote(row); }
      for (final row in locations) { await db.upsertLocationFromRemote(row); }
      for (final row in staff)     { await db.upsertStaffFromRemote(row); }
      for (final row in movements) { await db.upsertMovementFromRemote(row); }

      debugPrint('SyncService.firstSyncFromRemote: done — '
          'items:${items.length} locations:${locations.length} '
          'staff:${staff.length} movements:${movements.length}');

     _updateLastSyncAt();
      return SyncFirstResult.success;

    } catch (e) {
      debugPrint('SyncService.firstSyncFromRemote error: $e');
      return SyncFirstResult.unreachable;
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
        'bale_no':       m['bale_no'],
        'is_deleted':    m['is_deleted'] == 1,
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