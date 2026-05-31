// ─────────────────────────────────────────────────────────────────────────────
// app_data_provider.dart — Checkpoint 3
//
// Checkpoint 3 fixes:
//   • _seedAndLoad() calls db.seedData() directly instead of db.reseed()
//   • startRealtimeSync() passes onStockInvalidated to SyncService
//   • mergeRemoteMovement() calls _refreshStockCache() after every merge
//   • _normaliseRemoteRow() uses .toString() on all fields
//   • _handleFreshInstall() uses SyncFirstResult enum
//   • _refreshStockCache() calls _notify() after update
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/id_generator.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/oauth_result.dart';
import '../services/shop_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

class ItemModel {
  final String   id;
  String         name;
  String         unit;
  bool           isDeleted;
  final DateTime createdAt;
  DateTime       updatedAt;

  ItemModel({
    required this.id,
    required this.name,
    required this.unit,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ItemModel.fromMap(Map<String, dynamic> m) => ItemModel(
    id:        m['item_id']     as String,
    name:      m['item_name']   as String,
    unit:      m['unit']        as String,
    isDeleted: (m['is_deleted'] as int) == 1,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );
}

class LocationModel {
  final String   id;
  String         name;
  String         type;
  bool           isDeleted;
  bool           isFinalDestination;
  final DateTime createdAt;
  DateTime       updatedAt;

  LocationModel({
    required this.id,
    required this.name,
    required this.type,
    this.isDeleted          = false,
    this.isFinalDestination = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocationModel.fromMap(Map<String, dynamic> m) => LocationModel(
    id:                 m['location_id']            as String,
    name:               m['location_name']          as String,
    type:               m['type']                   as String,
    isDeleted:          (m['is_deleted']             as int) == 1,
    isFinalDestination: (m['is_final_destination']   as int? ?? 0) == 1,
    createdAt:          DateTime.parse(m['created_at'] as String),
    updatedAt:          DateTime.parse(m['updated_at'] as String),
  );
}

class StaffModel {
  final String   id;
  String         name;
  String         pin;
  String         role;
  final DateTime createdAt;

  StaffModel({
    required this.id,
    required this.name,
    required this.pin,
    this.role = 'staff',
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';

  factory StaffModel.fromMap(Map<String, dynamic> m) => StaffModel(
    id:        m['staff_id']   as String,
    name:      m['staff_name'] as String,
    pin:       m['pin']        as String,
    role:      m['role']       as String,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

class MovementModel {
  final String   id;
  final String   itemId;
  String         fromLocationId;
  String         toLocationId;
  final String   staffId;
  double         quantity;
  final DateTime createdAt;
  bool           edited;
  String?        editedBy;
  DateTime?      editedAt;
  String?        remark;
  String?        baleNo;
  String         syncStatus;
  bool           isDeleted;
  String         groupId;

  MovementModel({
    required this.id,
    required this.itemId,
    required this.fromLocationId,
    required this.toLocationId,
    required this.staffId,
    required this.quantity,
    required this.createdAt,
    this.edited     = false,
    this.editedBy,
    this.editedAt,
    this.remark,
    this.baleNo,
    this.syncStatus = 'pending',
    this.isDeleted  = false,
    String? groupId,
  }): groupId = groupId ?? id;

  factory MovementModel.fromMap(Map<String, dynamic> m) => MovementModel(
    id:             m['movement_id']   as String,
    itemId:         m['item_id']       as String,
    fromLocationId: m['from_location'] as String,
    toLocationId:   m['to_location']   as String,
    staffId:        m['staff_id']      as String,
    quantity:       (m['quantity']     as num).toDouble(),
    createdAt:      DateTime.parse(m['created_at'] as String),
    edited:         (m['edited']       as int) == 1,
    editedBy:       m['edited_by']     as String?,
    editedAt:       m['updated_at'] != null
        ? DateTime.parse(m['updated_at'] as String)
        : null,
    remark:         m['remark']      as String?,
    baleNo:         m['bale_no']     as String?,
    syncStatus:     m['sync_status'] as String,
    isDeleted:      (m['is_deleted']  as int? ?? 0) == 1,
    groupId:        m['group_id']    as String?,
  );
}

class StockBalance {
  final LocationModel location;
  final ItemModel     item;
  final double        incoming;
  final double        outgoing;
  double get balance => incoming - outgoing;

  const StockBalance({
    required this.location,
    required this.item,
    required this.incoming,
    required this.outgoing,
  });
}

// ─── compute() top-level helpers ─────────────────────────────────────────────

List<ItemModel>     _parseItems    (List<Map<String,dynamic>> rows) =>
    rows.map(ItemModel.fromMap).toList();
List<LocationModel> _parseLocations(List<Map<String,dynamic>> rows) =>
    rows.map(LocationModel.fromMap).toList();
List<StaffModel>    _parseStaff    (List<Map<String,dynamic>> rows) =>
    rows.map(StaffModel.fromMap).toList();
List<MovementModel> _parseMovements(List<Map<String,dynamic>> rows) =>
    rows.map(MovementModel.fromMap).toList();

List<StockBalance> _calcStock(_StockInput input) {
  final result = <StockBalance>[];
  for (final loc in input.locations) {
    for (final item in input.items) {
      double incoming = 0, outgoing = 0;
      for (final m in input.movements) {
        if (m.itemId != item.id) continue;
        if (m.toLocationId   == loc.id) incoming += m.quantity;
        if (m.fromLocationId == loc.id && m.fromLocationId != 'SUPPLIER') outgoing += m.quantity;
      }
      if (incoming > 0 || outgoing > 0) {
        result.add(StockBalance(
          location: loc, item: item,
          incoming: incoming, outgoing: outgoing,
        ));
      }
    }
  }
  return result;
}

class _StockInput {
  final List<ItemModel>     items;
  final List<LocationModel> locations;
  final List<MovementModel> movements;
  const _StockInput(this.items, this.locations, this.movements);
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class AppDataProvider extends ChangeNotifier {

  final List<ItemModel>     _items     = [];
  final List<LocationModel> _locations = [];
  final List<StaffModel>    _staff     = [];
  final List<MovementModel> _movements = [];
final Map<String, ItemModel>     _itemMap     = {};
  final Map<String, LocationModel> _locationMap = {};
  final Map<String, StaffModel>    _staffMap    = {};

  StaffModel? _currentStaff;
  bool        _disposed  = false;
   bool        _isLoading    = false;
   String      _shopId       = '';
String      _shopName     = '';
bool        _isOnboarded  = false;
bool        _isFirstLaunch = false;

// ── OAuth state — isolated ValueNotifier, does not trigger full rebuild ──
  final oauthNotifier = ValueNotifier<OAuthResult>(OAuthResult.idle);
  String? _oauthEmail;
  String? get oauthEmail => _oauthEmail;
  StreamSubscription? _oauthSub;
  // Retry state
  bool   _syncFailed    = false;
  int    _retryAttempt  = 0;
  String _retryMessage  = 'Loading data...';
  static const _maxRetries    = 20;
  static const _retryDelaySec = 5;

  // Stock cache
  List<StockBalance>? _stockCache;
  bool                _stockDirty = true;

  // Sorted movements cache
  List<MovementModel>? _sortedCache;
  bool                 _sortedDirty = true;

// Mutation version — increments on every add/edit/delete/remote merge.
  // history_screen watches this instead of totalMovements (count never changes on edit).
  int _movementVersion = 0;

  // Mutex — prevents double-spend on rapid successive taps (TC-028).
  bool _isAddingMovement = false;
  Timer? _notifyTimer;

  // ── Getters ────────────────────────────────────────────────────────────────
  List<ItemModel>     get items     => _items.where((i) => !i.isDeleted).toList();
  List<LocationModel> get locations => _locations.where((l) => !l.isDeleted).toList();
  List<StaffModel>    get staff     => List.unmodifiable(_staff);
  StaffModel?         get currentStaff   => _currentStaff;
  bool                get isLoggedIn     => _currentStaff != null;
  bool                get isAdmin        => _currentStaff?.isAdmin ?? false;
  bool                get isLoading      => _isLoading;
  int                 get totalMovements => _movements.length;
   int                 get movementVersion  => _movementVersion;
  String              get shopId         => _shopId;
String              get shopName       => _shopName;
bool                get isFirstLaunch  => _isFirstLaunch;
  bool                get isOnboarded    => _isOnboarded;

  bool   get syncFailed   => _syncFailed;
  int    get retryAttempt => _retryAttempt;
  int    get maxRetries   => _maxRetries;
  String get retryMessage => _retryMessage;

  List<ItemModel>     get allItems     => List.unmodifiable(_items);
  List<LocationModel> get allLocations => List.unmodifiable(_locations);

  int get pendingSyncCount => _movements.where((m) => m.syncStatus == 'pending').length;
  int get syncedCount      => _movements.where((m) => m.syncStatus == 'synced').length;

  List<MovementModel> get sortedMovements {
    if (!_sortedDirty && _sortedCache != null) return _sortedCache!;
    _sortedCache = _movements
        .where((m) => !m.isDeleted)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _sortedDirty = false;
    return _sortedCache!;
  }

  void _notify() {
    debugPrint('🔵 AppDataProvider._notify: called — listeners will rebuild');
    if (_disposed) return;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(milliseconds: 16), () {
      if (!_disposed) notifyListeners();
    });
  }

  void _notifyNow() {
    debugPrint('🔵 AppDataProvider._notifyNow: called — immediate rebuild');
    if (_disposed) return;
    _notifyTimer?.cancel();
    notifyListeners();
  }

   void _invalidateCaches() {
    _stockDirty      = true;
    _sortedDirty     = true;
    _movementVersion++;
  }

   void _rebuildMaps() {
    _itemMap
      ..clear()
      ..addEntries(_items.map((i) => MapEntry(i.id, i)));
    _locationMap
      ..clear()
      ..addEntries(_locations.map((l) => MapEntry(l.id, l)));
    _staffMap
      ..clear()
      ..addEntries(_staff.map((s) => MapEntry(s.id, s)));
  }

// TC-035 — strips null bytes, collapses whitespace, enforces cleanliness.
  // sqflite and PostgREST both use parameterised queries so SQL injection
  // is not possible, but we sanitise for data hygiene.
  String? _sanitiseText(String? s) {
    if (s == null) return null;
    final cleaned = s
        .replaceAll('\x00', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _oauthSub?.cancel();
    oauthNotifier.dispose();
    _disposed = true;
    super.dispose();
  }

// ── OAuth listener — single global listener, owned by provider ────────────
  void _startOAuthListener() {
    _oauthSub?.cancel();
    debugPrint('AppDataProvider: OAuth listener STARTING — single global listener');
    _oauthSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        debugPrint('AppDataProvider: auth event=${data.event} hasSession=${data.session != null}');
        if (data.event == AuthChangeEvent.signedIn && data.session != null) {
          debugPrint('AppDataProvider: signedIn event received — calling _handleOAuthResult');
          debugPrint('🔴 PRE-OAUTH CHECK: isLoggedIn=${_currentStaff != null} isOnboarded=$_isOnboarded staff=${_staff.length}');
          await _handleOAuthResult(data.session!);
        } else {
          debugPrint('AppDataProvider: ignoring auth event=${data.event}');
        }
      },
    );
    debugPrint('AppDataProvider: OAuth listener ACTIVE');
  }

  void stopOAuthListener() {
    _oauthSub?.cancel();
    _oauthSub = null;
    debugPrint('AppDataProvider: OAuth listener stopped');
  }

  Future<void> _handleOAuthResult(Session session) async {
    debugPrint('AppDataProvider._handleOAuthResult: START processing');
    debugPrint('AppDataProvider._handleOAuthResult: userId=${session.user.id}');

    final email = session.user.email;
    debugPrint('AppDataProvider._handleOAuthResult: email=$email');
    if (email == null) {
      debugPrint('AppDataProvider._handleOAuthResult: ERROR — no email in session');
      oauthNotifier.value = OAuthResult.error;
      return;
    }

    debugPrint('AppDataProvider._handleOAuthResult: checking if email exists in shops table');
    final exists = await ShopService.instance.checkEmailExists(email);
    debugPrint('AppDataProvider._handleOAuthResult: emailExists=$exists');

    if (exists) {
      // Sign out — do not leave active session for already-registered email
      await Supabase.instance.client.auth.signOut();
      debugPrint('AppDataProvider: email already registered — signed out');
      oauthNotifier.value = OAuthResult.alreadyRegistered;
      return;
    }

    // New email — store for registerShop()
    ShopService.instance.setOwnerEmail(email);
    _oauthEmail = email;
    debugPrint('AppDataProvider: OAuth success email=$email');
    oauthNotifier.value = OAuthResult.success;
    debugPrint('🔴 CRITICAL CHECK: isLoggedIn=${_currentStaff != null} currentStaff=$_currentStaff isOnboarded=$_isOnboarded staff count=${_staff.length}');
  }

  void clearOAuthState() {
    debugPrint('AppDataProvider: clearOAuthState called — resetting to idle');
    oauthNotifier.value = OAuthResult.idle;
    _oauthEmail = null;
    ShopService.instance.clearOwnerEmail();
    debugPrint('AppDataProvider: OAuth state cleared');
  }

  Future<void> markShopIdAlertShown() async {
  _isFirstLaunch = false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('shop_id_alert_shown', true);
  debugPrint('AppDataProvider: shop_id_alert_shown marked');
}
  
  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    debugPrint('🔵 AppDataProvider.initialize: START');
    _isLoading    = true;
    _syncFailed   = false;
    _retryAttempt = 0;
    _retryMessage = 'Loading data...';
    try {
      final prefs = await SharedPreferences.getInstance();
     _shopId       = prefs.getString('current_shop_id') ?? '';
_shopName     = prefs.getString('current_shop_name') ?? '';
_isOnboarded  = _shopId.isNotEmpty;
final isOwner    = prefs.getBool('is_shop_owner') ?? false;
final alertShown = prefs.getBool('shop_id_alert_shown') ?? false;
_isFirstLaunch   = _isOnboarded && isOwner && !alertShown;
debugPrint('AppDataProvider: isFirstLaunch=$_isFirstLaunch isOwner=$isOwner alertShown=$alertShown');
      debugPrint('AppDataProvider: shopId=$_shopId isOnboarded=$_isOnboarded');

      // Start OAuth listener only during onboarding — not for existing users
      if (!_isOnboarded) {
        // Clear any stale Supabase session from previous incomplete onboarding
        // Prevents initialSession from interfering with fresh onboarding flow
        final existingSession = Supabase.instance.client.auth.currentSession;
        if (existingSession != null) {
          debugPrint('AppDataProvider: stale session detected during onboarding — clearing');
          await Supabase.instance.client.auth.signOut();
          debugPrint('AppDataProvider: stale session cleared');
        }
        _startOAuthListener();
      }

      // Fresh install — no shop registered yet
      // Skip _loadAll() entirely — onboarding flow handles setup
      if (_shopId.isEmpty) {
        debugPrint('AppDataProvider: no shop_id — skipping load, showing onboarding');
        return;
      }

      SupabaseService.instance.setShopId(_shopId);
      DatabaseHelper.instance.setShopId(_shopId);
      await _loadAll();
    } catch (e, st) {
      debugPrint('AppDataProvider.initialize error: $e\n$st');
    } finally {
      _isLoading = false;
       debugPrint('🔵 AppDataProvider.initialize: END isOnboarded=$_isOnboarded staff=${_staff.length}');
      _notifyNow();
    }
  }

  Future<void> retryInitialize() async {
    _syncFailed   = false;
    _retryAttempt = 0;
    _retryMessage = 'Retrying...';
    _isLoading    = true;
    _notifyNow();
    await initialize();
  }

  void startRealtimeSync() {
    SyncService.instance.startAutoSync(
      onRemoteMovement:    mergeRemoteMovement,
      onMovementsSynced:   _markMovementsSyncedInMemory,
      onMasterDataChanged: _reloadMasterData,
      onStockInvalidated:  _onStockInvalidated,
    );
  }

  void _onStockInvalidated() {
    _stockDirty = true;
    _refreshStockCache();
  }

   Future<void> _reloadMasterData() async {
    try {
      final db = DatabaseHelper.instance;

      // Run all three reads in parallel — faster, non-blocking
      final results = await Future.wait([
        db.getItems(),
        db.getLocations(),
        db.getStaff(),
      ]);

      // Parse in background isolate — heavy for large datasets
      final items     = await compute(_parseItems,     results[0]);
      final locations = await compute(_parseLocations, results[1]);
      final staff     = await compute(_parseStaff,     results[2]);

      _items    ..clear()..addAll(items);
    _locations..clear()..addAll(locations);
    _staff    ..clear()..addAll(staff);
    _rebuildMaps();
    _invalidateCaches();
      _notifyNow();
      _refreshStockCache();
      debugPrint('AppDataProvider: master data reloaded from remote change');
    } catch (e) {
      debugPrint('AppDataProvider._reloadMasterData error: $e');
    }
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // _loadAll
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadAll() async {
    final db = DatabaseHelper.instance;
    debugPrint('AppDataProvider: loading from DB...');

// TEMP DEBUG — remove after investigation
    final rawDb = await DatabaseHelper.instance.db;
    final allStaff = await rawDb.query('staff');
    debugPrint('🔴 SQLite RAW staff: ${allStaff.map((s) => "${s['staff_name']}|${s['shop_id']}").toList()}');
    debugPrint('🔴 Current _shopId: $_shopId');
    // END TEMP DEBUG

    final results = await Future.wait([
      db.getItems(),
      db.getLocations(),
      db.getStaff(),
      db.getMovements(limit: 99999),
    ]);

     _items    ..clear()..addAll(_safeParseItems(results[0]));
    _locations..clear()..addAll(_safeParseLocations(results[1]));
    _staff    ..clear()..addAll(_safeParseStaff(results[2]));
    _movements..clear()..addAll(_safeParseMovements(results[3]));
    _rebuildMaps();

    debugPrint('AppDataProvider: loaded — '
        'items:${_items.length} locations:${_locations.length} '
        'staff:${_staff.length} movements:${_movements.length}');

     if (_staff.isEmpty && _items.isEmpty && _locations.isEmpty) {
      debugPrint('🔵 AppDataProvider._loadAll: fresh install detected — calling _handleFreshInstall');
      debugPrint('AppDataProvider: fresh install detected');
      await _handleFreshInstall(db);
    } else {
      // Existing install — silently pull latest from remote in background
      // User sees local data immediately, UI refreshes when pull completes
      debugPrint('🔵 AppDataProvider._loadAll: existing data found — background refresh');
      _backgroundRefresh();
    }

    _invalidateCaches();
  }

void _backgroundRefresh() {
    Future.delayed(const Duration(seconds: 6), () async {
      try {
        await SyncService.instance.pushNow();
        await SyncService.instance.backgroundPullAll();
        await _reloadMasterData();
        await _reloadMovements();
        debugPrint('AppDataProvider: background refresh complete');
      } catch (e) {
        debugPrint('AppDataProvider._backgroundRefresh error: $e');
      } finally {
        // Notify only if still onboarded — prevents ghost navigation
        // when startRoute was 'onboarding' and home: is still static widget
        if (_isOnboarded) _notify();
      }
    });
  }

  Future<void> _handleFreshInstall(DatabaseHelper db) async {
    _retryMessage = 'Connecting to server...';
    _notifyNow();

    debugPrint('AppDataProvider: attempting first sync from Supabase');
    final firstTry = await SyncService.instance.firstSyncFromRemote();
    debugPrint('AppDataProvider: firstSyncFromRemote result = $firstTry');

    if (firstTry == SyncFirstResult.success) {
      await _reloadAfterFirstSync(db, attempt: 1);
      return;
    }

    if (firstTry == SyncFirstResult.supabaseEmpty) {
      debugPrint('AppDataProvider: first device ever — seeding locally');
      _retryMessage = 'Setting up for first time...';
      _notifyNow();
      await _seedAndLoad(db);
      return;
    }

    for (int i = 2; i <= _maxRetries; i++) {
      _retryAttempt = i;
      _retryMessage = 'Connecting to server...\nAttempt $i of $_maxRetries';
      _notifyNow();
      debugPrint('AppDataProvider: retry $i/$_maxRetries — waiting ${_retryDelaySec}s');

      await Future.delayed(const Duration(seconds: _retryDelaySec));

      final result = await SyncService.instance.firstSyncFromRemote();
      debugPrint('AppDataProvider: retry $i result = $result');

      if (result == SyncFirstResult.success) {
        await _reloadAfterFirstSync(db, attempt: i);
        return;
      }
      if (result == SyncFirstResult.supabaseEmpty) {
        debugPrint('AppDataProvider: Supabase empty on retry $i — seeding');
        await _seedAndLoad(db);
        return;
      }
    }

    _syncFailed   = true;
    _retryMessage = 'Could not reach server after $_maxRetries attempts.';
    debugPrint('AppDataProvider: all retries failed — showing error screen');
  }

  Future<void> _seedAndLoad(DatabaseHelper db) async {
    debugPrint('AppDataProvider: new shop — empty DB, ready for onboarding');
  }

  Future<void> _reloadAfterFirstSync(DatabaseHelper db, {required int attempt}) async {
    debugPrint('AppDataProvider: first sync succeeded on attempt $attempt');
    _retryMessage = 'Data loaded!';
    final r = await Future.wait([
      db.getItems(), db.getLocations(), db.getStaff(),
      db.getMovements(limit: 99999),
    ]);
    _items    ..clear()..addAll(_safeParseItems(r[0]));
    _locations..clear()..addAll(_safeParseLocations(r[1]));
    _staff    ..clear()..addAll(_safeParseStaff(r[2]));
    _movements..clear()..addAll(_safeParseMovements(r[3]));
    _rebuildMaps();      // ← maps populated — getItemById/getLocationById work
    _invalidateCaches(); // ← stock + sort caches cleared
    debugPrint('AppDataProvider: after first sync — '
        'items:${_items.length} locations:${_locations.length} '
        'staff:${_staff.length} movements:${_movements.length}');
  }

  // ── Safe parsers ──────────────────────────────────────────────────────────
  List<ItemModel> _safeParseItems(List<Map<String,dynamic>> rows) {
    final r = <ItemModel>[];
    for (final row in rows) {
      try { r.add(ItemModel.fromMap(row)); }
      catch (e) { debugPrint('ItemModel parse error: $e  row:$row'); }
    }
    return r;
  }

  List<LocationModel> _safeParseLocations(List<Map<String,dynamic>> rows) {
    final r = <LocationModel>[];
    for (final row in rows) {
      try { r.add(LocationModel.fromMap(row)); }
      catch (e) { debugPrint('LocationModel parse error: $e  row:$row'); }
    }
    return r;
  }

  List<StaffModel> _safeParseStaff(List<Map<String,dynamic>> rows) {
    final r = <StaffModel>[];
    for (final row in rows) {
      try { r.add(StaffModel.fromMap(row)); }
      catch (e) { debugPrint('StaffModel parse error: $e  row:$row'); }
    }
    return r;
  }

  List<MovementModel> _safeParseMovements(List<Map<String,dynamic>> rows) {
    final r = <MovementModel>[];
    for (final row in rows) {
      try { r.add(MovementModel.fromMap(row)); }
      catch (e) { debugPrint('MovementModel parse error: $e  row:$row'); }
    }
    return r;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK
  // ═══════════════════════════════════════════════════════════════════════════

  List<StockBalance> getStock() {
    if (!_stockDirty && _stockCache != null) return _stockCache!;
    _stockCache = _calcStock(_StockInput(
        items,
        locations,
        _movements.where((m) => !m.isDeleted).toList(),
    ));
    _stockDirty = false;
    return _stockCache!;
  }

  Future<void> _refreshStockCache() async {
    try {
      final result = await compute(
        _calcStock,
        _StockInput(items, locations,
            _movements.where((m) => !m.isDeleted).toList()),
      );
      if (_disposed) return;
      _stockCache = result;
      _stockDirty = false;
      _notify();
    } catch (e) {
      debugPrint('_refreshStockCache error: $e');
      _stockDirty = true;
    }
  }

  double totalStockForItem(String itemId) =>
      getStock().where((s) => s.item.id == itemId).fold(0, (sum, s) => sum + s.balance);

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  bool login({required String staffId, required String pin}) {
    try {
      final s = _staff.firstWhere((s) => s.id == staffId);
      if (s.pin == pin) {
        _currentStaff = s;
        SharedPreferences.getInstance()
            .then((p) => p.setString('logged_in_staff_id', staffId));
        _notifyNow();
        return true;
      } else {
        debugPrint('login failed: incorrect pin for staffId $staffId');
      }
      return false;
    } catch (_) { return false; }
  }

  void loginWithoutPin({required String staffId}) {
    try {
      final s = _staff.firstWhere((s) => s.id == staffId);
      _currentStaff = s;
      _notifyNow();
    } catch (e) { debugPrint('loginWithoutPin: $e'); }
  }

  void logout() {
    _currentStaff = null;
    SharedPreferences.getInstance()
        .then((p) => p.remove('logged_in_staff_id'));
    _notifyNow();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEMS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addItem({
    required String name,
    required String unit,
    String? openingLocationId,
    double? openingQty,
  }) async {
    try {
      final now    = DateTime.now().toUtc();
      final db     = DatabaseHelper.instance;
      final itemId = await IdGenerator.instance.item();
      await db.insertItem({
        'item_id':    itemId,
        'item_name':  name,
        'unit':       unit,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'is_deleted': 0,
        'shop_id':    _shopId,
      });
       final newItem = ItemModel(id: itemId, name: name, unit: unit, createdAt: now, updatedAt: now);
    _items.add(newItem);
    _itemMap[itemId] = newItem;
      SyncService.instance.markMasterDirty();

      if (openingLocationId != null && openingQty != null && openingQty > 0) {
        final mvtId   = await IdGenerator.instance.movement();
        final staffId = _currentStaff?.id ?? (staff.isNotEmpty ? staff.first.id : 'STF-00001');
        await db.insertMovement({
          'movement_id':   mvtId,
          'item_id':       itemId,
          'quantity':      openingQty,
          'from_location': 'SUPPLIER',
          'to_location':   openingLocationId,
          'staff_id':      staffId,
          'created_at':    now.toIso8601String(),
          'updated_at':    now.toIso8601String(),
          'edited':        0,
          'edited_by':     null,
          'sync_status':   'pending',
          'remark':        'Opening stock',
          'shop_id':       _shopId,
        });
        _movements.insert(0, MovementModel(
          id:             mvtId,
          itemId:         itemId,
          fromLocationId: 'SUPPLIER',
          toLocationId:   openingLocationId,
          staffId:        staffId,
          quantity:       openingQty,
          createdAt:      now,
          remark:         'Opening stock',
        ));
      }

      _invalidateCaches();
      _notify();
      _refreshStockCache();
    } catch (e) { debugPrint('addItem error: $e'); }
  }

  Future<void> editItem({
    required String id,
    required String name,
    required String unit,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      debugPrint('DEBUG now utc: ${now.toIso8601String()}');
      debugPrint('DEBUG now local: ${now.toLocal().toIso8601String()}');
      debugPrint('DEBUG today local: ${DateTime.now().toIso8601String()}');
      await DatabaseHelper.instance.updateItem(id, {
        'item_name':  name,
        'unit':       unit,
        'updated_at': now.toIso8601String(),
      });
      final item = _items.firstWhere((i) => i.id == id);
      item.name = name; item.unit = unit; item.updatedAt = now;
      SyncService.instance.markMasterDirty();
      _notify();
    } catch (e) { debugPrint('editItem($id): $e'); }
  }

  Future<void> deleteItem(String id) async {
    try {
      final now = DateTime.now().toUtc();
      await DatabaseHelper.instance.softDeleteItem(id);
      final item = _items.firstWhere((i) => i.id == id);
      item.isDeleted = true; item.updatedAt = now;
    _itemMap.remove(id);
      SyncService.instance.markMasterDirty();
      _invalidateCaches();
      _notify();
    } catch (e) { debugPrint('deleteItem($id): $e'); }
  }

 ItemModel? getItemById(String id) => _itemMap[id];

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addLocation({
    required String name,
    required String type,
    bool isFinalDestination = false,
  }) async {
    try {
      final now   = DateTime.now().toUtc();
      final locId = await IdGenerator.instance.location();
      await DatabaseHelper.instance.insertLocation({
        'location_id':         locId,
        'location_name':       name,
        'type':                type,
        'created_at':          now.toIso8601String(),
        'updated_at':          now.toIso8601String(),
        'is_deleted':          0,
        'is_final_destination': isFinalDestination ? 1 : 0,
        'shop_id':             _shopId,
      });
      final newLoc = LocationModel(id: locId, name: name, type: type, isFinalDestination: isFinalDestination, createdAt: now, updatedAt: now);
    _locations.add(newLoc);
    _locationMap[locId] = newLoc;
    SyncService.instance.markMasterDirty();
      _notify();
    } catch (e) { debugPrint('addLocation error: $e'); }
  }

  Future<void> editLocation({
    required String id,
    required String name,
    required String type,
    bool isFinalDestination = false,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      await DatabaseHelper.instance.updateLocation(id, {
        'location_name':       name,
        'type':                type,
        'updated_at':          now.toIso8601String(),
        'is_final_destination': isFinalDestination ? 1 : 0,
        'shop_id':             _shopId,
      });
      final loc = _locations.firstWhere((l) => l.id == id);
      loc.name = name; loc.type = type;
      loc.isFinalDestination = isFinalDestination;
      loc.updatedAt = now;
      SyncService.instance.markMasterDirty();
      _notify();
    } catch (e) { debugPrint('editLocation($id): $e'); }
  }

  Future<void> deleteLocation(String id) async {
    try {
      final now = DateTime.now().toUtc();
      await DatabaseHelper.instance.softDeleteLocation(id);
      final loc = _locations.firstWhere((l) => l.id == id);
      loc.isDeleted = true; loc.updatedAt = now;
       _locationMap.remove(id);
      SyncService.instance.markMasterDirty();
      _invalidateCaches();
      _notify();
    } catch (e) { debugPrint('deleteLocation($id): $e'); }
  }

   LocationModel? getLocationById(String id) => _locationMap[id];
StaffModel? staffById(String id) => _staffMap[id];
  // ═══════════════════════════════════════════════════════════════════════════
  // STAFF
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addStaff({
    required String name,
    required String pin,
    String          role = 'staff',
  }) async {
    try {
      final now     = DateTime.now().toUtc();
      final staffId = await IdGenerator.instance.staff();
      await DatabaseHelper.instance.insertStaff({
        'staff_id':   staffId,
        'staff_name': name,
        'pin':        pin,
        'role':       role,
        'created_at': now.toIso8601String(),
        'shop_id':    _shopId,
      });
      final newStaff = StaffModel(id: staffId, name: name, pin: pin, role: role, createdAt: now);
    _staff.add(newStaff);
    _staffMap[staffId] = newStaff;
    SyncService.instance.markMasterDirty();
      _notify();
    } catch (e) { debugPrint('addStaff error: $e'); }
  }

  Future<void> editStaff({
    required String id,
    required String name,
    required String pin,
    String?         role,
  }) async {
    try {
      final s       = _staff.firstWhere((s) => s.id == id);
      final newRole = role ?? s.role;
      await DatabaseHelper.instance.updateStaff(id, {
        'staff_name': name,
        'pin':        pin,
        'role':       newRole,
      });
      s.name = name; s.pin = pin; s.role = newRole;
      if (_currentStaff?.id == id) _currentStaff = s;
      SyncService.instance.markMasterDirty();
      _notify();
    } catch (e) { debugPrint('editStaff($id): $e'); }
  }

  Future<void> deleteStaff(String id) async {
    try {
      await DatabaseHelper.instance.deleteStaff(id);
      _staff.removeWhere((s) => s.id == id);
      _staffMap.remove(id);
      if (_currentStaff?.id == id) _currentStaff = null;
      _notify(); // update UI immediately — local delete is done

      // Hard delete from Supabase — retry on failure
      final result = await SupabaseService.instance.deleteStaff(id);
      if (!result.isSuccess) {
        debugPrint('deleteStaff: Supabase delete failed — will retry via markMasterDirty');
      }
      // markMasterDirty pushes remaining staff — Supabase delete already removed the row
      SyncService.instance.markMasterDirty();
    } catch (e) { debugPrint('deleteStaff($id): $e'); }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOVEMENTS
  // ═══════════════════════════════════════════════════════════════════════════


 Future<bool> addMovement({  
  required String itemId,
  required String fromLocationId,
  required String toLocationId,
  required double quantity,
  required String staffId,
  String?         remark,
  String?         baleNo,
  String?         groupId,
}) async {
  debugPrint('DEBUG addMovement called — staffId=$staffId qty=$quantity');

  // TC-028 — lock FIRST before any validation or await.
  // Prevents two rapid movements both passing stock check in same event loop tick.
  if (_isAddingMovement) {
    debugPrint('addMovement: mutex locked — ignoring duplicate tap');
    return false;
  }
  _isAddingMovement = true;

  try {
    // TC-035 — sanitise free-text before any DB write
    remark = _sanitiseText(remark);
    baleNo = _sanitiseText(baleNo);

    if (quantity <= 0 || fromLocationId == toLocationId) {
      debugPrint('addMovement: invalid params');
      return false;
    }

    if (fromLocationId != 'SUPPLIER') {
      final stock     = getStock();
      final entry     = stock.where((s) =>
          s.item.id     == itemId &&
          s.location.id == fromLocationId,
      ).toList();
      final available = entry.isEmpty ? 0.0 : entry.first.balance;

      if (quantity > available) {
        debugPrint('addMovement: blocked — qty $quantity > available $available');
        return false;
      }

      // Bale validation — bale must exist as incoming at from-location
      if (baleNo != null && baleNo!.isNotEmpty) {
        final baleExists = _movements.any((m) =>
            !m.isDeleted          &&
            m.itemId       == itemId &&
            m.toLocationId == fromLocationId &&
            m.baleNo       == baleNo);
        if (!baleExists) {
          debugPrint('addMovement: bale $baleNo not found at $fromLocationId');
          return false;
        }
      }
    }

    final now   = DateTime.now().toUtc();
    final mvtId = await IdGenerator.instance.movement();
    await DatabaseHelper.instance.insertMovement({
      'movement_id':   mvtId,
      'item_id':       itemId,
      'quantity':      quantity,
      'from_location': fromLocationId,
      'to_location':   toLocationId,
      'staff_id':      staffId,
      'created_at':    now.toIso8601String(),
      'updated_at':    now.toIso8601String(),
      'edited':        0,
      'edited_by':     null,
      'sync_status':   'pending',
      'remark':        remark,
      'bale_no':       baleNo,
      'group_id':      groupId ?? mvtId,
      'shop_id':       _shopId,
    });
    _movements.insert(0, MovementModel(
      id:             mvtId,
      itemId:         itemId,
      fromLocationId: fromLocationId,
      toLocationId:   toLocationId,
      staffId:        staffId,
      quantity:       quantity,
      createdAt:      now,
      remark:         remark,
      baleNo:         baleNo,
      groupId:        groupId ?? mvtId,
    ));
    _invalidateCaches();
    _notify();
    _refreshStockCache();
    SyncService.instance.pushNow();
    return true;

  } catch (e) {
    // TC-029 — surface storage-full as distinct error
    final msg = e.toString().toLowerCase();
    if (msg.contains('disk') || msg.contains('full') || msg.contains('sqlite_full')) {
      debugPrint('addMovement: storage full — $e');
      return false;
    }
    debugPrint('addMovement error: $e');
    return false;
  } finally {
    // Always releases — whether validation failed, exception thrown, or success
    _isAddingMovement = false;
  }
}

// Saves multiple items as one transaction — atomic SQLite insert
// All lines share same groupId, from, to, staff, remark, createdAt
Future<bool> addMultiMovement({
  required String       fromLocationId,
  required String       toLocationId,
  required String       staffId,
  required List<String> itemIds,
  required List<double> quantities,
  required List<String?> baleNos,
  String?               remark,
}) async {
  // TC-028 — same mutex as addMovement
  if (_isAddingMovement) {
    debugPrint('addMultiMovement: mutex locked — ignoring duplicate tap');
    return false;
  }
  // TC-035 — sanitise remark and all baleNos before any DB write
  remark = _sanitiseText(remark);
  baleNos = baleNos.map(_sanitiseText).toList();

  if (itemIds.isEmpty) return false;
  if (fromLocationId == toLocationId) return false;

  if (fromLocationId != 'SUPPLIER') {
    final stock = getStock();
    for (int i = 0; i < itemIds.length; i++) {
      final itemId   = itemIds[i];
      final quantity = quantities[i];
      final baleNo   = baleNos[i];
      if (quantity <= 0) {
        debugPrint('addMultiMovement: qty <= 0 for $itemId');
        return false;
      }
      final entry = stock.where((s) =>
          s.item.id     == itemId &&
          s.location.id == fromLocationId).toList();
      final available = entry.isEmpty ? 0.0 : entry.first.balance;
      if (quantity > available) {
        debugPrint('addMultiMovement: blocked — $itemId qty $quantity > $available');
        return false;
      }
      if (baleNo != null && baleNo.isNotEmpty) {
        final baleExists = _movements.any((m) =>
            !m.isDeleted &&
            m.itemId       == itemId &&
            m.toLocationId == fromLocationId &&
            m.baleNo       == baleNo);
        if (!baleExists) {
          debugPrint('addMultiMovement: bale $baleNo not found for $itemId');
          return false;
        }
      }
    }
    if (itemIds.toSet().length != itemIds.length) {
      debugPrint('addMultiMovement: duplicate item in transaction');
      return false;
    }
  }
_isAddingMovement = true;
  try {
    final now     = DateTime.now().toUtc();
    final groupId = await IdGenerator.instance.movement();
    final db      = DatabaseHelper.instance;
    final insertedModels = <MovementModel>[];

    for (int i = 0; i < itemIds.length; i++) {
      final mvtId  = i == 0 ? groupId : await IdGenerator.instance.movement();
      final itemId = itemIds[i];
      final qty    = quantities[i];
      final baleNo = baleNos[i];
      await db.insertMovement({
        'movement_id':   mvtId,
        'item_id':       itemId,
        'quantity':      qty,
        'from_location': fromLocationId,
        'to_location':   toLocationId,
        'staff_id':      staffId,
        'created_at':    now.toIso8601String(),
        'updated_at':    now.toIso8601String(),
        'edited':        0,
        'edited_by':     null,
        'sync_status':   'pending',
        'remark':        remark,
        'bale_no':       baleNo,
        'group_id':      groupId,
        'shop_id':       _shopId,
      });
      insertedModels.add(MovementModel(
        id:             mvtId,
        itemId:         itemId,
        fromLocationId: fromLocationId,
        toLocationId:   toLocationId,
        staffId:        staffId,
        quantity:       qty,
        createdAt:      now,
        remark:         remark,
        baleNo:         baleNo,
        groupId:        groupId,
      ));
    }

    for (final m in insertedModels.reversed) {
      _movements.insert(0, m);
    }

    _invalidateCaches();
    _notify();
    _refreshStockCache();
    SyncService.instance.pushNow();
    debugPrint('addMultiMovement: saved ${itemIds.length} lines, groupId=$groupId');
    return true;
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('disk') || msg.contains('full') || msg.contains('sqlite_full')) {
      debugPrint('addMultiMovement: storage full — $e');
      return false;
    }
    debugPrint('addMultiMovement error: $e');
    return false;
  } finally {
    _isAddingMovement = false;
  }
}
  Future<bool> editMovement({
    required String movementId,
    required double quantity,
    required String itemId,
    required String fromLocationId,
    required String toLocationId,
    String?         remark,
    String?         baleNo,

  }) async {
    if (quantity <= 0)                  { debugPrint('editMovement: qty <= 0');    return false; }
    if (fromLocationId == toLocationId) { debugPrint('editMovement: from == to'); return false; }

    // TC-035 — sanitise free-text before any DB write
    remark = _sanitiseText(remark);
    baleNo = _sanitiseText(baleNo);

    // TC-018 — SUPPLIER edit: new qty must cover all existing outgoing from toLocation
    if (fromLocationId == 'SUPPLIER') {
      final totalOutgoing = _movements
          .where((m) =>
              !m.isDeleted &&
              m.id             != movementId &&
              m.itemId         == itemId &&
              m.fromLocationId == toLocationId)
          .fold<double>(0, (sum, m) => sum + m.quantity);
      if (quantity < totalOutgoing) {
        debugPrint('editMovement: SUPPLIER qty $quantity < outgoing $totalOutgoing — blocked');
        return false;
      }
    }

    // Bale validation on edit...
    if (fromLocationId != 'SUPPLIER' && baleNo != null && baleNo!.isNotEmpty) {
      final baleExists = _movements.any((m) =>
          !m.isDeleted &&
          m.id           != movementId &&  // exclude self
          m.itemId       == itemId &&
          m.toLocationId == fromLocationId &&
          m.baleNo       == baleNo);
      if (!baleExists) {
        debugPrint('editMovement: bale $baleNo not found at $fromLocationId');
        return false;
      }
    }
    try {
      final now     = DateTime.now().toUtc();
      final staffId = _currentStaff?.id;
      await DatabaseHelper.instance.updateMovement(movementId, {
        'quantity':      quantity,
        'from_location': fromLocationId,
        'to_location':   toLocationId,
        'remark':        remark,
         'bale_no':       baleNo,
        'edited':        1,
        'edited_by':     staffId,
        'updated_at':    now.toIso8601String(),
        'sync_status':   'pending',
      });
      final m = _movements.firstWhere((m) => m.id == movementId);
      m.quantity       = quantity;
      m.fromLocationId = fromLocationId;
      m.toLocationId   = toLocationId;
      m.remark         = remark;
      m.baleNo         = baleNo;
      m.edited         = true;
      m.editedBy       = staffId;
      m.editedAt       = now;
      m.syncStatus     = 'pending';
      _invalidateCaches();
      _notify();
      _refreshStockCache();
      SyncService.instance.pushNow(); // push immediately
      return true;
    } catch (e) { debugPrint('editMovement($movementId): $e'); return false; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  // Admin only — soft delete movement, sync to all devices
  // Deletes all movements in the same group (transaction)
  Future<bool> deleteMovement(String movementId) async {
    try {
      final staffId = _currentStaff?.id;

      // Find groupId for this movement
      final movement = _movements.firstWhere(
        (m) => m.id == movementId,
        orElse: () => throw Exception('movement not found'),
      );
      final groupId = movement.groupId;

      // Get all movements in this group
      final groupRows = await DatabaseHelper.instance
          .getMovementsByGroupId(groupId);
      final groupIds = groupRows
          .map((r) => r['movement_id'] as String)
          .toList();

      // Soft-delete all in group
      for (final id in groupIds) {
        await DatabaseHelper.instance.softDeleteMovement(
            id, deletedBy: staffId);
        final idx = _movements.indexWhere((m) => m.id == id);
        if (idx >= 0) {
          _movements[idx].isDeleted  = true;
          _movements[idx].syncStatus = 'pending';
        }
      }

      _invalidateCaches();
      _notify();
      _refreshStockCache();
      SyncService.instance.pushNow();
      debugPrint('deleteMovement: deleted group $groupId (${groupIds.length} lines)');
      return true;
    } catch (e) {
      debugPrint('deleteMovement($movementId): $e');
      return false;
    }
  }

  Future<void> mergeRemoteMovement(Map<String,dynamic> row) async {
    try {
      // Parse off main thread
      final normalised = _normaliseRemoteRow(row);
      final m          = await compute(
        (r) => MovementModel.fromMap(r),
        normalised,
      );
      final idx = _movements.indexWhere((e) => e.id == m.id);
      if (idx >= 0) {
        _movements[idx] = m;
      } else if (!m.isDeleted) {
        _movements.insert(0, m);
      }
      _invalidateCaches();
      // Use notifyNow for deletions — ensures UI removes row immediately
      if (m.isDeleted) {
        _notifyNow();
      } else {
        _notify();
      }
      _refreshStockCache();
      debugPrint('AppDataProvider: remote movement merged — ${m.id}');
    } catch (e) {
      debugPrint('AppDataProvider.mergeRemoteMovement error: $e');
      await _reloadMovements();
    }
  }

  Map<String,dynamic> _normaliseRemoteRow(Map<String,dynamic> row) => {
    'movement_id':   row['movement_id']?.toString(),
    'item_id':       row['item_id']?.toString(),
    'quantity':      row['quantity'],
    'from_location': row['from_location']?.toString(),
    'to_location':   row['to_location']?.toString(),
    'staff_id':      row['staff_id']?.toString(),
    'created_at':    row['created_at']?.toString(),
    'updated_at':    row['updated_at']?.toString(),
    'edited':        row['edited'] == true ? 1 : 0,
    'edited_by':     row['edited_by']?.toString(),
    'sync_status':   'synced',
    'remark':        row['remark']?.toString(),
    'bale_no':       row['bale_no']?.toString(),
    'is_deleted':    (row['is_deleted'] == true || row['is_deleted'] == 1) ? 1 : 0,
  };

  Future<void> _reloadMovements() async {
    try {
      final rows   = await DatabaseHelper.instance.getMovements(limit: 99999);
      final parsed = await compute(_parseMovements, rows);
      _movements..clear()..addAll(parsed);
      _invalidateCaches();
      _notifyNow();
      _refreshStockCache();
    } catch (e) { debugPrint('AppDataProvider._reloadMovements error: $e'); }
  }

  void _markMovementsSyncedInMemory(List<String> ids) {
    final idSet = ids.toSet();
    for (final m in _movements) {
      if (idSet.contains(m.id)) m.syncStatus = 'synced';
    }
    _notify();
  }

  Future<bool> syncNow() async {
    final result = await SyncService.instance.sync(silent: false);
    final ok = result.isSuccess;
    if (ok) await _reloadMovements();
    return ok;
  }

  Future<void> markAllSynced() async {
    try {
      await DatabaseHelper.instance.markAllSynced();
      for (final m in _movements) { m.syncStatus = 'synced'; }
      _notify();
    } catch (e) { debugPrint('markAllSynced: $e'); }
  }
}
