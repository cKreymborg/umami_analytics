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
