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

## Contributing

Contributions are welcome! Please [open an issue](https://github.com/cKreymborg/umami_analytics/issues) first before submitting a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT
