// ─────────────────────────────────────────────────────────────────────────────
// app_data_provider.dart  —  Phase 2
//
// All data now persists to SQLite via DatabaseHelper.
// Screens are completely unchanged — they still call the same methods.
//
// Loading pattern:
//   • initialize() is called once from main() before runApp
//   • Loads all tables into memory for fast UI reads
//   • Every write goes to DB first, then updates memory + notifies UI
//   • This gives us: fast reads (memory) + persistence (SQLite)
//
// Concurrency:
//   • All DB calls are async/await — non-blocking
//   • _disposed guard prevents notify after widget tree teardown
//   • Single isolate — no parallel mutation possible
// ─────────────────────────────────────────────────────────────────────────────
import '../database/database_helper.dart';
import 'package:flutter/foundation.dart';


// ═══════════════════════════════════════════════════════════════════════════
// MODELS  (unchanged from Phase 1 — screens need no changes)
// ═══════════════════════════════════════════════════════════════════════════

class ItemModel {
  final int      id;
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
    id:        m['item_id']   as int,
    name:      m['item_name'] as String,
    unit:      m['unit']      as String,
    isDeleted: (m['is_deleted'] as int) == 1,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'item_name':  name,
    'unit':       unit,
    'is_deleted': isDeleted ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class LocationModel {
  final int      id;
  String         name;
  String         type;
  bool           isDeleted;
  final DateTime createdAt;
  DateTime       updatedAt;

  LocationModel({
    required this.id,
    required this.name,
    required this.type,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocationModel.fromMap(Map<String, dynamic> m) => LocationModel(
    id:        m['location_id']   as int,
    name:      m['location_name'] as String,
    type:      m['type']          as String,
    isDeleted: (m['is_deleted']   as int) == 1,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'location_name': name,
    'type':          type,
    'is_deleted':    isDeleted ? 1 : 0,
    'created_at':    createdAt.toIso8601String(),
    'updated_at':    updatedAt.toIso8601String(),
  };
}

class StaffModel {
  final int      id;
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
    id:        m['staff_id']   as int,
    name:      m['staff_name'] as String,
    pin:       m['pin']        as String,
    role:      m['role']       as String,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'staff_name': name,
    'pin':        pin,
    'role':       role,
    'created_at': createdAt.toIso8601String(),
  };
}

class MovementModel {
  final int      id;
  final int      itemId;
  final int      fromLocationId;
  final int      toLocationId;
  final int      staffId;
  final double   quantity;
  final DateTime createdAt;
  bool           edited;
  int?           editedBy;
  DateTime?      editedAt;
  String?        remark;
  String         syncStatus;

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
    this.syncStatus = 'pending',
  });

  factory MovementModel.fromMap(Map<String, dynamic> m) => MovementModel(
    id:             m['movement_id']   as int,
    itemId:         m['item_id']       as int,
    fromLocationId: m['from_location'] as int,
    toLocationId:   m['to_location']   as int,
    staffId:        m['staff_id']      as int,
    quantity:       (m['quantity']     as num).toDouble(),
    createdAt:      DateTime.parse(m['created_at'] as String),
    edited:         (m['edited']       as int) == 1,
    editedBy:       m['edited_by']     as int?,
    editedAt:       m['updated_at'] != null
        ? DateTime.parse(m['updated_at'] as String)
        : null,
    remark:         m['remark']        as String?,
    syncStatus:     m['sync_status']   as String,
  );

  Map<String, dynamic> toMap() => {
    'item_id':       itemId,
    'quantity':      quantity,
    'from_location': fromLocationId,
    'to_location':   toLocationId,
    'staff_id':      staffId,
    'created_at':    createdAt.toIso8601String(),
    'updated_at':    (editedAt ?? createdAt).toIso8601String(),
    'edited':        edited ? 1 : 0,
    'edited_by':     editedBy,
    'sync_status':   syncStatus,
    'remark':        remark,
  };
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

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class AppDataProvider extends ChangeNotifier {

  // In-memory cache — loaded from DB on initialize()
  final List<ItemModel>     _items     = [];
  final List<LocationModel> _locations = [];
  final List<StaffModel>    _staff     = [];
  final List<MovementModel> _movements = [];

  StaffModel? _currentStaff;
  bool        _disposed   = false;
  bool        _isLoading  = true;

  // ── Public getters ─────────────────────────────────────────────────────────
  List<ItemModel>     get items     => _items.where((i) => !i.isDeleted).toList();
  List<LocationModel> get locations => _locations.where((l) => !l.isDeleted).toList();
  List<StaffModel>    get staff     => List.unmodifiable(_staff);
  StaffModel?         get currentStaff   => _currentStaff;
  bool                get isLoggedIn     => _currentStaff != null;
  bool                get isAdmin        => _currentStaff?.isAdmin ?? false;
  bool                get isLoading      => _isLoading;
  int                 get pendingSyncCount =>
      _movements.where((m) => m.syncStatus == 'pending').length;
  int                 get syncedCount =>
      _movements.where((m) => m.syncStatus == 'synced').length;
  int                 get totalMovements => _movements.length;

  List<MovementModel> get sortedMovements {
    final list = List<MovementModel>.from(_movements);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZE — called once from main() before runApp
  // Loads all data from SQLite into memory
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    try {
      await _loadAll();
    } catch (e) {
      debugPrint('AppDataProvider.initialize error: $e');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> _loadAll() async {
    final db = DatabaseHelper.instance;

    final results = await Future.wait([
      db.getItems(),
      db.getLocations(),
      db.getStaff(),
      db.getMovements(),
    ]);

    _items    ..clear()..addAll(results[0].map(ItemModel.fromMap));
    _locations..clear()..addAll(results[1].map(LocationModel.fromMap));
    _staff    ..clear()..addAll(results[2].map(StaffModel.fromMap));
    _movements..clear()..addAll(results[3].map(MovementModel.fromMap));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  bool login({required int staffId, required String pin}) {
    try {
      final s = _staff.firstWhere((s) => s.id == staffId);
      if (s.pin == pin) {
        _currentStaff = s;
        _notify();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void loginWithoutPin({required int staffId}) {
    try {
      final s = _staff.firstWhere((s) => s.id == staffId);
      _currentStaff = s;
      _notify();
    } catch (e) {
      debugPrint('loginWithoutPin: $e');
    }
  }

  void logout() {
    _currentStaff = null;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEMS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addItem({
    required String name,
    required String unit,
    int?    openingLocationId,
    double? openingQty,
  }) async {
    final now = DateTime.now();
    final db  = DatabaseHelper.instance;

    // Write to DB first — get auto-incremented ID back
    final itemId = await db.insertItem({
      'item_name':  name,
      'unit':       unit,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'is_deleted': 0,
    });

    // Update memory
    _items.add(ItemModel(
      id: itemId, name: name, unit: unit,
      createdAt: now, updatedAt: now,
    ));

    // Opening stock movement if provided
    if (openingLocationId != null && openingQty != null && openingQty > 0) {
      final mvtId = await db.insertMovement({
        'item_id':       itemId,
        'quantity':      openingQty,
        'from_location': -1,
        'to_location':   openingLocationId,
        'staff_id':      _currentStaff?.id ?? 1,
        'created_at':    now.toIso8601String(),
        'updated_at':    now.toIso8601String(),
        'edited':        0,
        'edited_by':     null,
        'sync_status':   'pending',
        'remark':        'Opening stock',
      });

      _movements.insert(0, MovementModel(
        id:             mvtId,
        itemId:         itemId,
        fromLocationId: -1,
        toLocationId:   openingLocationId,
        staffId:        _currentStaff?.id ?? 1,
        quantity:       openingQty,
        createdAt:      now,
        remark:         'Opening stock',
      ));
    }

    _notify();
  }

  Future<void> editItem({
    required int    id,
    required String name,
    required String unit,
  }) async {
    final now = DateTime.now();
    try {
      await DatabaseHelper.instance.updateItem(id, {
        'item_name':  name,
        'unit':       unit,
        'updated_at': now.toIso8601String(),
      });
      final item     = _items.firstWhere((i) => i.id == id);
      item.name      = name;
      item.unit      = unit;
      item.updatedAt = now;
      _notify();
    } catch (e) {
      debugPrint('editItem($id): $e');
    }
  }

  Future<void> deleteItem(int id) async {
    final now = DateTime.now();
    try {
      await DatabaseHelper.instance.softDeleteItem(id);
      final item     = _items.firstWhere((i) => i.id == id);
      item.isDeleted = true;
      item.updatedAt = now;
      _notify();
    } catch (e) {
      debugPrint('deleteItem($id): $e');
    }
  }

  ItemModel? getItemById(int id) {
    try { return _items.firstWhere((i) => i.id == id); }
    catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addLocation({
    required String name,
    required String type,
  }) async {
    final now  = DateTime.now();
    final db   = DatabaseHelper.instance;
    final locId = await db.insertLocation({
      'location_name': name,
      'type':          type,
      'created_at':    now.toIso8601String(),
      'updated_at':    now.toIso8601String(),
      'is_deleted':    0,
    });
    _locations.add(LocationModel(
      id: locId, name: name, type: type,
      createdAt: now, updatedAt: now,
    ));
    _notify();
  }

  Future<void> editLocation({
    required int    id,
    required String name,
    required String type,
  }) async {
    final now = DateTime.now();
    try {
      await DatabaseHelper.instance.updateLocation(id, {
        'location_name': name,
        'type':          type,
        'updated_at':    now.toIso8601String(),
      });
      final loc    = _locations.firstWhere((l) => l.id == id);
      loc.name      = name;
      loc.type      = type;
      loc.updatedAt = now;
      _notify();
    } catch (e) {
      debugPrint('editLocation($id): $e');
    }
  }

  Future<void> deleteLocation(int id) async {
    final now = DateTime.now();
    try {
      await DatabaseHelper.instance.softDeleteLocation(id);
      final loc     = _locations.firstWhere((l) => l.id == id);
      loc.isDeleted = true;
      loc.updatedAt = now;
      _notify();
    } catch (e) {
      debugPrint('deleteLocation($id): $e');
    }
  }

  LocationModel? getLocationById(int id) {
    try { return _locations.firstWhere((l) => l.id == id); }
    catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAFF
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addStaff({
    required String name,
    required String pin,
    String          role = 'staff',
  }) async {
    final now     = DateTime.now();
    final staffId = await DatabaseHelper.instance.insertStaff({
      'staff_name': name,
      'pin':        pin,
      'role':       role,
      'created_at': now.toIso8601String(),
    });
    _staff.add(StaffModel(
      id: staffId, name: name, pin: pin,
      role: role, createdAt: now,
    ));
    _notify();
  }

  Future<void> editStaff({
    required int    id,
    required String name,
    required String pin,
    String?         role,
  }) async {
    try {
      final s      = _staff.firstWhere((s) => s.id == id);
      final newRole = role ?? s.role;
      await DatabaseHelper.instance.updateStaff(id, {
        'staff_name': name,
        'pin':        pin,
        'role':       newRole,
      });
      s.name = name;
      s.pin  = pin;
      s.role = newRole;
      if (_currentStaff?.id == id) _currentStaff = s;
      _notify();
    } catch (e) {
      debugPrint('editStaff($id): $e');
    }
  }

  Future<void> deleteStaff(int id) async {
    try {
      await DatabaseHelper.instance.deleteStaff(id);
      _staff.removeWhere((s) => s.id == id);
      if (_currentStaff?.id == id) _currentStaff = null;
      _notify();
    } catch (e) {
      debugPrint('deleteStaff($id): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOVEMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> addMovement({
    required int    itemId,
    required int    fromLocationId,
    required int    toLocationId,
    required double quantity,
    required int    staffId,
    String?         remark,
  }) async {
    if (quantity <= 0 || fromLocationId == toLocationId) {
      debugPrint('addMovement: invalid params');
      return;
    }

    final now = DateTime.now();
    final mvtId = await DatabaseHelper.instance.insertMovement({
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
    ));
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK  — calculated from DB SQL query (fast, indexed)
  // ═══════════════════════════════════════════════════════════════════════════

  // Returns pre-calculated stock from the in-memory movement list
  // Same logic as before — no screen changes needed
  List<StockBalance> getStock() {
    final result = <StockBalance>[];

    for (final loc in locations) {
      for (final item in items) {
        double incoming = 0;
        double outgoing = 0;

        for (final m in _movements) {
          if (m.itemId != item.id) continue;
          if (m.toLocationId   == loc.id) incoming += m.quantity;
          if (m.fromLocationId == loc.id) outgoing += m.quantity;
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

  double totalStockForItem(int itemId) => getStock()
      .where((s) => s.item.id == itemId)
      .fold(0, (sum, s) => sum + s.balance);

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> markAllSynced() async {
    try {
      await DatabaseHelper.instance.markAllSynced();
      for (final m in _movements) {
        m.syncStatus = 'synced';
      }
      _notify();
    } catch (e) {
      debugPrint('markAllSynced: $e');
    }
  }
}