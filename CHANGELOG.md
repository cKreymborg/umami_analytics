## 0.2.0

- Add `enabled` parameter to `UmamiAnalytics` constructor to suppress HTTP requests while retaining event logging

## 0.1.0

- Initial release
- Page view and custom event tracking via Umami `/api/send` endpoint
- Offline queue with three modes: disabled, in-memory, SQLite-persisted
- `UmamiNavigatorObserver` for automatic page view tracking
- Configurable logging with two granularity flags
- Session continuity via `x-umami-cache` token
