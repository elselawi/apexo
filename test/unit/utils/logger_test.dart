import 'package:apexo/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  group('logger', () {
    Future<List<LogRecord>> capture(void Function() action) async {
      final records = <LogRecord>[];
      final subscription = log.onRecord.listen(records.add);
      action();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      return records;
    }

    test('maps importance to exact levels and ANSI message colors', () async {
      final severe = await capture(() => logger('critical', null, 1));
      final warning = await capture(() => logger('warning', null, 2));
      final info = await capture(() => logger('info', null, 3));
      final fallback = await capture(() => logger('fallback', null));

      expect(severe.single.level, Level.SEVERE);
      expect(severe.single.message, '\x1B[31mcritical\x1B[0m');
      expect(warning.single.level, Level.WARNING);
      expect(warning.single.message, '\x1B[33mwarning\x1B[0m');
      expect(info.single.level, Level.INFO);
      expect(info.single.message, '\x1B[34minfo\x1B[0m');
      expect(fallback.single.level, Level.SEVERE);
      expect(fallback.single.message, '\x1B[31mfallback\x1B[0m');
    });

    test('emits a separate purple stack-trace record', () async {
      final trace = StackTrace.fromString('trace line');
      final records = await capture(() => logger('error', trace, 1));

      expect(records, hasLength(2));
      expect(records[1].level, Level.INFO);
      expect(records[1].message, '\n\x1B[35mSTACKTRACE:\ntrace line\x1B[0m');
    });

    test('logs very long objects without truncating the message', () async {
      final long = 'x' * 10000;
      final records = await capture(() => logger(long, null, 2));

      expect(records.single.message, '\x1B[33m$long\x1B[0m');
    });
  });
}
