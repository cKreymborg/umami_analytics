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
