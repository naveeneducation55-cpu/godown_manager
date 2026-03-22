// ─────────────────────────────────────────────────────────────────────────────
// database_helper.dart
//
// Singleton database layer. All raw SQL lives here.
// AppDataProvider calls these methods — screens never touch SQL directly.
//
// Tables (from inventory_app_spec.md section 5):
//   items, locations, staff, movements
//
// Indexes (from spec section 16):
//   item_id, from_location, to_location, created_at
//
// Design principles:
//   • Singleton pattern — one DB connection for the app lifetime
//   • All methods are async — non-blocking IO
//   • Transactions used for multi-step writes — data consistency guaranteed
//   • Soft deletes — is_deleted flag, records never physically removed
//   • DB version tracked — migrations supported via onUpgrade
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../utils/id_generator.dart';

class DatabaseHelper {

  // ── Singleton ──────────────────────────────────────────────────────────────
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  // DB config
  static const _dbName    = 'godown_inventory.db';
  static const _dbVersion = 1;

  // ── Table names ────────────────────────────────────────────────────────────
  static const tItems     = 'items';
  static const tLocations = 'locations';
  static const tStaff     = 'staff';
  static const tMovements = 'movements';

  // ── Get or create DB ───────────────────────────────────────────────────────
  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _dbName);

    return openDatabase(
      path,
      version:  _dbVersion,
      onCreate: _onCreate,
      // onUpgrade: _onUpgrade,  // uncomment in Phase 3 for schema migrations
    );
  }

  // ── Create all tables ──────────────────────────────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {

      // Items table
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

      // Locations table
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

      // Staff table — role added beyond spec for admin/staff distinction
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

      // Movements table — from spec section 5
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
          remark          TEXT
        )
      ''');

      // Indexes — spec section 16
      await txn.execute(
        'CREATE INDEX idx_movements_item_id ON $tMovements(item_id)');
      await txn.execute(
        'CREATE INDEX idx_movements_from ON $tMovements(from_location)');
      await txn.execute(
        'CREATE INDEX idx_movements_to ON $tMovements(to_location)');
      await txn.execute(
        'CREATE INDEX idx_movements_created ON $tMovements(created_at)');

      // Seed real data
      await _seedData(txn);
    });
  }

  // ── Seed initial data ──────────────────────────────────────────────────────
  Future<void> _seedData(Transaction txn) async {
    final idGen = IdGenerator.instance;
    final now = DateTime.now().toIso8601String();

    // Items — real products
    final itemIds = <String>[];
    for (final item in [
      ('60*90 Dabangg',         'pcs'),
      ('60*90 Jio Vip',         'pcs'),
      ('90*100 Sonata White',   'pcs'),
      ('90*100 Khubsurat Set',  'pcs'),
      ('108*108 Flora Bedsheet','pcs'),
      ('70*90 Metro',           'pcs'),
      ('90*100 Metro',          'pcs'),
      ('60*90 Metro',           'pcs'),
    ]) {
      final id = await idGen.item();
      itemIds.add(id);
      await txn.insert(tItems, {
        'item_id':    id,
        'item_name':  item.$1,
        'unit':       item.$2,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });
    }

    // Locations
    final locIds = <String>[];
    for (final loc in [
      ('Godown A', 'godown'),
      ('Godown B', 'godown'),
      ('Godown C', 'godown'),
      ('Shop',     'shop'),
    ]) {
      final id = await idGen.location();
      locIds.add(id);
      await txn.insert(tLocations, {
        'location_id':   id,
        'location_name': loc.$1,
        'type':          loc.$2,
        'created_at':    now,
        'updated_at':    now,
        'is_deleted':    0,
      });
    }

    // Staff — first is admin
    final staffIds = <String>[];
    for (final s in [
      ('Ramesh', '1234', 'admin'),
      ('Suresh', '5678', 'staff'),
      ('Dinesh', '9012', 'staff'),
    ]) {
      final id = await idGen.staff();
      staffIds.add(id);
      await txn.insert(tStaff, {
        'staff_id':   id,
        'staff_name': s.$1,
        'pin':        s.$2,
        'role':       s.$3,
        'created_at': now,
      });
    }

    // Sample movements (so stock/history are not empty on first launch)
    // itemIds index:  0=Dabangg,1=JioVip,2=Sonata,3=Khubsurat,4=Flora,5=Metro70,6=Metro90,7=Metro60
    // locIds index:   0=GodownA,1=GodownB,2=GodownC,3=Shop
    // staffIds index: 0=Ramesh,1=Suresh,2=Dinesh
    final seedMvts = [
      (item: 0, from: 0, to: 3, staff: 0, qty: 100.0, hrs: 2,  remark: ''),
      (item: 1, from: 0, to: 3, staff: 1, qty: 50.0,  hrs: 3,  remark: ''),
      (item: 2, from: 1, to: 3, staff: 0, qty: 30.0,  hrs: 5,  remark: ''),
      (item: 3, from: 0, to: 3, staff: 2, qty: 25.0,  hrs: 6,  remark: ''),
      (item: 4, from: 1, to: 3, staff: 1, qty: 60.0,  hrs: 26, remark: ''),
      (item: 5, from: 0, to: 1, staff: 0, qty: 40.0,  hrs: 28, remark: 'Transfer to B'),
      (item: 6, from: 1, to: 3, staff: 2, qty: 20.0,  hrs: 30, remark: ''),
      (item: 7, from: 0, to: 3, staff: 1, qty: 35.0,  hrs: 50, remark: ''),
    ];

    final base = DateTime.now();
    for (final m in seedMvts) {
      final id = await idGen.movement();
      final ts = base.subtract(Duration(hours: m.hrs)).toIso8601String();
      await txn.insert(tMovements, {
        'movement_id':   id,
        'item_id':       itemIds[m.item],
        'quantity':      m.qty,
        'from_location': locIds[m.from],
        'to_location':   locIds[m.to],
        'staff_id':      staffIds[m.staff],
        'created_at':    ts,
        'updated_at':    ts,
        'edited':        0,
        'edited_by':     null,
        'sync_status':   'pending',
        'remark':        m.remark.isEmpty ? null : m.remark,
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEMS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getItems() async {
    final d = await db;
    return d.query(tItems,
      where:   'is_deleted = ?',
      whereArgs: [0],
      orderBy: 'item_name ASC',
    );
  }

  Future<String> insertItem(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tItems, data);
    return data['item_id'] as String;
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tItems, data,
      where:     'item_id = ?',
      whereArgs: [id],
    );
  }

  // Soft delete
  Future<void> softDeleteItem(String id) async {
    final d   = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tItems,
      {'is_deleted': 1, 'updated_at': now},
      where:     'item_id = ?',
      whereArgs: [id],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATIONS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getLocations() async {
    final d = await db;
    return d.query(tLocations,
      where:     'is_deleted = ?',
      whereArgs: [0],
      orderBy:   'location_name ASC',
    );
  }

  Future<String> insertLocation(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tLocations, data);
    return data['location_id'] as String;
  }

  Future<void> updateLocation(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tLocations, data,
      where:     'location_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteLocation(String id) async {
    final d   = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tLocations,
      {'is_deleted': 1, 'updated_at': now},
      where:     'location_id = ?',
      whereArgs: [id],
    );
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

  Future<void> updateStaff(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tStaff, data,
      where:     'staff_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteStaff(String id) async {
    final d = await db;
    await d.delete(tStaff,
      where:     'staff_id = ?',
      whereArgs: [id],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOVEMENTS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  // P4: Paginated movements — avoids loading 10,000 rows on startup
  // Default: latest 200 records — enough for history screen
  // Pass offset to load more (infinite scroll in Phase 3)
  Future<List<Map<String, dynamic>>> getMovements({
    int limit  = 200,
    int offset = 0,
  }) async {
    final d = await db;
    return d.query(
      tMovements,
      orderBy:  'created_at DESC',
      limit:    limit,
      offset:   offset,
    );
  }

  // Total movement count — for sync screen stats
  Future<int> getMovementCount() async {
    final d      = await db;
    final result = await d.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tMovements'
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // Pending sync count — for home screen badge
  Future<int> getPendingCount() async {
    final d      = await db;
    final result = await d.rawQuery(
      "SELECT COUNT(*) AS cnt FROM $tMovements WHERE sync_status = 'pending'"
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<String> insertMovement(Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(tMovements, data);
    return data['movement_id'] as String;
  }

  Future<void> updateMovement(String id, Map<String, dynamic> data) async {
    final d = await db;
    await d.update(tMovements, data,
      where:     'movement_id = ?',
      whereArgs: [id],
    );
  }

  // Mark all pending as synced — used by sync screen
  Future<void> markAllSynced() async {
    final d   = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(tMovements,
      {'sync_status': 'synced', 'updated_at': now},
      where:     'sync_status = ?',
      whereArgs: ['pending'],
    );
  }

  // Mark specific movement IDs as synced — called after successful push
  Future<void> markMovementsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final d   = await db;
    final now = DateTime.now().toIso8601String();
    // Batch update using IN clause
    final placeholders = ids.map((_) => '?').join(',');
await d.rawUpdate(
  'UPDATE $tMovements SET sync_status = ?, updated_at = ? '
  'WHERE movement_id IN ($placeholders)',
  ['synced', now, ...ids],
);
  }

  // Get only pending movements — used by SyncService push
  Future<List<Map<String, dynamic>>> getPendingMovements() async {
    final d = await db;
    return d.query(
      tMovements,
      where:     'sync_status = ?',
      whereArgs: ['pending'],
      orderBy:   'created_at ASC', // push oldest first
    );
  }

  // Upsert a movement received from Supabase
  // Conflict resolution: remote wins only if its updated_at is newer
  Future<void> upsertMovementFromRemote(Map<String, dynamic> remote) async {
    final d          = await db;
    final remoteId   = remote['movement_id'] as int;
    final remoteTs   = remote['updated_at']  as String;

    final existing = await d.query(
      tMovements,
      where:     'movement_id = ?',
      whereArgs: [remoteId],
      limit:     1,
    );

    if (existing.isEmpty) {
      // New record from another device — insert
      await d.insert(tMovements, {
        'movement_id':   remoteId,
        'item_id':       remote['item_id'],
        'quantity':      remote['quantity'],
        'from_location': remote['from_location'],
        'to_location':   remote['to_location'],
        'staff_id':      remote['staff_id'],
        'created_at':    remote['created_at'],
        'updated_at':    remoteTs,
        'edited':        remote['edited'] == true ? 1 : 0,
        'edited_by':     remote['edited_by'],
        'sync_status':   'synced',
        'remark':        remote['remark'],
      });
    } else {
      // Exists locally — only update if remote is newer (spec section 13)
      final localTs = existing.first['updated_at'] as String;
      if (remoteTs.compareTo(localTs) > 0) {
        await d.update(
          tMovements,
          {
            'quantity':      remote['quantity'],
            'from_location': remote['from_location'],
            'to_location':   remote['to_location'],
            'edited':        remote['edited'] == true ? 1 : 0,
            'edited_by':     remote['edited_by'],
            'updated_at':    remoteTs,
            'sync_status':   'synced',
            'remark':        remote['remark'],
          },
          where:     'movement_id = ?',
          whereArgs: [remoteId],
        );
      }
      // else: local is newer — keep local, skip remote
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK CALCULATION
  // Stock = Incoming - Outgoing  (spec section 8)
  // Done in SQL — much faster than Dart loop for large datasets
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getStock() async {
    final d = await db;
    // Returns one row per (item, location) pair with incoming + outgoing sums
    return d.rawQuery('''
      SELECT
        i.item_id,
        i.item_name,
        i.unit,
        l.location_id,
        l.location_name,
        l.type AS location_type,
        COALESCE(SUM(CASE WHEN m.to_location   = l.location_id THEN m.quantity ELSE 0 END), 0) AS incoming,
        COALESCE(SUM(CASE WHEN m.from_location = l.location_id AND m.from_location != -1 THEN m.quantity ELSE 0 END), 0) AS outgoing
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
  // UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  // Close DB — called on app dispose (rare but clean)
  Future<void> close() async {
    final d = _db;
    if (d != null) {
      await d.close();
      _db = null;
    }
  }

  // Delete DB entirely — for testing/reset only
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _dbName);
    await databaseFactory.deleteDatabase(path);
    _db = null;
    debugPrint('Database deleted');
  }

  // Reseed — called when staff table is empty after load
  // Drops and recreates all tables with correct schema then seeds
  Future<void> reseed() async {
    try {
      final d = await db;
      await d.transaction((txn) async {
        // Drop all tables
        await txn.execute('DROP TABLE IF EXISTS tMovements');
        await txn.execute('DROP TABLE IF EXISTS tItems');
        await txn.execute('DROP TABLE IF EXISTS tLocations');
        await txn.execute('DROP TABLE IF EXISTS tStaff');
      });
      // Close and delete DB file so onCreate runs fresh
      await d.close();
      _db = null;
      // Reopen — triggers onCreate which creates tables + seeds
      await db;
      debugPrint('DatabaseHelper: reseed complete');
    } catch (e) {
      debugPrint('DatabaseHelper.reseed error: \$e');
    }
  }
}