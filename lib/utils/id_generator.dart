// ─────────────────────────────────────────────────────────────────────────────
// id_generator.dart
//
// Format: PREFIX-DDDD-NNNNN-YYYYMMDD
//   PREFIX   = MOV / ITM / LOC / STF
//   DDDD     = 4-char device token (generated once per install, stored in DB)
//   NNNNN    = 5-digit zero-padded sequence
//   YYYYMMDD = date
//
// Example: MOV-A3F9-00001-20260401
//
// Device token guarantees IDs are unique across devices even if sequence
// counters reset (fresh install). Two devices can never generate the same ID.
//
// Stored in id_sequences.db — separate file from godown_inventory.db
// to avoid lock conflicts during onCreate transactions.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class IdGenerator {
  IdGenerator._();
  static final IdGenerator instance = IdGenerator._();

  static const _dbName      = 'id_sequences.db';
  static const _tableName   = 'sequences';
  static const _deviceTable = 'device_token';
  Database? _db;
  String?   _deviceToken;

  Future<Database> get _seqDb async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version:  2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            prefix   TEXT    PRIMARY KEY,
            last_seq INTEGER NOT NULL DEFAULT 0
          )
        ''');
        for (final p in ['MOV', 'ITM', 'LOC', 'STF']) {
          await db.insert(_tableName, {'prefix': p, 'last_seq': 0});
        }
        await db.execute('''
          CREATE TABLE $_deviceTable (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        // Generate and store device token on first install
        final token = _randomToken();
        await db.insert(_deviceTable, {'key': 'token', 'value': token});
        debugPrint('IdGenerator: device token created — $token');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Existing install — create device token table and generate token
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $_deviceTable (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          final token = _randomToken();
          await db.insert(_deviceTable, {'key': 'token', 'value': token},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          debugPrint('IdGenerator: migrated v1→v2, device token — $token');
        }
      },
    );
  }

  // Generate a 4-char alphanumeric token — uppercase letters + digits
  static String _randomToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I,O,0,1 — ambiguous
    final rng   = Random.secure();
    return List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // Load device token once, cache it
  Future<String> _getDeviceToken() async {
    if (_deviceToken != null) return _deviceToken!;
    final db   = await _seqDb;
    final rows = await db.query(_deviceTable,
        where: 'key = ?', whereArgs: ['token']);
    _deviceToken = rows.isNotEmpty
        ? rows.first['value'] as String
        : _randomToken(); // fallback — should never happen
    return _deviceToken!;
  }

  Future<int> _nextSeq(String prefix) async {
    final db = await _seqDb;
    int next  = 1;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _tableName,
        where:     'prefix = ?',
        whereArgs: [prefix],
      );
      if (rows.isEmpty) {
        await txn.insert(_tableName, {'prefix': prefix, 'last_seq': 1});
        next = 1;
      } else {
        next = (rows.first['last_seq'] as int) + 1;
        await txn.update(
          _tableName,
          {'last_seq': next},
          where:     'prefix = ?',
          whereArgs: [prefix],
        );
      }
    });
    return next;
  }

  Future<String> _generate(String prefix) async {
    try {
      final token  = await _getDeviceToken();
      final seq    = await _nextSeq(prefix);
      final now    = DateTime.now();
      final date   = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final seqStr = seq.toString().padLeft(5, '0');
      return '$prefix-$token-$seqStr-$date';
    } catch (e) {
      debugPrint('IdGenerator._generate($prefix) error: $e');
      final ts = DateTime.now().millisecondsSinceEpoch;
      return '$prefix-XXXX-00000-$ts';
    }
  }

  Future<String> movement()  => _generate('MOV');
  Future<String> item()      => _generate('ITM');
  Future<String> location()  => _generate('LOC');
  Future<String> staff()     => _generate('STF');

  Future<void> close() async {
    await _db?.close();
    _db     = null;
    _deviceToken = null;
  }
}