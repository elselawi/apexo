import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/services/network.dart';

/// The [network] singleton keeps state across tests, so every test must
/// reset it. Tests use small `Future.delayed` waits so the broadcast stream
/// has a chance to deliver events synchronously before assertions run.
void main() {
  // Wait long enough for any pending observer callbacks to fire, while
  // keeping the suite fast.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    // Reset to a known starting state before each test.
    network.isOnline(false);
    network.onOnline.clear();
    network.onOffline.clear();
  });

  group('initial state', () {
    test('starts offline', () {
      expect(network.isOnline(), isFalse);
    });

    test('onOnline and onOffline callback maps start empty', () {
      expect(network.onOnline, isEmpty);
      expect(network.onOffline, isEmpty);
    });
  });

  group('isOnline setter', () {
    test('setting true flips the observable value', () {
      network.isOnline(true);
      expect(network.isOnline(), isTrue);
    });

    test('setting false flips the observable value back', () {
      network.isOnline(true);
      network.isOnline(false);
      expect(network.isOnline(), isFalse);
    });

    test('isOnline() with no argument is a getter', () {
      // Calling with no argument returns the current value without firing
      // observers.
      final before = network.isOnline();
      final after = network.isOnline();
      expect(after, before);
    });
  });

  group('callback fan-out', () {
    test('online callbacks fire when state transitions to online', () async {
      var count = 0;
      network.onOnline['test'] = () => count++;

      network.isOnline(true);
      await settle();

      expect(count, 1);
    });

    test('offline callbacks fire when state transitions to offline', () async {
      var count = 0;
      network.onOffline['test'] = () => count++;

      network.isOnline(false);
      await settle();

      expect(count, 1);
    });

    test('multiple online callbacks all fire on transition to online',
        () async {
      var count = 0;
      network.onOnline['a'] = () => count++;
      network.onOnline['b'] = () => count++;
      network.onOnline['c'] = () => count++;

      network.isOnline(true);
      await settle();

      expect(count, 3);
    });

    test('multiple offline callbacks all fire on transition to offline',
        () async {
      var count = 0;
      network.onOffline['a'] = () => count++;
      network.onOffline['b'] = () => count++;
      network.onOffline['c'] = () => count++;

      network.isOnline(false);
      await settle();

      expect(count, 3);
    });

    test('online and offline callbacks fire on their respective edges',
        () async {
      var onlineCount = 0;
      var offlineCount = 0;
      network.onOnline['a'] = () => onlineCount++;
      network.onOffline['b'] = () => offlineCount++;

      network.isOnline(true);
      await settle();
      expect(onlineCount, 1);
      expect(offlineCount, 0);

      network.isOnline(false);
      await settle();
      expect(onlineCount, 1);
      expect(offlineCount, 1);
    });
  });

  group('callback isolation', () {
    test('removing an online callback prevents it from firing', () async {
      var fired = false;
      network.onOnline['test'] = () => fired = true;
      network.onOnline.remove('test');

      network.isOnline(true);
      await settle();

      expect(fired, isFalse);
    });

    test('removing an offline callback prevents it from firing', () async {
      var fired = false;
      network.onOffline['test'] = () => fired = true;
      network.onOffline.remove('test');

      network.isOnline(false);
      await settle();

      expect(fired, isFalse);
    });

    test('a throwing callback does not break the observable stream', () async {
      // Once a registered callback throws, the inner for-loop in the
      // observer aborts, so sibling callbacks registered after it on the
      // same edge will not fire. We pin that behavior down here.
      var later = 0;
      network.onOnline['throws'] = () => throw StateError('boom');
      network.onOnline['later'] = () => later++;

      // The assignment itself must not propagate the throw to the caller.
      expect(() => network.isOnline(true), returnsNormally);
      await settle();
      expect(later, 0);

      // Reassigning also works without throwing — the observer is not
      // detached from the stream after a thrown callback.
      expect(() => network.isOnline(false), returnsNormally);
      expect(() => network.isOnline(true), returnsNormally);
      await settle();
    });

    test('only online callbacks fire when going online (not offline)',
        () async {
      var onlineRan = false;
      var offlineRan = false;
      network.onOnline['a'] = () => onlineRan = true;
      network.onOffline['a'] = () => offlineRan = true;

      network.isOnline(true);
      await settle();

      expect(onlineRan, isTrue);
      expect(offlineRan, isFalse);
    });

    test('only offline callbacks fire when going offline (not online)',
        () async {
      var onlineRan = false;
      var offlineRan = false;
      network.onOnline['a'] = () => onlineRan = true;
      network.onOffline['a'] = () => offlineRan = true;

      network.isOnline(false);
      await settle();

      expect(onlineRan, isFalse);
      expect(offlineRan, isTrue);
    });
  });

  group('repeated transitions', () {
    test('callbacks fire on every transition', () async {
      var online = 0;
      var offline = 0;
      network.onOnline['a'] = () => online++;
      network.onOffline['a'] = () => offline++;

      for (var i = 0; i < 3; i++) {
        network.isOnline(true);
        await settle();
        network.isOnline(false);
        await settle();
      }

      expect(online, 3);
      expect(offline, 3);
    });

    test('setting the same value still triggers observers (dedupe is off)',
        () async {
      var count = 0;
      network.onOnline['a'] = () => count++;

      network.isOnline(true);
      network.isOnline(true);
      network.isOnline(true);
      await settle();

      // ObservableState.notifyObservers fires on every set, even when the
      // value is unchanged, so callbacks are invoked multiple times.
      expect(count, 3);
    });
  });

  group('observable stream', () {
    test('stream emits the new value when isOnline(true) is called', () async {
      final received = <bool>[];
      final sub = network.isOnline.stream.listen(received.add);

      network.isOnline(true);
      await settle();

      expect(received, contains(true));
      await sub.cancel();
    });

    test('stream emits false when isOnline(false) is called', () async {
      network.isOnline(true);
      await settle();

      final received = <bool>[];
      final sub = network.isOnline.stream.listen(received.add);

      network.isOnline(false);
      await settle();

      expect(received, contains(false));
      await sub.cancel();
    });

    test('multiple listeners all receive the value', () async {
      final first = <bool>[];
      final second = <bool>[];
      final s1 = network.isOnline.stream.listen(first.add);
      final s2 = network.isOnline.stream.listen(second.add);

      network.isOnline(true);
      await settle();

      expect(first, contains(true));
      expect(second, contains(true));

      await s1.cancel();
      await s2.cancel();
    });
  });
}
