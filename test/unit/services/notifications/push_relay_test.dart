import 'package:apexo/services/notifications/push_relay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushRelay constants', () {
    test('relayServer is set', () {
      expect(PushRelay.relayServer, isNotEmpty);
      expect(PushRelay.relayServer, contains('workers.dev'));
    });

    test('relayKeyIDInCollection is set', () {
      expect(PushRelay.relayKeyIDInCollection, isNotEmpty);
      expect(PushRelay.relayKeyIDInCollection, 'notifications_k');
    });
  });

  group('PushRelay device flag', () {
    test('deviceIsPut defaults to false', () {
      expect(PushRelay.deviceIsPut, isFalse);
    });

    test('deviceIsPut can be toggled', () {
      PushRelay.deviceIsPut = true;
      expect(PushRelay.deviceIsPut, isTrue);
      PushRelay.deviceIsPut = false;
      expect(PushRelay.deviceIsPut, isFalse);
    });
  });
}
