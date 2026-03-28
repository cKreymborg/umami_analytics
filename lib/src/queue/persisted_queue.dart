import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'umami_queue.dart';

/// SQLite-backed event queue. Events survive app restarts.
class PersistedQueue implements UmamiQueue {
  /// Maximum number of events to keep in the queue.
  final int maxSize;
  final Database _db;

  PersistedQueue._(this._db, {required this.maxSize});

  /// Open (or create) the queue database.
  ///
  /// Pass `:memory:` as [databasePath] for testing with an in-memory database.
  /// When [databasePath] is null, defaults to `getDatabasesPath()/umami_queue.db`.
  static Future<PersistedQueue> open({
    required int maxSize,
    String? databasePath,
  }) async {
    final path =
        databasePath ?? p.join(await getDatabasesPath(), 'umami_queue.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE event_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return PersistedQueue._(db, maxSize: maxSize);
  }

  @override
  Future<void> insert(Map<String, dynamic> payload) async {
    await _db.insert('event_queue', {
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _enforceMaxSize();
  }

  Future<void> _enforceMaxSize() async {
    final count = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM event_queue'),
        ) ??
        0;
    if (count > maxSize) {
      await _db.rawDelete(
        '''DELETE FROM event_queue WHERE id IN (
          SELECT id FROM event_queue ORDER BY id ASC LIMIT ?
        )''',
        [count - maxSize],
      );
    }
  }

  @override
  Future<List<QueuedEvent>> getAll() async {
    final rows = await _db.query('event_queue', orderBy: 'id ASC');
    return rows
        .map((row) => QueuedEvent(
              id: row['id'] as int,
              payload:
                  jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
            ))
        .toList();
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('event_queue', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteExpired(Duration ttl) async {
    final cutoffMs = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    await _db
        .delete('event_queue', where: 'created_at < ?', whereArgs: [cutoffMs]);
  }

  @override
  Future<int> get length async =>
      Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM event_queue')) ??
      0;

  @override
  Future<void> close() async {
    await _db.close();
  }
}
