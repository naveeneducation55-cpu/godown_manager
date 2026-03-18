// ─────────────────────────────────────────────────────────────────────────────
// app_data_provider.dart
//
// Central data store for the entire app.
// Every screen reads from and writes to this provider.
//
// Phase 2 note:
//   Every method marked with "// TODO Phase 2" will be replaced
//   with a real SQLite DB call. The screens will NOT need to change —
//   only the implementation inside each method changes.
//
// Data held:
//   • items       — all inventory items
//   • locations   — all godowns + shops
//   • staff       — all staff members
//   • movements   — all stock movements (the core transaction log)
//
// Stock calculation:
//   Balance = incoming − outgoing  (spec section 8)
//   Calculated on demand from movements — never stored separately
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

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
  final DateTime createdAt;

  StaffModel({
    required this.id,
    required this.name,
    required this.pin,
    required this.createdAt,
  });
}

class MovementModel {
  final int        id;
  final int        itemId;
  final int        fromLocationId;
  final int        toLocationId;
  final int        staffId;
  final double     quantity;
  final DateTime   createdAt;
  bool             edited;
  int?             editedBy;
  DateTime?        editedAt;
  String?          remark;
  String           syncStatus; // 'pending' or 'synced'

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

// ─── Stock result — returned by getStock() ────────────────────────────────────
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

  // ── Internal lists ──────────────────────────────────────────────────────────
  final List<ItemModel>     _items     = [];
  final List<LocationModel> _locations = [];
  final List<StaffModel>    _staff     = [];
  final List<MovementModel> _movements = [];

  // Currently logged-in staff (set by login screen)
  StaffModel? _currentStaff;

  // ID counters (DB auto-increments in Phase 2)
  int _itemId     = 1;
  int _locationId = 1;
  int _staffId    = 1;
  int _movementId = 1;

  // ── Public read-only getters ─────────────────────────────────────────────────
  List<ItemModel>     get items      => _items.where((i) => !i.isDeleted).toList();
  List<LocationModel> get locations  => _locations.where((l) => !l.isDeleted).toList();
  List<StaffModel>    get staff      => List.unmodifiable(_staff);
  List<MovementModel> get movements  => List.unmodifiable(_movements);
  StaffModel?         get currentStaff => _currentStaff;

  bool get hasStaff     => _staff.isNotEmpty;
  bool get isLoggedIn   => _currentStaff != null;

  // ── Constructor — seed with default data ────────────────────────────────────
  AppDataProvider() {
    _seedData();
  }

  void _seedData() {
    final now = DateTime.now();

    // Default items
    _items.addAll([
      ItemModel(id:_itemId++, name:'Rice',         unit:'kg',    createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Sugar',        unit:'kg',    createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Wheat flour',  unit:'kg',    createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Mustard oil',  unit:'litre', createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Dal',          unit:'kg',    createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Salt',         unit:'kg',    createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Ghee',         unit:'kg',    createdAt:now, updatedAt:now),
      ItemModel(id:_itemId++, name:'Diesel',       unit:'litre', createdAt:now, updatedAt:now),
    ]);

    // Default locations
    _locations.addAll([
      LocationModel(id:_locationId++, name:'Godown A',  type:'godown', createdAt:now, updatedAt:now),
      LocationModel(id:_locationId++, name:'Godown B',  type:'godown', createdAt:now, updatedAt:now),
      LocationModel(id:_locationId++, name:'Godown C',  type:'godown', createdAt:now, updatedAt:now),
      LocationModel(id:_locationId++, name:'Shop',      type:'shop',   createdAt:now, updatedAt:now),
      LocationModel(id:_locationId++, name:'Warehouse', type:'godown', createdAt:now, updatedAt:now),
    ]);

    // Default staff
    _staff.addAll([
      StaffModel(id:_staffId++, name:'Ramesh', pin:'1234', createdAt:now),
      StaffModel(id:_staffId++, name:'Suresh', pin:'5678', createdAt:now),
      StaffModel(id:_staffId++, name:'Dinesh', pin:'9012', createdAt:now),
    ]);

    // Seed some past movements so History and Stock screens are not empty
    final movements = [
      (itemId:1, fromId:1, toId:4, staffId:1, qty:50.0,  hoursAgo:2,  edited:false, editedBy:0,  remark:''),
      (itemId:2, fromId:2, toId:1, staffId:2, qty:20.0,  hoursAgo:3,  edited:true,  editedBy:1,  remark:''),
      (itemId:8, fromId:1, toId:4, staffId:3, qty:100.0, hoursAgo:5,  edited:false, editedBy:0,  remark:'Urgent transfer'),
      (itemId:5, fromId:2, toId:4, staffId:1, qty:30.0,  hoursAgo:6,  edited:false, editedBy:0,  remark:''),
      (itemId:4, fromId:1, toId:4, staffId:2, qty:40.0,  hoursAgo:26, edited:false, editedBy:0,  remark:''),
      (itemId:7, fromId:2, toId:1, staffId:3, qty:15.0,  hoursAgo:28, edited:true,  editedBy:2,  remark:''),
      (itemId:1, fromId:1, toId:2, staffId:1, qty:200.0, hoursAgo:30, edited:false, editedBy:0,  remark:'Monthly transfer'),
      (itemId:2, fromId:2, toId:4, staffId:2, qty:50.0,  hoursAgo:50, edited:false, editedBy:0,  remark:''),
      (itemId:8, fromId:1, toId:2, staffId:3, qty:200.0, hoursAgo:52, edited:false, editedBy:0,  remark:''),
      (itemId:5, fromId:1, toId:4, staffId:1, qty:80.0,  hoursAgo:54, edited:true,  editedBy:3,  remark:'Corrected qty'),
    ];

    for (final m in movements) {
      _movements.add(MovementModel(
        id:             _movementId++,
        itemId:         m.itemId,
        fromLocationId: m.fromId,
        toLocationId:   m.toId,
        staffId:        m.staffId,
        quantity:       m.qty,
        createdAt:      now.subtract(Duration(hours: m.hoursAgo)),
        edited:         m.edited,
        editedBy:       m.edited ? m.editedBy : null,
        editedAt:       m.edited ? now.subtract(Duration(hours: m.hoursAgo - 1)) : null,
        remark:         m.remark.isEmpty ? null : m.remark,
        syncStatus:     'pending',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEM METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  // Add a new item
  // TODO Phase 2: await DatabaseHelper.instance.insertItem(item)
  void addItem({required String name, required String unit}) {
    final now = DateTime.now();
    _items.add(ItemModel(
      id:        _itemId++,
      name:      name,
      unit:      unit,
      createdAt: now,
      updatedAt: now,
    ));
    notifyListeners();
  }

  // Edit an existing item
  // TODO Phase 2: await DatabaseHelper.instance.updateItem(item)
  void editItem({required int id, required String name, required String unit}) {
    final item = _items.firstWhere((i) => i.id == id);
    item.name      = name;
    item.unit      = unit;
    item.updatedAt = DateTime.now();
    notifyListeners();
  }

  // Soft delete — item stays in DB, is_deleted = true
  // TODO Phase 2: await DatabaseHelper.instance.softDeleteItem(id)
  void deleteItem(int id) {
    final item = _items.firstWhere((i) => i.id == id);
    item.isDeleted = true;
    item.updatedAt = DateTime.now();
    notifyListeners();
  }

  // Get item by ID (used internally)
  ItemModel? getItemById(int id) {
    try { return _items.firstWhere((i) => i.id == id); }
    catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void addLocation({required String name, required String type}) {
    final now = DateTime.now();
    _locations.add(LocationModel(
      id:        _locationId++,
      name:      name,
      type:      type,
      createdAt: now,
      updatedAt: now,
    ));
    notifyListeners();
  }

  void editLocation({required int id, required String name, required String type}) {
    final loc  = _locations.firstWhere((l) => l.id == id);
    loc.name      = name;
    loc.type      = type;
    loc.updatedAt = DateTime.now();
    notifyListeners();
  }

  void deleteLocation(int id) {
    final loc  = _locations.firstWhere((l) => l.id == id);
    loc.isDeleted = true;
    loc.updatedAt = DateTime.now();
    notifyListeners();
  }

  LocationModel? getLocationById(int id) {
    try { return _locations.firstWhere((l) => l.id == id); }
    catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAFF METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void addStaff({required String name, required String pin}) {
    _staff.add(StaffModel(
      id:        _staffId++,
      name:      name,
      pin:       pin,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void editStaff({required int id, required String name, required String pin}) {
    final s = _staff.firstWhere((s) => s.id == id);
    s.name = name;
    s.pin  = pin;
    notifyListeners();
  }

  void deleteStaff(int id) {
    _staff.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // Login — verifies staff name + PIN
  // Returns true if login successful
  bool login({required int staffId, required String pin}) {
    try {
      final s = _staff.firstWhere((s) => s.id == staffId);
      if (s.pin == pin) {
        _currentStaff = s;
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    _currentStaff = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOVEMENT METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  // Add a new movement — the core action of the app
  // TODO Phase 2: await DatabaseHelper.instance.insertMovement(movement)
  void addMovement({
    required int    itemId,
    required int    fromLocationId,
    required int    toLocationId,
    required double quantity,
    required int    staffId,
    String?         remark,
  }) {
    _movements.insert(0, MovementModel(  // insert at top so newest is first
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
    notifyListeners(); // all screens listening will rebuild automatically
  }

  // Get movements sorted newest first
  List<MovementModel> get sortedMovements {
    final list = List<MovementModel>.from(_movements);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK CALCULATION  (spec section 8: Stock = Incoming - Outgoing)
  // ═══════════════════════════════════════════════════════════════════════════

  // Returns stock balance for every item at every location
  // Only returns entries where balance > 0
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

  // Stock for one specific location
  List<StockBalance> getStockForLocation(int locationId) =>
      getStock().where((s) => s.location.id == locationId).toList();

  // Stock for one specific item across all locations
  List<StockBalance> getStockForItem(int itemId) =>
      getStock().where((s) => s.item.id == itemId).toList();

  // Total stock of one item across all locations
  double totalStockForItem(int itemId) =>
      getStockForItem(itemId).fold(0, (sum, s) => sum + s.balance);

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  int get pendingSyncCount =>
      _movements.where((m) => m.syncStatus == 'pending').length;

  int get syncedCount =>
      _movements.where((m) => m.syncStatus == 'synced').length;

  // Mark all pending as synced (called by sync service in Phase 2)
  void markAllSynced() {
    for (final m in _movements) {
      m.syncStatus = 'synced';
    }
    notifyListeners();
  }
}