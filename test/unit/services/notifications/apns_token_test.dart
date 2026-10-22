import 'package:apexo/services/notifications/apns_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('waitForAPNSToken', () {
    test('returns the first token it reads, without waiting', () async {
      var reads = 0;
      final waits = <Duration>[];

      final token = await waitForAPNSToken(
        () async {
          reads++;
          return 'apns-token';
        },
        wait: (duration) async => waits.add(duration),
      );

      expect(token, 'apns-token');
      expect(reads, 1);
      expect(waits, isEmpty);
    });

    test('retries until the system registers with APNs', () async {
      var reads = 0;
      final waits = <Duration>[];

      final token = await waitForAPNSToken(
        () async {
          reads++;
          return reads < 4 ? null : 'apns-token';
        },
        attempts: 10,
        interval: const Duration(milliseconds: 500),
        wait: (duration) async => waits.add(duration),
      );

      expect(token, 'apns-token');
      expect(reads, 4);
      expect(waits, everyElement(const Duration(milliseconds: 500)));
      expect(waits, hasLength(3));
    });

    test('treats an empty token as not issued yet', () async {
      final reads = <int>[];
      var attempt = 0;

      final token = await waitForAPNSToken(
        () async {
          attempt++;
          reads.add(attempt);
          return attempt == 1 ? '' : 'apns-token';
        },
        attempts: 2,
        wait: (duration) async {},
      );

      expect(token, 'apns-token');
      expect(reads, [1, 2]);
    });

    test('gives up after the last attempt without waiting again', () async {
      var reads = 0;
      var waits = 0;

      final token = await waitForAPNSToken(
        () async {
          reads++;
          return null;
        },
        attempts: 3,
        wait: (duration) async => waits++,
      );

      expect(token, isNull);
      expect(reads, 3);
      expect(waits, 2);
    });

    test('never reads a token when it is allowed no attempts', () async {
      var reads = 0;

      final token = await waitForAPNSToken(
        () async {
          reads++;
          return 'apns-token';
        },
        attempts: 0,
        wait: (duration) async {},
      );

      expect(token, isNull);
      expect(reads, 0);
    });

    test('defaults to ten attempts half a second apart', () {
      expect(apnsTokenAttempts, 10);
      expect(apnsTokenRetryInterval, const Duration(milliseconds: 500));
    });
  });
}
