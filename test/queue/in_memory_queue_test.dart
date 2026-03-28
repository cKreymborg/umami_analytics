import 'package:flutter_test/flutter_test.dart';
import 'package:umami_analytics/src/queue/in_memory_queue.dart';

void main() {
  late InMemoryQueue queue;

  setUp(() {
    queue = InMemoryQueue(maxSize: 3);
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

    test('assigns unique IDs', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      final events = await queue.getAll();
      expect(events[0].id, isNot(events[1].id));
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

    test('no-op when id does not exist', () async {
      await queue.insert({'n': 1});
      await queue.delete(999);
      expect(await queue.length, 1);
    });
  });

  group('maxSize enforcement', () {
    test('drops oldest events when maxSize exceeded', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      await queue.insert({'n': 3});
      await queue.insert({'n': 4}); // should drop n:1
      expect(await queue.length, 3);
      final events = await queue.getAll();
      expect(events.map((e) => e.payload['n']), [2, 3, 4]);
    });

    test('handles burst exceeding maxSize', () async {
      for (var i = 1; i <= 10; i++) {
        await queue.insert({'n': i});
      }
      expect(await queue.length, 3);
      final events = await queue.getAll();
      expect(events.map((e) => e.payload['n']), [8, 9, 10]);
    });
  });

  group('deleteExpired', () {
    test('removes events older than TTL', () async {
      await queue.insert({'n': 1});
      // Wait to ensure event ages past TTL
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

  group('close', () {
    test('clears all events', () async {
      await queue.insert({'n': 1});
      await queue.insert({'n': 2});
      await queue.close();
      expect(await queue.length, 0);
    });
  });
}
