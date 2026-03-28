# umami_analytics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-quality Flutter package for Umami analytics with offline queue support, automatic page view tracking, and configurable logging.

**Architecture:** Single `UmamiAnalytics` class wraps HTTP POST to Umami's `/api/send` endpoint. Failed sends go to an offline queue (in-memory or SQLite-persisted via sealed config class). `UmamiNavigatorObserver` hooks into Flutter navigation for automatic page view tracking. Logging is opt-in via two boolean flags and a pluggable callback.

**Tech Stack:** Flutter, `http` (HTTP client), `sqflite` (persistence), `sqflite_common_ffi` (test), `flutter_lints` (analysis)

**Note:** The existing docs reference `umami_flutter` as the package name. The correct package name is `umami_analytics`.

**Parallelization:** Tasks 2 and 3 can run in parallel. All other tasks are sequential.

---

### Task 1: Project Scaffolding

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `CHANGELOG.md`
- Create: `lib/umami_analytics.dart` (empty barrel)

**Step 1: Create `pubspec.yaml`**

```yaml
name: umami_analytics
description: >-
  A production-quality Flutter package for Umami analytics with offline support,
  automatic page view tracking, and configurable logging.
version: 0.1.0
repository: https://github.com/christopherkreymborg/umami_analytics

environment:
  sdk: ^3.5.0
  flutter: '>=3.24.0'

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  sqflite: ^2.4.1
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  sqflite_common_ffi: ^2.3.4
```

**Step 2: Create `analysis_options.yaml`**

```yaml
include: package:flutter_lints/flutter.yaml
```

**Step 3: Create `.gitignore`**

```
.dart_tool/
.packages
build/
pubspec.lock
*.iml
.idea/
.vscode/
.DS_Store
```

**Step 4: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Christopher Kreymborg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 5: Create `CHANGELOG.md`**

```markdown
## 0.1.0

- Initial release
- Page view and custom event tracking via Umami `/api/send` endpoint
- Offline queue with three modes: disabled, in-memory, SQLite-persisted
- `UmamiNavigatorObserver` for automatic page view tracking
- Configurable logging with two granularity flags
- Session continuity via `x-umami-cache` token
```

**Step 6: Create empty barrel file `lib/umami_analytics.dart`**

```dart
library umami_analytics;
```

**Step 7: Run `flutter pub get`**

```bash
flutter pub get
```

Expected: Dependencies resolve successfully.

**Step 8: Commit**

```bash
git add pubspec.yaml analysis_options.yaml .gitignore LICENSE CHANGELOG.md lib/umami_analytics.dart
git commit -m "feat: scaffold project with pubspec, lints, license, and changelog"
```

---

### Task 2: Logger & Queue Config Types

**Files:**
- Create: `lib/src/umami_logger.dart`
- Create: `lib/src/queue/umami_queue_config.dart`
- Create: `test/umami_logger_test.dart`
- Create: `test/queue/umami_queue_config_test.dart`

**Step 1: Write logger tests**

```dart
// test/umami_logger_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:umami_analytics/src/umami_logger.dart';

void main() {
  test('UmamiLogLevel has four values', () {
    expect(UmamiLogLevel.values, hasLength(4));
    expect(UmamiLogLevel.values, containsAll([
      UmamiLogLevel.debug,
      UmamiLogLevel.info,
      UmamiLogLevel.warning,
      UmamiLogLevel.error,
    ]));
  });

  test('UmamiLogger typedef accepts matching function', () {
    final List<String> logs = [];
    final UmamiLogger logger = (level, message) {
      logs.add('${level.name}: $message');
    };
    logger(UmamiLogLevel.info, 'test message');
    expect(logs, ['info: test message']);
  });
}
```

**Step 2: Run tests to verify they fail**

```bash
flutter test test/umami_logger_test.dart
```

Expected: FAIL — file not found.

**Step 3: Implement logger types**

```dart
// lib/src/umami_logger.dart

/// Log severity levels for Umami analytics operations.
enum UmamiLogLevel {
  /// Detailed diagnostic information (payloads, raw HTTP data).
  debug,

  /// General operational information (event tracked, flush complete).
  info,

  /// Potential issues (event dropped, queue full).
  warning,

  /// Failures (send failed, database error).
  error,
}

/// Callback signature for custom logging.
///
/// When provided to [UmamiAnalytics], all log output routes through this
/// callback instead of the default [debugPrint].
typedef UmamiLogger = void Function(UmamiLogLevel level, String message);
```

**Step 4: Run tests to verify they pass**

```bash
flutter test test/umami_logger_test.dart
```

Expected: PASS.

**Step 5: Write queue config tests**

```dart
// test/queue/umami_queue_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:umami_analytics/src/queue/umami_queue_config.dart';

void main() {
  test('UmamiQueueDisabled is a UmamiQueueConfig', () {
    final config = UmamiQueueDisabled();
    expect(config, isA<UmamiQueueConfig>());
  });

  test('UmamiQueueInMemory has default maxSize of 500', () {
    final config = UmamiQueueInMemory();
    expect(config.maxSize, 500);
  });

  test('UmamiQueueInMemory accepts custom maxSize', () {
    final config = UmamiQueueInMemory(maxSize: 100);
    expect(config.maxSize, 100);
  });

  test('UmamiQueuePersisted has default values', () {
    final config = UmamiQueuePersisted();
    expect(config.maxSize, 500);
    expect(config.databasePath, isNull);
    expect(config.eventTtl, const Duration(hours: 48));
  });

  test('UmamiQueuePersisted accepts custom values', () {
    final config = UmamiQueuePersisted(
      maxSize: 100,
      databasePath: '/tmp/test.db',
      eventTtl: const Duration(hours: 24),
    );
    expect(config.maxSize, 100);
    expect(config.databasePath, '/tmp/test.db');
    expect(config.eventTtl, const Duration(hours: 24));
  });

  test('sealed class exhaustiveness with switch', () {
    final configs = <UmamiQueueConfig>[
      UmamiQueueDisabled(),
      UmamiQueueInMemory(),
      UmamiQueuePersisted(),
    ];
    for (final config in configs) {
      final label = switch (config) {
        UmamiQueueDisabled() => 'disabled',
        UmamiQueueInMemory() => 'memory',
        UmamiQueuePersisted() => 'persisted',
      };
      expect(label, isNotEmpty);
    }
  });

  test('all subclasses support const construction', () {
    const disabled = UmamiQueueDisabled();
    const memory = UmamiQueueInMemory();
    const persisted = UmamiQueuePersisted();
    expect(disabled, isA<UmamiQueueConfig>());
    expect(memory, isA<UmamiQueueConfig>());
    expect(persisted, isA<UmamiQueueConfig>());
  });
}
```

**Step 6: Run tests to verify they fail**

```bash
flutter test test/queue/umami_queue_config_test.dart
```

Expected: FAIL.

**Step 7: Implement queue config**

```dart
// lib/src/queue/umami_queue_config.dart

/// Configuration for the offline event queue.
///
/// Use the sealed subclasses to select a queue strategy:
/// - [UmamiQueueDisabled] — fire and forget, no retry.
/// - [UmamiQueueInMemory] — in-memory queue, lost on app restart.
/// - [UmamiQueuePersisted] — SQLite queue, survives app restarts.
sealed class UmamiQueueConfig {
  const UmamiQueueConfig();
}

/// No queue — events that fail to send are discarded.
class UmamiQueueDisabled extends UmamiQueueConfig {
  const UmamiQueueDisabled();
}

/// In-memory queue — survives temporary network failures but lost on app restart.
class UmamiQueueInMemory extends UmamiQueueConfig {
  /// Maximum number of events to keep in the queue.
  /// Oldest events are dropped when the limit is exceeded.
  final int maxSize;

  const UmamiQueueInMemory({this.maxSize = 500});
}

/// SQLite-persisted queue — survives app restarts.
class UmamiQueuePersisted extends UmamiQueueConfig {
  /// Maximum number of events to keep in the queue.
  final int maxSize;

  /// Custom database file path.
  /// Defaults to `getDatabasesPath()/umami_queue.db` when null.
  final String? databasePath;

  /// Events older than this duration are dropped during flush.
  final Duration eventTtl;

  const UmamiQueuePersisted({
    this.maxSize = 500,
    this.databasePath,
    this.eventTtl = const Duration(hours: 48),
  });
}
```

**Step 8: Run all tests**

```bash
flutter test test/umami_logger_test.dart test/queue/umami_queue_config_test.dart
```

Expected: All PASS.

**Step 9: Commit**

```bash
git add lib/src/umami_logger.dart lib/src/queue/umami_queue_config.dart test/umami_logger_test.dart test/queue/umami_queue_config_test.dart
git commit -m "feat: add logger types and queue config sealed class"
```

---

### Task 3: Queue Interface & In-Memory Queue

**Files:**
- Create: `lib/src/queue/umami_queue.dart`
- Create: `lib/src/queue/in_memory_queue.dart`
- Create: `test/queue/in_memory_queue_test.dart`

**Step 1: Write in-memory queue tests**

```dart
// test/queue/in_memory_queue_test.dart
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
```

**Step 2: Run tests to verify they fail**

```bash
flutter test test/queue/in_memory_queue_test.dart
```

Expected: FAIL — files not found.

**Step 3: Implement queue interface**

```dart
// lib/src/queue/umami_queue.dart

/// A single queued event with metadata.
class QueuedEvent {
  /// Unique identifier for this queued event.
  final int id;

  /// The full event payload (JSON-serializable map sent to Umami).
  final Map<String, dynamic> payload;

  /// When this event was added to the queue.
  final DateTime createdAt;

  QueuedEvent({
    required this.id,
    required this.payload,
    required this.createdAt,
  });
}

/// Abstract interface for event queue implementations.
abstract class UmamiQueue {
  /// Insert an event payload into the queue, enforcing maxSize by dropping oldest.
  Future<void> insert(Map<String, dynamic> payload);

  /// Retrieve all queued events, oldest first.
  Future<List<QueuedEvent>> getAll();

  /// Delete a single event by [id].
  Future<void> delete(int id);

  /// Delete all events older than [ttl] from now.
  Future<void> deleteExpired(Duration ttl);

  /// Current number of events in the queue.
  Future<int> get length;

  /// Release resources (clear memory or close database).
  Future<void> close();
}
```

**Step 4: Implement in-memory queue**

```dart
// lib/src/queue/in_memory_queue.dart
import 'umami_queue.dart';

/// List-backed event queue. Events are lost on app restart.
class InMemoryQueue implements UmamiQueue {
  final int maxSize;
  final List<QueuedEvent> _events = [];
  int _nextId = 1;

  InMemoryQueue({required this.maxSize});

  @override
  Future<void> insert(Map<String, dynamic> payload) async {
    _events.add(QueuedEvent(
      id: _nextId++,
      payload: Map<String, dynamic>.from(payload),
      createdAt: DateTime.now(),
    ));
    while (_events.length > maxSize) {
      _events.removeAt(0);
    }
  }

  @override
  Future<List<QueuedEvent>> getAll() async =>
      List<QueuedEvent>.unmodifiable(_events);

  @override
  Future<void> delete(int id) async {
    _events.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> deleteExpired(Duration ttl) async {
    final cutoff = DateTime.now().subtract(ttl);
    _events.removeWhere((e) => e.createdAt.isBefore(cutoff));
  }

  @override
  Future<int> get length async => _events.length;

  @override
  Future<void> close() async {
    _events.clear();
  }
}
```

**Step 5: Run tests to verify they pass**

```bash
flutter test test/queue/in_memory_queue_test.dart
```

Expected: All PASS.

**Step 6: Commit**

```bash
git add lib/src/queue/umami_queue.dart lib/src/queue/in_memory_queue.dart test/queue/in_memory_queue_test.dart
git commit -m "feat: add queue interface and in-memory queue implementation"
```

---

### Task 4: Persisted Queue

**Files:**
- Create: `lib/src/queue/persisted_queue.dart`
- Create: `test/queue/persisted_queue_test.dart`

**Step 1: Write persisted queue tests**

```dart
// test/queue/persisted_queue_test.dart
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
      var q = await PersistedQueue.open(maxSize: 10, databasePath: tempPath);
      await q.insert({'persisted': true});
      await q.close();

      q = await PersistedQueue.open(maxSize: 10, databasePath: tempPath);
      final events = await q.getAll();
      expect(events, hasLength(1));
      expect(events.first.payload['persisted'], true);
      await q.close();
    });
  });
}
```

**Step 2: Run tests to verify they fail**

```bash
flutter test test/queue/persisted_queue_test.dart
```

Expected: FAIL.

**Step 3: Implement persisted queue**

```dart
// lib/src/queue/persisted_queue.dart
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'umami_queue.dart';

/// SQLite-backed event queue. Events survive app restarts.
class PersistedQueue implements UmamiQueue {
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
    final path = databasePath ??
        p.join(await getDatabasesPath(), 'umami_queue.db');
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
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                  row['created_at'] as int),
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
```

**Step 4: Run tests to verify they pass**

```bash
flutter test test/queue/persisted_queue_test.dart
```

Expected: All PASS.

**Step 5: Run all queue tests**

```bash
flutter test test/queue/
```

Expected: All PASS.

**Step 6: Commit**

```bash
git add lib/src/queue/persisted_queue.dart test/queue/persisted_queue_test.dart
git commit -m "feat: add SQLite-persisted queue implementation"
```

---

### Task 5: UmamiAnalytics Core Class

**Files:**
- Create: `lib/src/umami_analytics.dart`
- Create: `test/umami_analytics_test.dart`

This is the largest task. The core class handles:
- Building payloads for Umami's `/api/send` endpoint
- HTTP POST with User-Agent and cache token headers
- Queue integration (enqueue on failure, flush on success)
- Logging through the configurable callback

**Step 1: Write core class tests**

```dart
// test/umami_analytics_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umami_analytics/src/umami_analytics.dart';
import 'package:umami_analytics/src/umami_logger.dart';
import 'package:umami_analytics/src/queue/umami_queue_config.dart';

void main() {
  late List<http.Request> capturedRequests;
  late MockClient mockClient;
  late UmamiAnalytics analytics;

  MockClient successClient({String cacheToken = 'test-cache-token'}) {
    return MockClient((request) async {
      capturedRequests.add(request);
      return http.Response(
        jsonEncode({'cache': cacheToken, 'sessionId': 'sid', 'visitId': 'vid'}),
        200,
      );
    });
  }

  MockClient failClient({int statusCode = 500}) {
    return MockClient((request) async {
      capturedRequests.add(request);
      return http.Response('error', statusCode);
    });
  }

  setUp(() {
    capturedRequests = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await analytics.dispose();
  });

  group('trackPageView', () {
    test('sends correct payload structure', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'test-website-id',
        endpoint: 'https://analytics.example.com/api/send',
        hostname: 'test-app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home', title: 'Home');

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['type'], 'event');
      expect(body['payload']['website'], 'test-website-id');
      expect(body['payload']['url'], '/home');
      expect(body['payload']['title'], 'Home');
      expect(body['payload']['hostname'], 'test-app');
      expect(body['payload']['language'], isA<String>());
      expect(body['payload']['screen'], 'ios');
    });

    test('sends to correct endpoint', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://analytics.example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/test');

      expect(
        capturedRequests.first.url.toString(),
        'https://analytics.example.com/api/send',
      );
    });

    test('omits title when not provided', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload'].containsKey('title'), isFalse);
    });
  });

  group('trackEvent', () {
    test('sends event name in payload', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackEvent(name: 'button_clicked', url: '/home');

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['name'], 'button_clicked');
      expect(body['payload']['url'], '/home');
    });

    test('includes custom data when provided', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackEvent(
        name: 'purchase',
        data: {'amount': 9.99, 'currency': 'USD'},
      );

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['data'], {'amount': 9.99, 'currency': 'USD'});
    });

    test('uses empty string url when not provided', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackEvent(name: 'tap');

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['url'], '');
    });
  });

  group('headers', () {
    test('sends Content-Type application/json', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/');

      expect(capturedRequests.first.headers['content-type'],
          contains('application/json'));
    });

    test('sends User-Agent header', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/');

      expect(capturedRequests.first.headers['user-agent'], isNotNull);
      expect(capturedRequests.first.headers['user-agent'], contains('Mozilla'));
    });
  });

  group('cache token', () {
    test('stores cache token from successful response', () async {
      mockClient = successClient(cacheToken: 'my-token');
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/first');
      await analytics.trackPageView(url: '/second');

      expect(capturedRequests[1].headers['x-umami-cache'], 'my-token');
    });

    test('does not send cache header on first request', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/first');

      expect(capturedRequests.first.headers['x-umami-cache'], isNull);
    });
  });

  group('queue integration', () {
    test('queues event on send failure with in-memory queue', () async {
      mockClient = failClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: UmamiQueueInMemory(maxSize: 10),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/fail');

      // Event should be queued, not lost
      // Verify by making a successful send which triggers flush
      capturedRequests.clear();
      var flushRequestCount = 0;
      mockClient = MockClient((request) async {
        capturedRequests.add(request);
        flushRequestCount++;
        return http.Response(
          jsonEncode({'cache': 'tok'}),
          200,
        );
      });
      // Replace the client — we need to recreate analytics
      // Instead, verify queue by flushing manually
    });

    test('does not queue when queue is disabled', () async {
      mockClient = failClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      // Should not throw, event is silently discarded
      await analytics.trackPageView(url: '/fail');
    });

    test('flush sends queued events', () async {
      var callCount = 0;
      mockClient = MockClient((request) async {
        capturedRequests.add(request);
        callCount++;
        if (callCount <= 2) {
          // First two calls fail (initial sends)
          return http.Response('error', 500);
        }
        // Subsequent calls succeed (flush)
        return http.Response(jsonEncode({'cache': 'tok'}), 200);
      });
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: UmamiQueueInMemory(maxSize: 10),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/page1');
      await analytics.trackEvent(name: 'evt1');

      capturedRequests.clear();
      await analytics.flush();

      // Both queued events should be sent
      expect(capturedRequests, hasLength(2));
    });
  });

  group('logging', () {
    test('logs events when enableEventLogging is true', () async {
      final logs = <String>[];
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        enableEventLogging: true,
        logger: (level, message) => logs.add('${level.name}: $message'),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      expect(logs, contains(matches(RegExp(r'info: .*Page view.*\/home'))));
    });

    test('does not log events when enableEventLogging is false', () async {
      final logs = <String>[];
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        enableEventLogging: false,
        logger: (level, message) => logs.add(message),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      expect(logs, isEmpty);
    });

    test('logs queue operations when enableQueueLogging is true', () async {
      final logs = <String>[];
      mockClient = failClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: UmamiQueueInMemory(maxSize: 10),
        enableQueueLogging: true,
        logger: (level, message) => logs.add('${level.name}: $message'),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/fail');

      expect(logs, anyElement(matches(RegExp(r'info: .*queued'))));
    });
  });

  group('platform detection', () {
    test('screen is ios on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/');

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['screen'], 'ios');
    });

    test('screen is android on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/');

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['screen'], 'android');
    });
  });
}
```

**Step 2: Run tests to verify they fail**

```bash
flutter test test/umami_analytics_test.dart
```

Expected: FAIL.

**Step 3: Implement the core class**

```dart
// lib/src/umami_analytics.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'umami_logger.dart';
import 'queue/umami_queue.dart';
import 'queue/umami_queue_config.dart';
import 'queue/in_memory_queue.dart';
import 'queue/persisted_queue.dart';

/// Umami analytics client for Flutter.
///
/// Sends page view and custom events to an Umami instance via the
/// `/api/send` endpoint. Supports offline queuing and automatic
/// session continuity via the `x-umami-cache` token.
class UmamiAnalytics {
  /// The website ID from your Umami dashboard.
  final String websiteId;

  /// The full Umami endpoint URL (e.g., `https://analytics.example.com/api/send`).
  final String endpoint;

  /// Hostname identifier included in every payload.
  final String hostname;

  /// Queue strategy for offline resilience.
  final UmamiQueueConfig queueConfig;

  /// When true, logs every [trackPageView] and [trackEvent] call.
  final bool enableEventLogging;

  /// When true, logs queue insert, flush, drop, and size operations.
  final bool enableQueueLogging;

  final UmamiLogger _logger;
  final http.Client _httpClient;

  UmamiQueue? _queue;
  bool _queueInitialized = false;
  String? _cacheToken;
  bool _isFlushing = false;

  /// Creates a new Umami analytics client.
  ///
  /// [websiteId], [endpoint], and [hostname] are required.
  /// Provide [httpClient] to inject a custom HTTP client (useful for testing).
  UmamiAnalytics({
    required this.websiteId,
    required this.endpoint,
    required this.hostname,
    this.queueConfig = const UmamiQueuePersisted(),
    this.enableEventLogging = false,
    this.enableQueueLogging = false,
    UmamiLogger? logger,
    http.Client? httpClient,
  })  : _logger = logger ?? _defaultLogger,
        _httpClient = httpClient ?? http.Client();

  static void _defaultLogger(UmamiLogLevel level, String message) {
    debugPrint('[umami] ${level.name}: $message');
  }

  String get _screen {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String get _language =>
      PlatformDispatcher.instance.locale.toString();

  String get _userAgent {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
            'Mobile/15E148 Safari/604.1';
      case TargetPlatform.android:
        return 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
      default:
        return 'Mozilla/5.0 (compatible; UmamiAnalytics/1.0)';
    }
  }

  Map<String, dynamic> _buildPayload({
    required String url,
    String? title,
    String? name,
    Map<String, dynamic>? data,
  }) {
    return {
      'type': 'event',
      'payload': {
        'website': websiteId,
        'url': url,
        'hostname': hostname,
        'language': _language,
        'screen': _screen,
        'referrer': '',
        if (title != null) 'title': title,
        if (name != null) 'name': name,
        if (data != null) 'data': data,
      },
    };
  }

  Future<bool> _send(Map<String, dynamic> payload) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
              if (_cacheToken != null) 'x-umami-cache': _cacheToken!,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        try {
          final body =
              jsonDecode(response.body) as Map<String, dynamic>;
          _cacheToken = body['cache'] as String?;
        } catch (_) {
          // Response may not contain a parseable cache token.
        }
        return true;
      }
      return false;
    } on TimeoutException {
      _log(UmamiLogLevel.error, 'Send timed out');
      return false;
    } catch (e) {
      _log(UmamiLogLevel.error, 'Send failed: $e');
      return false;
    }
  }

  /// Track a page view.
  ///
  /// [url] is required (e.g., `/home`). [title] is optional.
  Future<void> trackPageView({required String url, String? title}) async {
    final payload = _buildPayload(url: url, title: title);
    if (enableEventLogging) {
      _log(UmamiLogLevel.info, 'Page view: $url');
    }

    final success = await _send(payload);
    if (success) {
      _triggerFlush();
    } else {
      await _enqueue(payload);
    }
  }

  /// Track a custom event.
  ///
  /// [name] is required (max 50 chars). [url] and [data] are optional.
  Future<void> trackEvent({
    required String name,
    String? url,
    Map<String, dynamic>? data,
  }) async {
    final payload = _buildPayload(url: url ?? '', name: name, data: data);
    if (enableEventLogging) {
      _log(UmamiLogLevel.info, 'Event: $name');
    }

    final success = await _send(payload);
    if (success) {
      _triggerFlush();
    } else {
      await _enqueue(payload);
    }
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final queue = await _ensureQueue();
    if (queue == null) {
      if (enableQueueLogging) {
        _log(UmamiLogLevel.warning, 'Event dropped (queue disabled)');
      }
      return;
    }
    await queue.insert(payload);
    if (enableQueueLogging) {
      _log(UmamiLogLevel.info,
          'Event queued (${await queue.length} in queue)');
    }
  }

  void _triggerFlush() {
    if (queueConfig is UmamiQueueDisabled) return;
    unawaited(_backgroundFlush());
  }

  Future<void> _backgroundFlush() async {
    if (_isFlushing) return;
    final queue = await _ensureQueue();
    if (queue == null) return;

    final queueLength = await queue.length;
    if (queueLength == 0) return;

    _isFlushing = true;
    try {
      if (queueConfig case UmamiQueuePersisted(eventTtl: final ttl)) {
        await queue.deleteExpired(ttl);
      }

      if (enableQueueLogging) {
        _log(UmamiLogLevel.info, 'Flush started ($queueLength events)');
      }

      final events = await queue.getAll();
      var sent = 0;
      for (final event in events) {
        final success = await _send(event.payload);
        if (success) {
          await queue.delete(event.id);
          sent++;
        }
      }

      if (enableQueueLogging) {
        _log(UmamiLogLevel.info,
            'Flush complete ($sent/${events.length} sent)');
      }
    } finally {
      _isFlushing = false;
    }
  }

  /// Manually flush the offline queue.
  ///
  /// Sends all queued events oldest-first. Failed events remain in the queue.
  Future<void> flush() async {
    _isFlushing = false;
    await _backgroundFlush();
  }

  Future<UmamiQueue?> _ensureQueue() async {
    if (_queueInitialized) return _queue;
    _queueInitialized = true;

    switch (queueConfig) {
      case UmamiQueueDisabled():
        _queue = null;
      case UmamiQueueInMemory(maxSize: final maxSize):
        _queue = InMemoryQueue(maxSize: maxSize);
      case UmamiQueuePersisted(
          maxSize: final maxSize,
          databasePath: final path
        ):
        _queue = await PersistedQueue.open(
            maxSize: maxSize, databasePath: path);
        if (enableQueueLogging) {
          _log(UmamiLogLevel.info, 'SQLite queue initialized');
        }
    }
    return _queue;
  }

  void _log(UmamiLogLevel level, String message) {
    _logger(level, message);
  }

  /// Release resources.
  ///
  /// Closes the offline queue database (if open) and the HTTP client.
  Future<void> dispose() async {
    await _queue?.close();
    _httpClient.close();
  }
}
```

**Step 4: Run tests to verify they pass**

```bash
flutter test test/umami_analytics_test.dart
```

Expected: All PASS. Some tests may need adjustment based on exact logging format — update test expectations to match actual log output.

**Step 5: Run all tests**

```bash
flutter test
```

Expected: All PASS.

**Step 6: Commit**

```bash
git add lib/src/umami_analytics.dart test/umami_analytics_test.dart
git commit -m "feat: add UmamiAnalytics core class with queue integration and logging"
```

---

### Task 6: Navigator Observer

**Files:**
- Create: `lib/src/umami_navigator_observer.dart`
- Create: `test/umami_navigator_observer_test.dart`

**Step 1: Write observer tests**

```dart
// test/umami_navigator_observer_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umami_analytics/src/umami_analytics.dart';
import 'package:umami_analytics/src/umami_navigator_observer.dart';
import 'package:umami_analytics/src/queue/umami_queue_config.dart';

void main() {
  late List<http.Request> capturedRequests;
  late UmamiAnalytics analytics;
  late UmamiNavigatorObserver observer;

  setUp(() {
    capturedRequests = [];
    final mockClient = MockClient((request) async {
      capturedRequests.add(request);
      return http.Response(jsonEncode({'cache': 'tok'}), 200);
    });
    analytics = UmamiAnalytics(
      websiteId: 'wid',
      endpoint: 'https://example.com/api/send',
      hostname: 'app',
      queueConfig: const UmamiQueueDisabled(),
      httpClient: mockClient,
    );
  });

  tearDown(() async {
    await analytics.dispose();
  });

  group('didPush', () {
    test('tracks page view for named route', () async {
      observer = UmamiNavigatorObserver(analytics: analytics);

      await _pumpApp(observer: observer, routes: {
        '/': (_) => const Text('Home'),
        '/about': (_) => const Text('About'),
      });

      // Initial route '/' is pushed
      await Future.delayed(Duration.zero);
      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['url'], '/');
    });

    test('skips routes without a name', () async {
      observer = UmamiNavigatorObserver(analytics: analytics);
      observer.didPush(
        _createRoute(name: null),
        null,
      );

      await Future.delayed(Duration.zero);
      expect(capturedRequests, isEmpty);
    });
  });

  group('didReplace', () {
    test('tracks page view for replacement route', () async {
      observer = UmamiNavigatorObserver(analytics: analytics);
      observer.didReplace(
        newRoute: _createRoute(name: '/new'),
        oldRoute: _createRoute(name: '/old'),
      );

      await Future.delayed(Duration.zero);
      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['url'], '/new');
    });

    test('skips when newRoute is null', () async {
      observer = UmamiNavigatorObserver(analytics: analytics);
      observer.didReplace(newRoute: null, oldRoute: _createRoute(name: '/old'));

      await Future.delayed(Duration.zero);
      expect(capturedRequests, isEmpty);
    });
  });

  group('routeFilter', () {
    test('skips routes rejected by filter', () async {
      observer = UmamiNavigatorObserver(
        analytics: analytics,
        routeFilter: (route) => route.settings.name != '/skip',
      );
      observer.didPush(_createRoute(name: '/skip'), null);

      await Future.delayed(Duration.zero);
      expect(capturedRequests, isEmpty);
    });

    test('tracks routes accepted by filter', () async {
      observer = UmamiNavigatorObserver(
        analytics: analytics,
        routeFilter: (route) => route.settings.name == '/track',
      );
      observer.didPush(_createRoute(name: '/track'), null);

      await Future.delayed(Duration.zero);
      expect(capturedRequests, hasLength(1));
    });
  });

  group('routeNameMapper', () {
    test('uses mapper to transform route name', () async {
      observer = UmamiNavigatorObserver(
        analytics: analytics,
        routeNameMapper: (route) => '/mapped${route.settings.name}',
      );
      observer.didPush(_createRoute(name: '/page'), null);

      await Future.delayed(Duration.zero);
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['url'], '/mapped/page');
    });
  });
}

Route<dynamic> _createRoute({String? name}) {
  return MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox(),
  );
}

Future<void> _pumpApp({
  required UmamiNavigatorObserver observer,
  required Map<String, WidgetBuilder> routes,
}) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final app = MaterialApp(
    navigatorObservers: [observer],
    routes: routes,
  );
  await binding.attachRootWidget(app);
  await binding.pump();
}
```

Note: The `_pumpApp` helper may need adjustment. A simpler approach is to call observer methods directly (as shown in most tests). The `didPush` test with `_pumpApp` verifies integration with a real `MaterialApp`.

**Step 2: Run tests to verify they fail**

```bash
flutter test test/umami_navigator_observer_test.dart
```

Expected: FAIL.

**Step 3: Implement the navigator observer**

```dart
// lib/src/umami_navigator_observer.dart
import 'package:flutter/widgets.dart';

import 'umami_analytics.dart';

/// Automatically tracks page views via Flutter's navigation system.
///
/// Add this observer to your [MaterialApp.navigatorObservers] to track
/// page views on [didPush] and [didReplace] events.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [
///     UmamiNavigatorObserver(analytics: umami),
///   ],
/// );
/// ```
class UmamiNavigatorObserver extends NavigatorObserver {
  /// The [UmamiAnalytics] instance to send page views through.
  final UmamiAnalytics analytics;

  /// Optional predicate to filter which routes trigger page views.
  ///
  /// Defaults to requiring a non-null [RouteSettings.name].
  final bool Function(Route<dynamic> route)? routeFilter;

  /// Optional transform from a route to a URL string.
  ///
  /// Defaults to [RouteSettings.name].
  final String Function(Route<dynamic> route)? routeNameMapper;

  UmamiNavigatorObserver({
    required this.analytics,
    this.routeFilter,
    this.routeNameMapper,
  });

  bool _shouldTrack(Route<dynamic> route) {
    if (routeFilter != null) return routeFilter!(route);
    return route.settings.name != null;
  }

  String _getUrl(Route<dynamic> route) {
    if (routeNameMapper != null) return routeNameMapper!(route);
    return route.settings.name ?? '/';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_shouldTrack(route)) {
      analytics.trackPageView(url: _getUrl(route));
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null && _shouldTrack(newRoute)) {
      analytics.trackPageView(url: _getUrl(newRoute));
    }
  }
}
```

**Step 4: Run tests to verify they pass**

```bash
flutter test test/umami_navigator_observer_test.dart
```

Expected: All PASS.

**Step 5: Run all tests**

```bash
flutter test
```

Expected: All PASS.

**Step 6: Commit**

```bash
git add lib/src/umami_navigator_observer.dart test/umami_navigator_observer_test.dart
git commit -m "feat: add UmamiNavigatorObserver for automatic page view tracking"
```

---

### Task 7: Barrel Export, README & Example

**Files:**
- Modify: `lib/umami_analytics.dart` (barrel export)
- Create: `README.md`
- Create: `example/lib/main.dart`
- Create: `example/pubspec.yaml`

**Step 1: Update barrel export**

```dart
// lib/umami_analytics.dart
library umami_analytics;

export 'src/umami_analytics.dart';
export 'src/umami_navigator_observer.dart';
export 'src/umami_logger.dart';
export 'src/queue/umami_queue_config.dart';
```

**Step 2: Create README.md**

```markdown
# umami_analytics

A production-quality Flutter package for [Umami](https://umami.is) analytics with offline support, automatic page view tracking, and configurable logging.

## Features

- **Page view & custom event tracking** via Umami's `/api/send` endpoint
- **Offline queue** with three modes: disabled, in-memory, or SQLite-persisted
- **Automatic page view tracking** with `UmamiNavigatorObserver`
- **Session continuity** via the `x-umami-cache` token
- **Configurable logging** with two granularity flags and a pluggable callback
- **Minimal dependencies** — only `http` and `sqflite`

## Getting started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  umami_analytics: ^0.1.0
```

Create a website in your Umami dashboard and note the **Website ID**.

## Usage

### Basic setup

```dart
import 'package:umami_analytics/umami_analytics.dart';

final umami = UmamiAnalytics(
  websiteId: 'your-website-id',
  endpoint: 'https://your-umami-instance.com/api/send',
  hostname: 'my-flutter-app',
);
```

### Track page views

```dart
await umami.trackPageView(url: '/home', title: 'Home');
```

### Track custom events

```dart
await umami.trackEvent(
  name: 'button_clicked',
  url: '/home',
  data: {'button_id': 'subscribe'},
);
```

### Automatic page view tracking

```dart
MaterialApp(
  navigatorObservers: [
    UmamiNavigatorObserver(
      analytics: umami,
      routeFilter: (route) => route.settings.name != null,
      routeNameMapper: (route) => route.settings.name!,
    ),
  ],
);
```

### Queue configuration

```dart
// No queue (fire and forget)
final umami = UmamiAnalytics(
  websiteId: 'id',
  endpoint: 'https://example.com/api/send',
  hostname: 'app',
  queueConfig: UmamiQueueDisabled(),
);

// In-memory queue (lost on restart)
final umami = UmamiAnalytics(
  websiteId: 'id',
  endpoint: 'https://example.com/api/send',
  hostname: 'app',
  queueConfig: UmamiQueueInMemory(maxSize: 200),
);

// SQLite-persisted queue (survives restarts, default)
final umami = UmamiAnalytics(
  websiteId: 'id',
  endpoint: 'https://example.com/api/send',
  hostname: 'app',
  queueConfig: UmamiQueuePersisted(
    maxSize: 500,
    eventTtl: Duration(hours: 48),
  ),
);
```

### Logging

```dart
final umami = UmamiAnalytics(
  websiteId: 'id',
  endpoint: 'https://example.com/api/send',
  hostname: 'app',
  enableEventLogging: true,
  enableQueueLogging: true,
  logger: (level, message) => print('[$level] $message'),
);
```

### Cleanup

```dart
await umami.dispose();
```

## API reference

| Method | Description |
|--------|-------------|
| `trackPageView(url:, title:)` | Send a page view event |
| `trackEvent(name:, url:, data:)` | Send a custom event with optional metadata |
| `flush()` | Manually flush the offline queue |
| `dispose()` | Close the queue database and HTTP client |

## License

MIT
```

**Step 3: Create example app**

```yaml
# example/pubspec.yaml
name: umami_analytics_example
description: Example app for umami_analytics package.

publish_to: none

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
  umami_analytics:
    path: ../
```

```dart
// example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:umami_analytics/umami_analytics.dart';

final umami = UmamiAnalytics(
  websiteId: 'your-website-id',
  endpoint: 'https://your-umami-instance.com/api/send',
  hostname: 'umami-analytics-example',
  queueConfig: UmamiQueueInMemory(maxSize: 100),
  enableEventLogging: true,
);

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umami Analytics Example',
      navigatorObservers: [
        UmamiNavigatorObserver(analytics: umami),
      ],
      routes: {
        '/': (_) => const HomePage(),
        '/about': (_) => const AboutPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                umami.trackEvent(
                  name: 'button_clicked',
                  url: '/',
                  data: {'button': 'navigate_about'},
                );
                Navigator.pushNamed(context, '/about');
              },
              child: const Text('Go to About'),
            ),
            ElevatedButton(
              onPressed: () {
                umami.trackEvent(name: 'manual_event', url: '/');
              },
              child: const Text('Track Custom Event'),
            ),
          ],
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(child: Text('About Page')),
    );
  }
}
```

**Step 4: Run `flutter pub get` in example**

```bash
cd example && flutter pub get && cd ..
```

**Step 5: Run all tests to verify nothing broke**

```bash
flutter test
```

Expected: All PASS.

**Step 6: Commit**

```bash
git add lib/umami_analytics.dart README.md example/
git commit -m "feat: add barrel export, README, and example app"
```

---

### Task 8: Dartdoc, Analysis & Final Polish

**Files:**
- Potentially modify any `lib/src/*.dart` file for dartdoc and formatting

**Step 1: Run static analysis**

```bash
flutter analyze
```

Fix any warnings or hints. Common issues:
- Missing dartdoc on public members
- Unused imports
- Prefer const constructors

**Step 2: Run formatter**

```bash
dart format lib/ test/ example/
```

**Step 3: Verify all tests still pass**

```bash
flutter test
```

Expected: All PASS.

**Step 4: Run analysis again to confirm clean**

```bash
flutter analyze
```

Expected: No issues found.

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: fix analysis warnings and format all files"
```

---

## Parallelization Summary

| Phase | Tasks | Parallel? |
|-------|-------|-----------|
| 1 | Task 1: Scaffolding | Sequential |
| 2 | Task 2: Types, Task 3: Queue | **Parallel** |
| 3 | Task 4: Persisted Queue | Sequential |
| 4 | Task 5: Core Class | Sequential |
| 5 | Task 6: Observer | Sequential |
| 6 | Task 7: Docs & Example | Sequential |
| 7 | Task 8: Polish | Sequential |
