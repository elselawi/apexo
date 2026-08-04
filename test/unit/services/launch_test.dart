import 'package:apexo/services/launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Open enum', () {
    test('has three values', () {
      expect(Open.values, [Open.login, Open.staff, Open.patient]);
    });
  });

  group('launch', () {
    late bool originalDialog;
    late bool originalFirstLaunch;
    late Open originalOpen;
    late bool originalOverlay;
    late double originalWidth;

    setUp(() {
      originalDialog = launch.dialogShown();
      originalFirstLaunch = launch.isFirstLaunch();
      originalOpen = launch.open();
      originalOverlay = launch.paneIsOverlaying();
      originalWidth = launch.layoutWidth;
    });

    tearDown(() {
      launch.dialogShown(originalDialog);
      launch.isFirstLaunch(originalFirstLaunch);
      launch.open(originalOpen);
      launch.paneIsOverlaying(originalOverlay);
      launch.layoutWidth = originalWidth;
    });

    test('singleton exists', () {
      expect(launch, isNotNull);
    });

    test('dialogShown defaults to false', () {
      expect(launch.dialogShown(), false);
    });

    test('dialogShown is settable', () {
      final prev = launch.dialogShown();
      launch.dialogShown(true);
      expect(launch.dialogShown(), true);
      launch.dialogShown(prev);
    });

    test('isFirstLaunch defaults to false', () {
      expect(launch.isFirstLaunch(), false);
    });

    test('isFirstLaunch is settable', () {
      final prev = launch.isFirstLaunch();
      launch.isFirstLaunch(true);
      expect(launch.isFirstLaunch(), true);
      launch.isFirstLaunch(prev);
    });

    test('isDemo is a bool', () {
      expect(launch.isDemo, isA<bool>());
    });

    test('open defaults to Open.login', () {
      expect(launch.open(), Open.login);
    });

    test('open transitions between modes', () {
      final prev = launch.open();

      launch.open(Open.staff);
      expect(launch.open(), Open.staff);

      launch.open(Open.patient);
      expect(launch.open(), Open.patient);

      launch.open(Open.login);
      expect(launch.open(), Open.login);

      launch.open(prev);
    });

    test('open notifies observers', () async {
      final prev = launch.open();
      bool notified = false;
      void observer(_) => notified = true;
      launch.open.observe(observer);
      addTearDown(() => launch.open.unObserve(observer));

      launch.open(Open.staff);
      await Future<void>.delayed(Duration.zero);
      expect(notified, true);

      launch.open(prev);
    });

    test('paneIsOverlaying defaults to false', () {
      expect(launch.paneIsOverlaying(), false);
    });

    test('paneIsOverlaying is settable', () {
      final prev = launch.paneIsOverlaying();
      launch.paneIsOverlaying(true);
      expect(launch.paneIsOverlaying(), true);
      launch.paneIsOverlaying(prev);
    });

    test('layoutWidth defaults to 0', () {
      expect(launch.layoutWidth, 0.0);
    });

    test('layoutWidth is settable', () {
      final prev = launch.layoutWidth;
      launch.layoutWidth = 800.0;
      expect(launch.layoutWidth, 800.0);
      launch.layoutWidth = prev;
    });
  });
}
