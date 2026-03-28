# umami_flutter - Technical Design

**Date:** 2026-03-28
**Status:** Draft

## Package Structure

```
umami_flutter/
  lib/
    umami_flutter.dart                # barrel export
    src/
      umami_analytics.dart            # main client class
      umami_navigator_observer.dart   # auto page view tracking
      umami_logger.dart               # UmamiLogLevel enum, UmamiLogger typedef
      queue/
        umami_queue_config.dart       # sealed class (Disabled, InMemory, Persisted)
        umami_queue.dart              # abstract queue interface
        in_memory_queue.dart          # List-based implementation
        persisted_queue.dart          # sqflite implementation
  test/
    ...
  pubspec.yaml
```

## Public API

### Constructor

```dart
final umami = UmamiAnalytics(
  // Required
  websiteId: 'your-website-id',
  endpoint: 'https://your-umami.com/api/send',
  hostname: 'my-flutter-app',

  // Queue (default: persisted, 500 events, 48h TTL)
  queueConfig: UmamiQueuePersisted(
    maxSize: 500,
    eventTtl: Duration(hours: 48),
    databasePath: null,  // defaults to getDatabasesPath()/umami_queue.db
  ),

  // Logging
  enableEventLogging: false,
  enableQueueLogging: false,
  logger: null,  // (UmamiLogLevel, String) -> void, defaults to debugPrint
);
```

### Tracking Methods

```dart
// Manual page view
await umami.trackPageView(url: '/home', title: 'Home');

// Custom event with optional metadata
await umami.trackEvent(
  name: 'button_clicked',
  url: '/home',
  data: {'button_id': 'subscribe'},
);

// Manual queue flush
await umami.flush();

// Cleanup
await umami.dispose();
```

### Navigator Observer

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

- Calls `trackPageView` on `didPush` and `didReplace`
- `routeFilter` — optional predicate, defaults to "has a non-null route name"
- `routeNameMapper` — optional transform from route to URL string, defaults to `route.settings.name`

## Queue Configuration (Sealed Class)

```dart
sealed class UmamiQueueConfig {}

class UmamiQueueDisabled extends UmamiQueueConfig {}

class UmamiQueueInMemory extends UmamiQueueConfig {
  final int maxSize;
  UmamiQueueInMemory({this.maxSize = 500});
}

class UmamiQueuePersisted extends UmamiQueueConfig {
  final int maxSize;
  final String? databasePath;
  final Duration eventTtl;
  UmamiQueuePersisted({
    this.maxSize = 500,
    this.databasePath,
    this.eventTtl = const Duration(hours: 48),
  });
}
```

## Logging

```dart
enum UmamiLogLevel { debug, info, warning, error }

typedef UmamiLogger = void Function(UmamiLogLevel level, String message);
```

### Log level usage

| Level | Examples |
|-------|---------|
| `debug` | Payload details, raw HTTP data |
| `info` | Event tracked, flush complete, DB initialized |
| `warning` | Event dropped (max queue), flush stopped (all expired) |
| `error` | Send failed, DB error |

### What each flag controls

- `enableEventLogging` — logs every `trackPageView` / `trackEvent` call
- `enableQueueLogging` — logs queue insert, flush progress, drops, size

When `logger` is null, logs go to `debugPrint`. When provided, all logs route through the callback.

## SQLite Schema

```sql
CREATE TABLE event_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
```

- `payload` — JSON-encoded event map (the full body sent to Umami)
- `created_at` — Unix timestamp in milliseconds
- `id` — provides natural FIFO ordering

## Queue Internals

### Send flow

```
track*() called
    |
    v
Build payload
    |
    v
Attempt HTTP POST to /api/send
    |
    +-- Success --> Update cache token
    |                   |
    |                   v
    |               Is queue non-empty?
    |                   |
    |                   +-- Yes --> Trigger background flush
    |                   +-- No  --> Done
    |
    +-- Failure --> Queue enabled?
                        |
                        +-- No  --> Log and discard
                        +-- Yes --> Insert into queue
                                        |
                                        v
                                    Queue size > maxSize?
                                        |
                                        +-- Yes --> Delete oldest rows
                                        +-- No  --> Done
```

### Flush flow

```
Flush triggered (background Future, guarded by _isFlushing)
    |
    v
SELECT all events WHERE created_at > (now - eventTtl)
DELETE expired events
    |
    v
For each event (oldest first):
    |
    +-- Attempt HTTP POST
    |       |
    |       +-- Success --> DELETE from queue, continue
    |       +-- Failure --> Leave in queue, continue to next event
    |
    v
Done (_isFlushing = false)
```

### Max queue enforcement (on insert)

```sql
DELETE FROM event_queue WHERE id IN (
  SELECT id FROM event_queue ORDER BY id ASC
  LIMIT max(0, (SELECT COUNT(*) FROM event_queue) - :maxQueueSize + 1)
);
```

## HTTP Details

### Request payload (page view)

```json
{
  "type": "event",
  "payload": {
    "website": "<websiteId>",
    "id": "<userId>",
    "url": "/home",
    "hostname": "<hostname>",
    "language": "en_US",
    "referrer": "",
    "screen": "ios",
    "title": "Home"
  }
}
```

### Request payload (custom event)

```json
{
  "type": "event",
  "payload": {
    "website": "<websiteId>",
    "id": "<userId>",
    "url": "/home",
    "name": "button_clicked",
    "hostname": "<hostname>",
    "language": "en_US",
    "referrer": "",
    "screen": "ios",
    "title": "Home",
    "data": { "button_id": "subscribe" }
  }
}
```

### Headers

```
Content-Type: application/json
User-Agent: <platform-appropriate UA string>
x-umami-cache: <cache token from previous response, if available>
```

### Timeouts

- Connect: 5 seconds
- Send: 5 seconds
- Receive: 5 seconds

### Cache token

The `x-umami-cache` header value is extracted from successful responses and included in subsequent requests. This maintains visit continuity in Umami's session tracking.

## Dependencies

| Package | Purpose | When used |
|---------|---------|-----------|
| `http` | HTTP client | Always |
| `sqflite` | SQLite database | Only with `UmamiQueuePersisted` |

## Design Decisions

1. **Passive flush over connectivity listening** — avoids `connectivity_plus` dependency and platform permissions. Flush triggers on next successful send.
2. **Failure inference over proactive connectivity checks** — handles "connected but no internet" correctly. Try to send; if it fails, queue.
3. **Skip-and-continue flush** — a failing event during flush does not block others. Prevents one bad payload from permanently blocking the queue.
4. **TTL-based expiry (48h)** — simpler than retry counting. Events that fail indefinitely expire naturally.
5. **Sealed class for queue config** — type-safe, explicit mode selection, no bag of nullable params.
6. **sqflite over drift/sqlite3** — most widely adopted Flutter SQLite package, appropriate for a Flutter-only package.
7. **`http` over `dio`** — lighter weight, fewer transitive dependencies, maintained by the Dart team. A single POST endpoint doesn't need dio's interceptors or advanced features. Can upgrade to dio later if needed.
8. **Two tracking methods only** — `trackPageView` and `trackEvent` match Umami's API. App-specific methods belong in consumer code.
