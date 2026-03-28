import 'package:flutter_test/flutter_test.dart';
import 'package:umami_analytics/src/queue/umami_queue_config.dart';

void main() {
  test('UmamiQueueDisabled is a UmamiQueueConfig', () {
    final config = UmamiQueueDisabled();
    expect(config, isA<UmamiQueueConfig>());
  });

  test('UmamiQueueInMemory has default maxSize of 500', () {
    final config = UmamiQueueInMemory();
    expect(config.maxSize, 500);
  });

  test('UmamiQueueInMemory accepts custom maxSize', () {
    final config = UmamiQueueInMemory(maxSize: 100);
    expect(config.maxSize, 100);
  });

  test('UmamiQueuePersisted has default values', () {
    final config = UmamiQueuePersisted();
    expect(config.maxSize, 500);
    expect(config.databasePath, isNull);
    expect(config.eventTtl, const Duration(hours: 48));
  });

  test('UmamiQueuePersisted accepts custom values', () {
    final config = UmamiQueuePersisted(
      maxSize: 100,
      databasePath: '/tmp/test.db',
      eventTtl: const Duration(hours: 24),
    );
    expect(config.maxSize, 100);
    expect(config.databasePath, '/tmp/test.db');
    expect(config.eventTtl, const Duration(hours: 24));
  });

  test('sealed class exhaustiveness with switch', () {
    final configs = <UmamiQueueConfig>[
      UmamiQueueDisabled(),
      UmamiQueueInMemory(),
      UmamiQueuePersisted(),
    ];
    for (final config in configs) {
      final label = switch (config) {
        UmamiQueueDisabled() => 'disabled',
        UmamiQueueInMemory() => 'memory',
        UmamiQueuePersisted() => 'persisted',
      };
      expect(label, isNotEmpty);
    }
  });

  test('all subclasses support const construction', () {
    const disabled = UmamiQueueDisabled();
    const memory = UmamiQueueInMemory();
    const persisted = UmamiQueuePersisted();
    expect(disabled, isA<UmamiQueueConfig>());
    expect(memory, isA<UmamiQueueConfig>());
    expect(persisted, isA<UmamiQueueConfig>());
  });
}
