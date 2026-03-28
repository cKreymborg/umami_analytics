import 'package:flutter_test/flutter_test.dart';
import 'package:umami_analytics/src/umami_logger.dart';

void main() {
  test('UmamiLogLevel has four values', () {
    expect(UmamiLogLevel.values, hasLength(4));
    expect(
        UmamiLogLevel.values,
        containsAll([
          UmamiLogLevel.debug,
          UmamiLogLevel.info,
          UmamiLogLevel.warning,
          UmamiLogLevel.error,
        ]));
  });

  test('UmamiLogger typedef accepts matching function', () {
    final List<String> logs = [];
    void logger(UmamiLogLevel level, String message) {
      logs.add('${level.name}: $message');
    }

    logger(UmamiLogLevel.info, 'test message');
    expect(logs, ['info: test message']);
  });
}
