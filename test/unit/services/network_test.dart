import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/services/network.dart';

void main() {
  group('Network Service Tests', () {
    test('Initial network state should be offline', () {
      expect(network.isOnline(), false);
    });

    test('Online callbacks should trigger when network becomes online', () async {
      int callbackCount = 0;
      network.onOnline['test'] = () {
        callbackCount++;
      };

      network.isOnline(true);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(callbackCount, 1);
    });

    test('Offline callbacks should trigger when network becomes offline', () async {
      int callbackCount = 0;
      network.onOffline['test'] = () {
        callbackCount++;
      };

      network.isOnline(false);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(callbackCount, 1);
    });

    test('Multiple callbacks should all trigger on network change', () async {
      int onlineCount = 0;
      int offlineCount = 0;

      network.onOnline['test1'] = () => onlineCount++;
      network.onOnline['test2'] = () => onlineCount++;
      network.onOffline['test1'] = () => offlineCount++;
      network.onOffline['test2'] = () => offlineCount++;

      network.isOnline(true);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(onlineCount, 2);

      network.isOnline(false);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(offlineCount, 2);
    });
  });
}
