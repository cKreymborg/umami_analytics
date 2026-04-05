import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umami_analytics/src/umami_analytics.dart';
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

  group('userId', () {
    test('includes id in payload when userId is provided', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        userId: 'user-123',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['id'], 'user-123');
    });

    test('omits id from payload when userId is null', () async {
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
      expect(body['payload'].containsKey('id'), isFalse);
    });
  });

  group('enabled', () {
    test('does not send HTTP request for trackPageView when false', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        enabled: false,
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      expect(capturedRequests, isEmpty);
    });

    test('does not send HTTP request for trackEvent when false', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        enabled: false,
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackEvent(name: 'tap');

      expect(capturedRequests, isEmpty);
    });

    test('still logs events when disabled and enableEventLogging is true',
        () async {
      final logs = <String>[];
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        enabled: false,
        queueConfig: const UmamiQueueDisabled(),
        enableEventLogging: true,
        logger: (level, message) => logs.add('${level.name}: $message'),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      expect(logs, contains(matches(RegExp(r'info: .*Page view.*\/home'))));
      expect(
          logs, contains(matches(RegExp(r'debug: .*Tracking disabled.*'))));
    });

    test('does not enqueue events when disabled', () async {
      mockClient = failClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        enabled: false,
        queueConfig: UmamiQueueInMemory(maxSize: 10),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');
      await analytics.trackEvent(name: 'tap');

      // Re-enable would be needed to flush, but since enabled is final
      // we verify no HTTP requests were made at all (no send, no enqueue)
      expect(capturedRequests, isEmpty);
    });

    test('flush is a no-op when disabled', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        enabled: false,
        queueConfig: UmamiQueueInMemory(maxSize: 10),
        httpClient: mockClient,
      );

      await analytics.flush();

      expect(capturedRequests, isEmpty);
    });

    test('sends normally when enabled is true (default)', () async {
      mockClient = successClient();
      analytics = UmamiAnalytics(
        websiteId: 'wid',
        endpoint: 'https://example.com/api/send',
        hostname: 'app',
        queueConfig: const UmamiQueueDisabled(),
        httpClient: mockClient,
      );

      await analytics.trackPageView(url: '/home');

      expect(capturedRequests, hasLength(1));
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
