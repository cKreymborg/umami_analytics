/// Configuration for the offline event queue.
///
/// Use the sealed subclasses to select a queue strategy:
/// - [UmamiQueueDisabled] — fire and forget, no retry.
/// - [UmamiQueueInMemory] — in-memory queue, lost on app restart.
/// - [UmamiQueuePersisted] — SQLite queue, survives app restarts.
sealed class UmamiQueueConfig {
  const UmamiQueueConfig();
}

/// No queue — events that fail to send are discarded.
class UmamiQueueDisabled extends UmamiQueueConfig {
  const UmamiQueueDisabled();
}

/// In-memory queue — survives temporary network failures but lost on app restart.
class UmamiQueueInMemory extends UmamiQueueConfig {
  /// Maximum number of events to keep in the queue.
  /// Oldest events are dropped when the limit is exceeded.
  final int maxSize;

  const UmamiQueueInMemory({this.maxSize = 500});
}

/// SQLite-persisted queue — survives app restarts.
class UmamiQueuePersisted extends UmamiQueueConfig {
  /// Maximum number of events to keep in the queue.
  final int maxSize;

  /// Custom database file path.
  /// Defaults to `getDatabasesPath()/umami_queue.db` when null.
  final String? databasePath;

  /// Events older than this duration are dropped during flush.
  final Duration eventTtl;

  const UmamiQueuePersisted({
    this.maxSize = 500,
    this.databasePath,
    this.eventTtl = const Duration(hours: 48),
  });
}
