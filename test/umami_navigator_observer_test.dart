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
      observer.didPush(_createRoute(name: '/home'), null);

      // Allow the async trackPageView to complete
      await Future.delayed(Duration.zero);

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      expect(body['payload']['url'], '/home');
    });

    test('skips routes without a name', () async {
      observer = UmamiNavigatorObserver(analytics: analytics);
      observer.didPush(_createRoute(name: null), null);

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
