// ─────────────────────────────────────────────────────────────────────────────
// id_generator.dart
//
// Format: PREFIX-NNNNN-YYYYMMDD
//   PREFIX   = MOV / ITM / LOC / STF
//   NNNNN    = 5-digit zero-padded sequence
//   YYYYMMDD = date
//
// Example: MOV-00001-20260322
//
// Stored in id_sequences.db — separate file from godown_inventory.db
// to avoid lock conflicts during onCreate transactions.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class IdGenerator {
  IdGenerator._();
  static final IdGenerator instance = IdGenerator._();

  static const _dbName    = 'id_sequences.db';
  static const _tableName = 'sequences';
  Database? _db;

  Future<Database> get _seqDb async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version:  1,
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
      },
    );
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
      final seq = await _nextSeq(prefix);
      final now = DateTime.now();
      final date = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final seqStr = seq.toString().padLeft(5, '0');
      return '$prefix-$seqStr-$date';
    } catch (e) {
      debugPrint('IdGenerator._generate($prefix) error: $e');
      final ts = DateTime.now().millisecondsSinceEpoch;
      return '$prefix-00000-$ts';
    }
  }

  Future<String> movement()  => _generate('MOV');
  Future<String> item()      => _generate('ITM');
  Future<String> location()  => _generate('LOC');
  Future<String> staff()     => _generate('STF');

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}