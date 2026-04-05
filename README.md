# umami_analytics

A production-quality Flutter package for [Umami](https://umami.is) analytics with offline support, automatic page view tracking, and configurable logging.

## Features

- **Page view & custom event tracking** via Umami's `/api/send` endpoint
- **Offline queue** with three modes: disabled, in-memory, or SQLite-persisted
- **Automatic page view tracking** with `UmamiNavigatorObserver`
- **Session continuity** via the `x-umami-cache` token
- **Enable/disable tracking** — suppress HTTP sends in debug mode while keeping event logging
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
  userId: 'optional-user-id', // enables stable session tracking across restarts
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

Instead of manually calling `trackPageView` on every navigation, you can add `UmamiNavigatorObserver` to your app. It hooks into Flutter's navigation system and automatically tracks page views whenever a route is pushed or replaced. You can optionally filter which routes are tracked and customize how route names are mapped to URLs.

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

If a send fails (e.g. the device is offline), the event can be saved to a queue and retried later. The next successful send automatically triggers a flush of any queued events. There are three modes:

- **Disabled** — events that fail to send are discarded.
- **In-memory** — failed events are buffered in memory. Fast, but lost on app restart.
- **Persisted** (default) — failed events are stored in a local SQLite database and survive app restarts. Events older than the configured TTL are automatically dropped during flush.

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

### Disabling tracking

Set `enabled: false` to suppress all HTTP requests while keeping event logging active. This is useful during development to see which events fire without polluting your production analytics.

```dart
final umami = UmamiAnalytics(
  websiteId: 'id',
  endpoint: 'https://example.com/api/send',
  hostname: 'app',
  enabled: !kDebugMode, // disable in debug mode
  enableEventLogging: true, // still see events in the console
);
```

### Logging

Logging is off by default. You can independently enable logging for tracking calls (`enableEventLogging`) and queue operations (`enableQueueLogging`). By default, logs go to `debugPrint`. If you want to route them somewhere else, provide a custom `logger` callback.

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

Call `dispose()` when you're done with the analytics instance — for example, in your app's `dispose` lifecycle method or before the app exits. This closes the SQLite database (if using a persisted queue) and the underlying HTTP client.

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

## Contributing

Contributions are welcome! If you're a first-time contributor, please [open an issue](https://github.com/cKreymborg/umami_analytics/issues) before submitting a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT
