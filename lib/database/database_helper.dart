// ─────────────────────────────────────────────────────────────────────────────
// database_helper.dart — Checkpoint 3
//
// Checkpoint 3 change (THE fix for duplicate/hardcoded data):
//   • _seedData() call REMOVED from _onCreate()
//   • seedData() renamed public — called by AppDataProvider._seedAndLoad()
//     only when Supabase is confirmed empty (first device ever)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../utils/id_generator.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  static const _dbName = 'godown_inventory.db';
  static const _dbVersion = 3;

  static const tItems     = 'items';
  static const tLocations = 'locations';
  static const tStaff     = 'staff';
  static const tMovements = 'movements';
  static const tSettings  = 'app_settings';

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(path, version: _dbVersion,
        onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  // Creates empty tables only — no seed data
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute('''
          CREATE TABLE $tItems (
            item_id     TEXT    PRIMARY KEY,
            item_name   TEXT    NOT NULL,
            unit        TEXT    NOT NULL,
            created_at  TEXT    NOT NULL,
            updated_at  TEXT    NOT NULL,
            is_deleted  INTEGER NOT NULL DEFAULT 0
          )
        ''');

      await txn.execute('''
          CREATE TABLE $tLocations (
            location_id   TEXT    PRIMARY KEY,
            location_name TEXT    NOT NULL,
            type          TEXT    NOT NULL CHECK(type IN ('godown','shop')),
            created_at    TEXT    NOT NULL,
            updated_at    TEXT    NOT NULL,
            is_deleted    INTEGER NOT NULL DEFAULT 0
          )
        ''');

      await txn.execute('''
          CREATE TABLE $tStaff (
            staff_id    TEXT    PRIMARY KEY,
            staff_name  TEXT    NOT NULL,
            pin         TEXT    NOT NULL,
            role        TEXT    NOT NULL DEFAULT 'staff'
                                CHECK(role IN ('admin','staff')),
            created_at  TEXT    NOT NULL
          )
        ''');

      await txn.execute('''
          CREATE TABLE $tMovements (
            movement_id     TEXT    PRIMARY KEY,
            item_id         TEXT    NOT NULL,
            quantity        REAL    NOT NULL CHECK(quantity > 0),
            from_location   TEXT    NOT NULL,
            to_location     TEXT    NOT NULL,
            staff_id        TEXT    NOT NULL,
            created_at      TEXT    NOT NULL,
            updated_at      TEXT    NOT NULL,
            edited          INTEGER NOT NULL DEFAULT 0,
            edited_by       TEXT,
            sync_status     TEXT    NOT NULL DEFAULT 'pending'
                                    CHECK(sync_status IN ('pending','synced')),
            remark          TEXT,
            is_deleted      INTEGER NOT NULL DEFAULT 0
          )
        ''');


      await txn.execute(
          'CREATE INDEX idx_movements_item_id ON $tMovements(item_id)');
      await txn.execute(
          'CREATE INDEX idx_movements_from ON $tMovements(from_location)');
      await txn.execute(
          'CREATE INDEX idx_movements_to ON $tMovements(to_location)');
      await txn.execute(
          'CREATE INDEX idx_movements_created ON $tMovements(created_at)');
      await txn.execute('''
          CREATE TABLE $tSettings (
            key    TEXT PRIMARY KEY,
            value  TEXT
          )
        ''');
    });

    debugPrint('DatabaseHelper: tables created — empty, no seed');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $tMovements ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
      debugPrint('DatabaseHelper: migrated v1→v2 — is_deleted added to movements');
    }
    if (oldVersion < 3) {
      await db.execute('''
          CREATE TABLE IF NOT EXISTS $tSettings (
            key    TEXT PRIMARY KEY,
            value  TEXT
          )
        ''');
      debugPrint('DatabaseHelper: migrated v2→v3 — app_settings table created');
    }
  }

  
  // Public seed — called ONLY when Supabase is confirmed empty (first device ever)
  Future<void> seedData() async {
    final d = await db;
    final idGen = IdGenerator.instance;
    final now = DateTime.now().toIso8601String();

    debugPrint('DatabaseHelper: seeding initial data...');

    final itemIds = <String>[];
    for (final item in [
      ('60*90 Dabangg', 'pcs'),
      ('60*90 Jio Vip', 'pcs'),
      ('90*100 Sonata White', 'pcs'),
      ('90*100 Khubsurat Set', 'pcs'),
      ('108*108 Flora Bedsheet', 'pcs'),
      ('70*90 Metro', 'pcs'),
      ('90*100 Metro', 'pcs'),
      ('60*90 Metro', 'pcs'),
    ]) {
      final id = await idGen.item();
      itemIds.add(id);
      await d.insert(tItems, {
        'item_id': id,
        'item_name': item.$1,
        'unit': item.$2,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });
    }

    final locIds = <String>[];
    for (final loc in [
      ('Godown A', 'godown'),
      ('Godown B', 'godown'),
      ('Godown C', 'godown'),
      ('Shop', 'shop'),
    ]) {
      final id = await idGen.location();
      locIds.add(id);
      await d.insert(tLocations, {
        'location_id': id,
        'location_name': loc.$1,
        'type': loc.$2,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });
    }

    final staffIds = <String>[];
    for (final s in [
      ('Ramesh', '1234', 'admin'),
      ('Suresh', '5678', 'staff'),
      ('Dinesh', '9012', 'staff'),
    ]) {
      final id = await idGen.staff();
      staffIds.add(id);
      await d.insert(tStaff, {
        'staff_id': id,
        'staff_name': s.$1,
        'pin': s.$2,
        'role': s.$3,
        'created_at': now,
      });
    }

    final seedMvts = [
      (item: 0, from: 0, to: 3, staff: 0, qty: 100.0, hrs: 2, remark: ''),
      (item: 1, from: 0, to: 3, staff: 1, qty: 50.0, hrs: 3, remark: ''),
      (item: 2, from: 1, to: 3, staff: 0, qty: 30.0, hrs: 5, remark: ''),
      (item: 3, from: 0, to: 3, staff: 2, qty: 25.0, hrs: 6, remark: ''),
      (item: 4, from: 1, to: 3, staff: 1, qty: 60.0, hrs: 26, remark: ''),
      (
        item: 5,
        from: 0,
        to: 1,
        staff: 0,
        qty: 40.0,
        hrs: 28,
        remark: 'Transfer to B'
      ),
      (item: 6, from: 1, to: 3, staff: 2, qty: 20.0, hrs: 30, remark: ''),
      (item: 7, from: 0, to: 3, staff: 1, qty: 35.0, hrs: 50, remark: ''),
    ];

    final base = DateTime.now();
    for (final m in seedMvts) {
      final id = await idGen.movement();
      final ts = base.subtract(Duration(hours: m.hrs)).toIso8601String();
      await d.insert(tMovements, {
        'movement_id': id,
        'item_id': itemIds[m.item],
        'quantity': m.qty,
        'from_location': locIds[m.from],
        'to_location': locIds[m.to],
        'staff_id': staffIds[m.staff],
        'created_at': ts,
        'updated_at': ts,
        'edited': 0,
        'edited_by': null,
        'sync_status': 'synced',
        'remark': m.remark.isEmpty ? null : m.remark,
      });
    }

    debugPrint('DatabaseHelper: seed complete — '
        'items:${itemIds.length} locations:${locIds.length} '
        'staff:${staffIds.length} movements:${seedMvts.length}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEMS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getItems() async {
    final d = await db;
    return d.query(tItems,
        where: 'is_deleted = ?', whereArgs: [0], orderBy: 'item_name ASC');
  }

  Future<List<Map<String, dynamic>>> getAllItems() async {
    final d = await db;
    return d.query(tItems, orderBy: 'item_name ASC');
  }

  Future<String> insertItem(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tItems, data);
    return data['item_id'] as String;
  }

  Future<void> upsertItemFromRemote(Map<String, dynamic> remote) async {
    final d = await db;
    await d.insert(
        tItems,
        {
          'item_id': remote['item_id']?.toString(),
          'item_name': remote['item_name']?.toString(),
          'unit': remote['unit']?.toString(),
          'created_at': remote['created_at']?.toString(),
          'updated_at': remote['updated_at']?.toString(),
          'is_deleted':
              (remote['is_deleted'] == true || remote['is_deleted'] == 1)
                  ? 1
                  : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tItems, data, where: 'item_id = ?', whereArgs: [id]);
  }

  Future<void> softDeleteItem(String id) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tItems, {'is_deleted': 1, 'updated_at': now},
        where: 'item_id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATIONS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getLocations() async {
    final d = await db;
    return d.query(tLocations,
        where: 'is_deleted = ?', whereArgs: [0], orderBy: 'location_name ASC');
  }

  Future<List<Map<String, dynamic>>> getAllLocations() async {
    final d = await db;
    return d.query(tLocations, orderBy: 'location_name ASC');
  }

  Future<String> insertLocation(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tLocations, data);
    return data['location_id'] as String;
  }

  Future<void> upsertLocationFromRemote(Map<String, dynamic> remote) async {
    final d = await db;
    await d.insert(
        tLocations,
        {
          'location_id': remote['location_id']?.toString(),
          'location_name': remote['location_name']?.toString(),
          'type': remote['type']?.toString(),
          'created_at': remote['created_at']?.toString(),
          'updated_at': remote['updated_at']?.toString(),
          'is_deleted':
              (remote['is_deleted'] == true || remote['is_deleted'] == 1)
                  ? 1
                  : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateLocation(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tLocations, data, where: 'location_id = ?', whereArgs: [id]);
  }

  Future<void> softDeleteLocation(String id) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tLocations, {'is_deleted': 1, 'updated_at': now},
        where: 'location_id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAFF CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getStaff() async {
    final d = await db;
    return d.query(tStaff, orderBy: 'staff_name ASC');
  }

  Future<String> insertStaff(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tStaff, data);
    return data['staff_id'] as String;
  }

  Future<void> upsertStaffFromRemote(Map<String, dynamic> remote) async {
    final d = await db;
    await d.insert(
        tStaff,
        {
          'staff_id': remote['staff_id']?.toString(),
          'staff_name': remote['staff_name']?.toString(),
          'pin': remote['pin']?.toString(),
          'role': remote['role']?.toString() ?? 'staff',
          'created_at': remote['created_at']?.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateStaff(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tStaff, data, where: 'staff_id = ?', whereArgs: [id]);
  }

  Future<void> deleteStaff(String id) async {
    final d = await db;
    await d.delete(tStaff, where: 'staff_id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOVEMENTS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getMovements(
      {int limit = 200, int offset = 0}) async {
    final d = await db;
    return d.query(tMovements,
        where:     'is_deleted = ?',
        whereArgs: [0],
        orderBy:   'created_at DESC',
        limit:     limit,
        offset:    offset);
  }

  Future<int> getMovementCount() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) AS cnt FROM $tMovements');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<int> getPendingCount() async {
    final d = await db;
    final result = await d.rawQuery(
        "SELECT COUNT(*) AS cnt FROM $tMovements WHERE sync_status = 'pending'");
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<String> insertMovement(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tMovements, data);
    return data['movement_id'] as String;
  }

  Future<void> updateMovement(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tMovements, data, where: 'movement_id = ?', whereArgs: [id]);
  }

  Future<void> markAllSynced() async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tMovements, {'sync_status': 'synced', 'updated_at': now},
        where: 'sync_status = ?', whereArgs: ['pending']);
  }

  Future<void> markMovementsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    final now = DateTime.now().toIso8601String();
    final placeholders = ids.map((_) => '?').join(',');
    await d.rawUpdate(
      'UPDATE $tMovements SET sync_status = ?, updated_at = ? '
      'WHERE movement_id IN ($placeholders)',
      ['synced', now, ...ids],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingMovements() async {
    final d = await db;
    return d.query(tMovements,
        where:     'sync_status = ? AND is_deleted = ?',
        whereArgs: ['pending', 0],
        orderBy:   'created_at ASC');
  }

  // Includes soft-deleted pending — needed for sync push so deletions reach Supabase
  Future<List<Map<String, dynamic>>> getPendingMovementsAll() async {
    final d = await db;
    return d.query(tMovements,
        where:     'sync_status = ?',
        whereArgs: ['pending'],
        orderBy:   'created_at ASC');
  }

  Future<void> softDeleteMovement(String id, {String? deletedBy}) async {
    final d   = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tMovements, {
      'is_deleted':  1,
      'edited_by':   deletedBy,
      'updated_at':  now,
      'sync_status': 'pending',
    }, where: 'movement_id = ?', whereArgs: [id]);
  }

  Future<bool> upsertMovementFromRemote(Map<String, dynamic> remote) async {
    final d = await db;
    final remoteId = remote['movement_id'].toString();
    final remoteTs = remote['updated_at']?.toString() ?? '';

    final existing = await d.query(tMovements,
        where: 'movement_id = ?', whereArgs: [remoteId], limit: 1);

    if (existing.isEmpty) {
      await d.insert(tMovements, {
        'movement_id':   remoteId,
        'item_id':       remote['item_id']?.toString(),
        'quantity':      remote['quantity'],
        'from_location': remote['from_location']?.toString(),
        'to_location':   remote['to_location']?.toString(),
        'staff_id':      remote['staff_id']?.toString(),
        'created_at':    remote['created_at']?.toString(),
        'updated_at':    remoteTs,
        'edited':        remote['edited'] == true ? 1 : 0,
        'edited_by':     remote['edited_by']?.toString(),
        'sync_status':   'synced',
        'remark':        remote['remark'],
        'is_deleted':    (remote['is_deleted'] == true || remote['is_deleted'] == 1) ? 1 : 0,
      });
      return true;
    } else {
      final localTs         = existing.first['updated_at'] as String;
      final localSyncStatus = existing.first['sync_status'] as String;
      if (remoteTs.compareTo(localTs) > 0) {
        // Remote is newer — accept, mark synced
        await d.update(tMovements, {
          'quantity':      remote['quantity'],
          'from_location': remote['from_location']?.toString(),
          'to_location':   remote['to_location']?.toString(),
          'edited':        remote['edited'] == true ? 1 : 0,
          'edited_by':     remote['edited_by']?.toString(),
          'updated_at':    remoteTs,
          'sync_status':   'synced',
          'remark':        remote['remark'],
          'is_deleted':    (remote['is_deleted'] == true || remote['is_deleted'] == 1) ? 1 : 0,
        }, where: 'movement_id = ?', whereArgs: [remoteId]);
        return true;
      }
      // Local is newer — keep local, preserve pending so it gets pushed to Supabase
      if (localSyncStatus == 'pending') {
        debugPrint('DatabaseHelper: local newer than remote — keeping pending for push');
      }
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getStock() async {
    final d = await db;
    return d.rawQuery('''
        SELECT
          i.item_id, i.item_name, i.unit,
          l.location_id, l.location_name, l.type AS location_type,
          COALESCE(SUM(CASE WHEN m.to_location   = l.location_id THEN m.quantity ELSE 0 END), 0) AS incoming,
          COALESCE(SUM(CASE WHEN m.from_location = l.location_id AND m.from_location != 'SUPPLIER' THEN m.quantity ELSE 0 END), 0) AS outgoing
        FROM $tItems i
        CROSS JOIN $tLocations l
        LEFT JOIN $tMovements m ON m.item_id = i.item_id
        WHERE i.is_deleted = 0 AND l.is_deleted = 0
        GROUP BY i.item_id, l.location_id
        HAVING incoming > 0 OR outgoing > 0
        ORDER BY l.location_name, i.item_name
      ''');
  }


 // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<DateTime?> getLastSyncAt() async {
    try {
      final d   = await db;
      final res = await d.query(
        tSettings,
        where:     'key = ?',
        whereArgs: ['last_sync_at'],
      );
      if (res.isEmpty) return null;
      final val = res.first['value'] as String?;
      if (val == null || val.isEmpty) return null;
      return DateTime.tryParse(val);
    } catch (e) {
      debugPrint('DatabaseHelper.getLastSyncAt error: $e');
      return null;
    }
  }

  Future<void> saveLastSyncAt(DateTime dt) async {
    try {
      final d = await db;
      await d.insert(
        tSettings,
        {'key': 'last_sync_at', 'value': dt.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('DatabaseHelper.saveLastSyncAt error: $e');
    }
  }




  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> close() async {
    final d = _db;
    if (d != null) {
      await d.close();
      _db = null;
    }
  }

  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    await databaseFactory.deleteDatabase(path);
    _db = null;
    debugPrint('Database deleted');
  }

  Future<void> reseed() async {
    try {
      final d = await db;
      await d.transaction((txn) async {
        await txn.execute('DROP TABLE IF EXISTS $tMovements');
        await txn.execute('DROP TABLE IF EXISTS $tItems');
        await txn.execute('DROP TABLE IF EXISTS $tLocations');
        await txn.execute('DROP TABLE IF EXISTS $tStaff');
      });
      await d.close();
      _db = null;
      await db;
      debugPrint('DatabaseHelper: reseed complete (tables empty)');
    } catch (e) {
      debugPrint('DatabaseHelper.reseed error: $e');
    }
  }
}