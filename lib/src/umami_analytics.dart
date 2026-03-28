import 'dart:async';
import 'dart:convert';

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

  String get _language => PlatformDispatcher.instance.locale.toString();

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
          final body = jsonDecode(response.body) as Map<String, dynamic>;
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
      _log(
        UmamiLogLevel.info,
        'Event queued (${await queue.length} in queue)',
      );
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
        _log(
          UmamiLogLevel.info,
          'Flush complete ($sent/${events.length} sent)',
        );
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
          databasePath: final path,
        ):
        _queue = await PersistedQueue.open(
          maxSize: maxSize,
          databasePath: path,
        );
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
