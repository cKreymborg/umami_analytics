/// A single queued event with metadata.
class QueuedEvent {
  /// Unique identifier for this queued event.
  final int id;

  /// The full event payload (JSON-serializable map sent to Umami).
  final Map<String, dynamic> payload;

  /// When this event was added to the queue.
  final DateTime createdAt;

  QueuedEvent({
    required this.id,
    required this.payload,
    required this.createdAt,
  });
}

/// Abstract interface for event queue implementations.
abstract class UmamiQueue {
  /// Insert an event payload into the queue, enforcing maxSize by dropping oldest.
  Future<void> insert(Map<String, dynamic> payload);

  /// Retrieve all queued events, oldest first.
  Future<List<QueuedEvent>> getAll();

  /// Delete a single event by [id].
  Future<void> delete(int id);

  /// Delete all events older than [ttl] from now.
  Future<void> deleteExpired(Duration ttl);

  /// Current number of events in the queue.
  Future<int> get length;

  /// Release resources (clear memory or close database).
  Future<void> close();
}
