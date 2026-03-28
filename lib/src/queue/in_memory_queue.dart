import 'umami_queue.dart';

/// List-backed event queue. Events are lost on app restart.
class InMemoryQueue implements UmamiQueue {
  /// Maximum number of events to keep in the queue.
  final int maxSize;
  final List<QueuedEvent> _events = [];
  int _nextId = 1;

  /// Creates an in-memory queue with the given [maxSize].
  InMemoryQueue({required this.maxSize});

  @override
  Future<void> insert(Map<String, dynamic> payload) async {
    _events.add(QueuedEvent(
      id: _nextId++,
      payload: Map<String, dynamic>.from(payload),
      createdAt: DateTime.now(),
    ));
    while (_events.length > maxSize) {
      _events.removeAt(0);
    }
  }

  @override
  Future<List<QueuedEvent>> getAll() async =>
      List<QueuedEvent>.unmodifiable(_events);

  @override
  Future<void> delete(int id) async {
    _events.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> deleteExpired(Duration ttl) async {
    final cutoff = DateTime.now().subtract(ttl);
    _events.removeWhere((e) => e.createdAt.isBefore(cutoff));
  }

  @override
  Future<int> get length async => _events.length;

  @override
  Future<void> close() async {
    _events.clear();
  }
}
