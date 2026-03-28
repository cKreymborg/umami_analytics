import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:umami_analytics/src/queue/persisted_queue.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late PersistedQueue queue;

  setUp(() async {
    queue = await PersistedQueue.open(maxSize: 3, databasePath: ':memory:');
  });

  tearDown(() async {
    await queue.close();
  });

  group('insert', () {
    test('adds event to queue', () async {
      await queue.insert({'key': 'value'});
      expect(await queue.length, 1);
    });

    test('stores payload correctly', () async {
      await queue.insert({'name': 'test_event'});
      final events = await queue.getAll();
      expect(events.first.payload, {'name': 'test_event'});
    });

    test('assigns unique auto-increment IDs', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      final events = await queue.getAll();
      expect(events[1].id, greaterThan(events[0].id));
    });
  });

  group('getAll', () {
    test('returns events in FIFO order', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      await queue.insert({'n': 3});
      final events = await queue.getAll();
      expect(events.map((e) => e.payload['n']), [1, 2, 3]);
    });

    test('returns empty list when queue is empty', () async {
      final events = await queue.getAll();
      expect(events, isEmpty);
    });
  });

  group('delete', () {
    test('removes specific event by id', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      final events = await queue.getAll();
      await queue.delete(events[0].id);
      expect(await queue.length, 1);
      final remaining = await queue.getAll();
      expect(remaining[0].payload['n'], 2);
    });
  });

  group('maxSize enforcement', () {
    test('drops oldest events when maxSize exceeded', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      await queue.insert({'n': 3});
      await queue.insert({'n': 4});
      expect(await queue.length, 3);
      final events = await queue.getAll();
      expect(events.map((e) => e.payload['n']), [2, 3, 4]);
    });
  });

  group('deleteExpired', () {
    test('removes events older than TTL', () async {
      await queue.insert({'n': 1});
      await Future.delayed(const Duration(milliseconds: 20));
      await queue.deleteExpired(const Duration(milliseconds: 5));
      expect(await queue.length, 0);
    });

    test('keeps events newer than TTL', () async {
      await queue.insert({'n': 1});
      await queue.deleteExpired(const Duration(hours: 1));
      expect(await queue.length, 1);
    });
  });

  group('persistence', () {
    test('events survive queue reopen with same database', () async {
      // Use a file-based temp DB for this test
      final tempPath = '${DateTime.now().millisecondsSinceEpoch}_test.db';
      try {
        var q = await PersistedQueue.open(maxSize: 10, databasePath: tempPath);
        await q.insert({'persisted': true});
        await q.close();

        q = await PersistedQueue.open(maxSize: 10, databasePath: tempPath);
        final events = await q.getAll();
        expect(events, hasLength(1));
        expect(events.first.payload['persisted'], true);
        await q.close();
      } finally {
        // Clean up the temp database file
        final file = File(tempPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  });
}
