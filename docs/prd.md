# umami_flutter - Product Requirements Document

**Date:** 2026-03-28
**Status:** Draft

## Problem

Umami is a growing privacy-focused analytics platform, but the Flutter ecosystem lacks a quality package for it. The existing packages on pub.dev (flutter_umami, umami_tracker, flutter_estatisticas) have minimal adoption, limited features, and no offline support. Flutter developers integrating Umami must roll their own HTTP layer, queue management, and navigation tracking.

## Goal

Build a production-quality Flutter package for Umami analytics that provides a clean API, automatic page view tracking, and offline resilience — filling a clear gap in the ecosystem.

## Target Users

- Flutter developers using self-hosted or cloud Umami instances
- Teams migrating from Google Analytics to a privacy-focused alternative
- Developers who need reliable analytics in mobile apps with intermittent connectivity

## Requirements

### Core Tracking

- **Manual page view tracking** — `trackPageView(url:, title:)` sends a page view event to Umami's `/api/send` endpoint
- **Custom event tracking** — `trackEvent(name:, url:, data:)` sends named events with optional metadata
- **Umami cache token** — persist the `x-umami-cache` header across requests for visit continuity
- **Platform metadata** — automatically include device locale, platform (ios/android), and hostname in payloads

### Automatic Page View Tracking

- **NavigatorObserver** — `UmamiNavigatorObserver` hooks into Flutter's navigation system, tracking page views on `didPush` and `didReplace`
- **Route filter** — optional `routeFilter` predicate to skip unwanted routes (dialogs, bottom sheets). Defaults to requiring a non-null route name
- **Route name mapper** — optional `routeNameMapper` callback to customize the URL string derived from a route. Defaults to `route.settings.name`
- **Manual tracking still available** — auto tracking does not replace manual `trackPageView` for cases like tab switches

### Offline Queue

The package must handle intermittent connectivity gracefully. Three queue modes via a sealed class:

#### UmamiQueueDisabled
- Fire and forget, no retry
- Events that fail to send are lost

#### UmamiQueueInMemory
- Queue stored in a `List`
- Lost on app restart
- Configurable `maxSize` (default: 500)

#### UmamiQueuePersisted
- Queue stored in SQLite via `sqflite`
- Survives app restarts
- Configurable `maxSize` (default: 500)
- Configurable `databasePath` (defaults to `getDatabasesPath()/umami_queue.db`)
- Configurable `eventTtl` (default: 48 hours)

#### Queue Behavior
- On send failure (timeout, socket exception, non-2xx), the event payload is inserted into the queue
- On the next successful send, a background flush is triggered
- Flush iterates all non-expired events oldest-first, sending one at a time
- A failed event during flush is skipped (left in queue for next attempt) — it does not block subsequent events
- Events exceeding `maxSize` cause the oldest events to be dropped on insert
- Events older than `eventTtl` are dropped during flush
- No concurrent flushes (guarded by a `_isFlushing` flag)
- Flush runs in a background Future, does not block the current `track*` call

### Logging

- **Event logging flag** (`enableEventLogging`) — logs every `track*` call with event name and URL
- **Queue logging flag** (`enableQueueLogging`) — logs queue insert, flush, drop, and size operations
- **Log levels** — `UmamiLogLevel` enum: `debug`, `info`, `warning`, `error`
- **Custom logger callback** — `UmamiLogger` typedef: `void Function(UmamiLogLevel level, String message)`. Falls back to `debugPrint` when not provided
- Both flags default to `false` (silent)

### Lifecycle

- **Single constructor** — all configuration provided at initialization, no separate init step
- **`flush()`** — manual queue flush for consumers who want explicit control
- **`dispose()`** — closes SQLite connection and cancels pending work. Must be called when done

## Non-Requirements

- No built-in dashboard or UI components
- No Umami REST API management (creating websites, users, teams)
- No server-side Dart support (Flutter-only)
- No batched event sending (Umami's API takes single events)

## Dependencies

- `http` — HTTP client (Dart team maintained, minimal transitive dependencies)
- `sqflite` — SQLite (only used with `UmamiQueuePersisted`)

## Quality Requirements

### Test Coverage
- Target 100% code coverage (or as close as possible)
- Unit tests for all public API methods
- Unit tests for queue logic (insert, flush, drop, TTL expiry, max size enforcement)
- Unit tests for navigator observer (didPush, didReplace, route filtering, name mapping)
- Unit tests for logging (both flags, all log levels, custom logger callback)
- Integration tests for send-fail-queue-flush cycle
- Mock HTTP layer for deterministic testing

### pub.dev Score (max 160 points)
- **Follow Dart file conventions** — `analysis_options.yaml` with `flutter_lints` or stricter
- **Provide documentation** — dartdoc comments on every public API member
- **Support multiple platforms** — iOS, Android (and web/desktop if feasible)
- **Pass static analysis** — zero warnings, zero hints
- **Provide a well-formatted README** — badges, install instructions, usage examples, API reference
- **Provide an example** — `example/` directory with a runnable Flutter app
- **Support up-to-date dependencies** — no outdated or deprecated packages
- **Null safety** — fully sound null-safe
- **CHANGELOG.md** — maintain a changelog from the start
- **LICENSE** — MIT

## Success Criteria

- Clean, minimal public API surface
- Zero silent data loss when offline (within TTL and queue size bounds)
- No runtime cost when queue is disabled
- Works with both self-hosted and Umami Cloud instances
- Published on pub.dev with full documentation and example app
- 100% (or near-100%) test coverage
- Maximum pub.dev score (160/160 pub points)
