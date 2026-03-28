import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// app_data_provider.dart
//
// Single source of truth for all app data.
// Phase 2: swap method bodies with SQLite calls — screens unchanged.
//
// Memory notes:
//   • All lists are plain List<T> — no StreamControllers, no duplicates
//   • notifyListeners() called only after actual state change
//   • getStock() computed on demand — not cached — avoids stale data
//   • fromLocationId = -1 means external supplier (opening stock)
// ─────────────────────────────────────────────────────────────────────────────

// ─── Models ───────────────────────────────────────────────────────────────────

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
}

class LocationModel {
  final int      id;
  String         name;
  String         type; // 'godown' or 'shop'
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
}

class StaffModel {
  final int      id;
  String         name;
  String         pin;
  String         role; // 'admin' or 'staff'
  final DateTime createdAt;

  StaffModel({
    required this.id,
    required this.name,
    required this.pin,
    this.role = 'staff', // default is staff
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';
}

class MovementModel {
  final int      id;
  final int      itemId;
  final int      fromLocationId; // -1 = external supplier
  final int      toLocationId;
  final int      staffId;
  final double   quantity;
  final DateTime createdAt;
  bool           edited;
  int?           editedBy;
  DateTime?      editedAt;
  String?        remark;
  String         syncStatus; // 'pending' | 'synced'

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

// ─── Provider ─────────────────────────────────────────────────────────────────

class AppDataProvider extends ChangeNotifier {

  // Private lists — only mutated through methods below
  final List<ItemModel>     _items     = [];
  final List<LocationModel> _locations = [];
  final List<StaffModel>    _staff     = [];
  final List<MovementModel> _movements = [];

  StaffModel? _currentStaff;
  bool        _disposed = false;

  // Auto-increment counters (replaced by DB in Phase 2)
  int _itemId     = 1;
  int _locationId = 1;
  int _staffId    = 1;
  int _movementId = 1;

  // ── Public getters (filtered, read-only views) ───────────────────────────────
  List<ItemModel>     get items    => _items.where((i) => !i.isDeleted).toList();
  List<LocationModel> get locations=> _locations.where((l) => !l.isDeleted).toList();
  List<StaffModel>    get staff    => List.unmodifiable(_staff);
  StaffModel?         get currentStaff => _currentStaff;
  bool get isLoggedIn => _currentStaff != null;
  bool get isAdmin    => _currentStaff?.isAdmin ?? false;

  int get pendingSyncCount => _movements.where((m) => m.syncStatus == 'pending').length;
  int get syncedCount      => _movements.where((m) => m.syncStatus == 'synced').length;
  int get totalMovements   => _movements.length;

  // Sorted newest first — avoids mutating internal list
  List<MovementModel> get sortedMovements {
    final list = List<MovementModel>.from(_movements);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ── Constructor ───────────────────────────────────────────────────────────────
  AppDataProvider() {
    _seedData();
  }

  // Safe notify — prevents calling after dispose
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ─── Seed data ────────────────────────────────────────────────────────────────
  void _seedData() {
    final now = DateTime.now();

    // Real products from spec
    for (final name in [
      '60*90 Dabangg',
      '60*90 Jio Vip',
      '90*100 Sonata White',
      '90*100 Khubsurat Set',
      '108*108 Flora Bedsheet',
      '70*90 Metro',
      '90*100 Metro',
      '60*90 Metro',
    ]) {
      _items.add(ItemModel(
        id: _itemId++, name: name, unit: 'pcs',
        createdAt: now, updatedAt: now,
      ));
    }

    // Locations
    for (final entry in [
      ('Godown A', 'godown'), ('Godown B', 'godown'),
      ('Godown C', 'godown'), ('Shop', 'shop'),
    ]) {
      _locations.add(LocationModel(
        id: _locationId++, name: entry.$1, type: entry.$2,
        createdAt: now, updatedAt: now,
      ));
    }

    // Staff — first entry is admin (the owner/manager)
    final staffSeed = [
      ('Ramesh', '1234', 'admin'),  // owner — full access
      ('Suresh', '5678', 'staff'),
      ('Dinesh', '9012', 'staff'),
    ];
    for (final entry in staffSeed) {
      _staff.add(StaffModel(
        id: _staffId++, name: entry.$1, pin: entry.$2,
        role: entry.$3, createdAt: now,
      ));
    }

    // Seed movements for History + Stock to show real data
    // itemId 1-8 match the products above, locationId 1-4
    final seeds = [
      (itemId: 1, from: 1, to: 4, staff: 1, qty: 100.0, hrs: 2,  edited: false, editedBy: 0, remark: ''),
      (itemId: 2, from: 1, to: 4, staff: 2, qty: 50.0,  hrs: 3,  edited: false, editedBy: 0, remark: ''),
      (itemId: 3, from: 2, to: 4, staff: 1, qty: 30.0,  hrs: 5,  edited: true,  editedBy: 2, remark: ''),
      (itemId: 4, from: 1, to: 4, staff: 3, qty: 25.0,  hrs: 6,  edited: false, editedBy: 0, remark: ''),
      (itemId: 5, from: 2, to: 4, staff: 2, qty: 60.0,  hrs: 26, edited: false, editedBy: 0, remark: ''),
      (itemId: 6, from: 1, to: 2, staff: 1, qty: 40.0,  hrs: 28, edited: false, editedBy: 0, remark: 'Transfer to B'),
      (itemId: 7, from: 2, to: 4, staff: 3, qty: 20.0,  hrs: 30, edited: true,  editedBy: 1, remark: ''),
      (itemId: 8, from: 1, to: 4, staff: 2, qty: 35.0,  hrs: 50, edited: false, editedBy: 0, remark: ''),
      (itemId: 1, from: 2, to: 1, staff: 1, qty: 200.0, hrs: 52, edited: false, editedBy: 0, remark: 'Restocking'),
      (itemId: 3, from: 1, to: 4, staff: 3, qty: 15.0,  hrs: 54, edited: false, editedBy: 0, remark: ''),
    ];

    for (final s in seeds) {
      _movements.add(MovementModel(
        id:             _movementId++,
        itemId:         s.itemId,
        fromLocationId: s.from,
        toLocationId:   s.to,
        staffId:        s.staff,
        quantity:       s.qty,
        createdAt:      now.subtract(Duration(hours: s.hrs)),
        edited:         s.edited,
        editedBy:       s.edited ? s.editedBy : null,
        editedAt:       s.edited
            ? now.subtract(Duration(hours: s.hrs - 1))
            : null,
        remark:         s.remark.isEmpty ? null : s.remark,
        syncStatus:     'pending',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEM METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  // TODO Phase 2: await db.insertItem(...)
  void addItem({
    required String name,
    required String unit,
    int?    openingLocationId,
    double? openingQty,
  }) {
    final now    = DateTime.now();
    final itemId = _itemId++;

    _items.add(ItemModel(
      id: itemId, name: name, unit: unit,
      createdAt: now, updatedAt: now,
    ));

    // Create opening stock movement if provided
    if (openingLocationId != null && openingQty != null && openingQty > 0) {
      _movements.insert(0, MovementModel(
        id:             _movementId++,
        itemId:         itemId,
        fromLocationId: -1, // -1 = external supplier
        toLocationId:   openingLocationId,
        staffId:        _currentStaff?.id ?? (_staff.isNotEmpty ? _staff.first.id : 1),
        quantity:       openingQty,
        createdAt:      now,
        remark:         'Opening stock',
        syncStatus:     'pending',
      ));
    }
    _notify();
  }

  // TODO Phase 2: await db.updateItem(...)
  void editItem({required int id, required String name, required String unit}) {
    try {
      final item     = _items.firstWhere((i) => i.id == id);
      item.name      = name;
      item.unit      = unit;
      item.updatedAt = DateTime.now();
      _notify();
    } catch (e) {
      debugPrint('editItem: item $id not found');
    }
  }

  // Soft delete — is_deleted = true, never removed from list
  // TODO Phase 2: await db.softDeleteItem(...)
  void deleteItem(int id) {
    try {
      final item     = _items.firstWhere((i) => i.id == id);
      item.isDeleted = true;
      item.updatedAt = DateTime.now();
      _notify();
    } catch (e) {
      debugPrint('deleteItem: item $id not found');
    }
  }

  ItemModel? getItemById(int id) {
    try {
      return _items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void addLocation({required String name, required String type}) {
    final now = DateTime.now();
    _locations.add(LocationModel(
      id: _locationId++, name: name, type: type,
      createdAt: now, updatedAt: now,
    ));
    _notify();
  }

  void editLocation({required int id, required String name, required String type}) {
    try {
      final loc     = _locations.firstWhere((l) => l.id == id);
      loc.name      = name;
      loc.type      = type;
      loc.updatedAt = DateTime.now();
      _notify();
    } catch (e) {
      debugPrint('editLocation: location $id not found');
    }
  }

  void deleteLocation(int id) {
    try {
      final loc     = _locations.firstWhere((l) => l.id == id);
      loc.isDeleted = true;
      loc.updatedAt = DateTime.now();
      _notify();
    } catch (e) {
      debugPrint('deleteLocation: location $id not found');
    }
  }

  LocationModel? getLocationById(int id) {
    try {
      return _locations.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAFF METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void addStaff({
    required String name,
    required String pin,
    String role = 'staff',
  }) {
    _staff.add(StaffModel(
      id: _staffId++, name: name, pin: pin,
      role: role, createdAt: DateTime.now(),
    ));
    _notify();
  }

  void editStaff({
    required int    id,
    required String name,
    required String pin,
    String? role,
  }) {
    try {
      final s = _staff.firstWhere((s) => s.id == id);
      s.name = name;
      s.pin  = pin;
      if (role != null) s.role = role;
      _notify();
    } catch (e) {
      debugPrint('editStaff: staff $id not found');
    }
  }

  void deleteStaff(int id) {
    _staff.removeWhere((s) => s.id == id);
    _notify();
  }

  // Returns true on success, false on wrong PIN
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

  // Auto-login from saved device session — no PIN needed
  // Called on app startup when SharedPreferences has a saved staff ID
  void loginWithoutPin({required int staffId}) {
    try {
      final s = _staff.firstWhere((s) => s.id == staffId);
      _currentStaff = s;
      _notify();
    } catch (e) {
      debugPrint('loginWithoutPin: staff $staffId not found');
    }
  }

  void logout() {
    _currentStaff = null;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOVEMENT METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  // TODO Phase 2: await db.insertMovement(...)
  void addMovement({
    required int    itemId,
    required int    fromLocationId,
    required int    toLocationId,
    required double quantity,
    required int    staffId,
    String?         remark,
  }) {
    // Basic validation
    if (quantity <= 0) {
      debugPrint('addMovement: invalid quantity $quantity');
      return;
    }
    if (fromLocationId == toLocationId) {
      debugPrint('addMovement: from == to, rejected');
      return;
    }

    _movements.insert(0, MovementModel(
      id:             _movementId++,
      itemId:         itemId,
      fromLocationId: fromLocationId,
      toLocationId:   toLocationId,
      staffId:        staffId,
      quantity:       quantity,
      createdAt:      DateTime.now(),
      remark:         remark,
      syncStatus:     'pending',
    ));
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK CALCULATION  — spec section 8: Balance = Incoming − Outgoing
  // ═══════════════════════════════════════════════════════════════════════════

  List<StockBalance> getStock() {
    final activeLocations = locations; // already filters isDeleted
    final activeItems     = items;
    final result          = <StockBalance>[];

    for (final loc in activeLocations) {
      for (final item in activeItems) {
        double incoming = 0;
        double outgoing = 0;

        for (final m in _movements) {
          if (m.itemId != item.id) continue;
          // fromLocationId = -1 (supplier) counts as incoming to toLocation only
          if (m.toLocationId   == loc.id) incoming += m.quantity;
          if (m.fromLocationId == loc.id) outgoing += m.quantity;
        }

        if (incoming > 0 || outgoing > 0) {
          result.add(StockBalance(
            location: loc,
            item:     item,
            incoming: incoming,
            outgoing: outgoing,
          ));
        }
      }
    }
    return result;
  }

  List<StockBalance> getStockForLocation(int locationId) =>
      getStock().where((s) => s.location.id == locationId).toList();

  double totalStockForItem(int itemId) =>
      getStock()
          .where((s) => s.item.id == itemId)
          .fold(0, (sum, s) => sum + s.balance);

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  // TODO Phase 2: push pending to Supabase, then mark synced
  void markAllSynced() {
    for (final m in _movements) {
      m.syncStatus = 'synced';
    }
    _notify();
  }
}
