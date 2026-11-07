@Tags(['serial'])
library;

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppRouter router;
  late List<int> originalPermissions;
  late String originalToken;
  late bool originalOnline;
  late bool originalBookingReady;

  setUp(() async {
    await login.ready;
    originalPermissions = login.savedPermissions;
    originalToken = login.token;
    originalOnline = network.isOnline();
    originalBookingReady = booking.ready();
    login.token = '';
    login.savedPermissions = List<int>.of(Perm.full);
    network.isOnline(false);
    booking.ready(false);
    router = AppRouter();
  });

  tearDown(() {
    login.savedPermissions = originalPermissions;
    login.token = originalToken;
    network.isOnline(originalOnline);
    booking.ready(originalBookingReady);
  });

  test('back falls back to the first visible route after permission loss', () {
    router.navigateWithoutSync(AppRoute.patients);
    router.navigateWithoutSync(AppRoute.notes);
    login.savedPermissions = List<int>.of(Perm.zeroes);
    expect(router.visibleRoutes, isNot(contains(AppRoute.patients)));
    final originalStart = chartsCtrl.start();
    final originalEnd = chartsCtrl.end();
    final originalInterval = chartsCtrl.interval();
    addTearDown(() {
      chartsCtrl.start(originalStart);
      chartsCtrl.end(originalEnd);
      chartsCtrl.interval(originalInterval);
    });
    chartsCtrl.interval(StatsInterval.years);

    router.goBack();

    expect(chartsCtrl.interval(), StatsInterval.days,
        reason: 'the displayed dashboard must be synchronized');
    expect(router.currentRoute(), router.visibleRoutes.first);
    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.currentIndex, 0);
    expect(router.canGoBack, isTrue);
    router.goBack();
    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.canGoBack, isFalse);
  });

  test('back falls back if the booking session becomes unavailable', () {
    booking.ready(true);
    router.navigateWithoutSync(AppRoute.booking);
    router.navigateWithoutSync(AppRoute.notes);
    booking.ready(false);

    router.goBack();

    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.currentIndex, 0);
  });

  test('back restores an accessible entry and consumes history', () {
    router.navigateWithoutSync(AppRoute.notes);
    router.navigateWithoutSync(AppRoute.settings);

    router.goBack();
    expect(router.currentRoute(), AppRoute.notes);
    expect(router.canGoBack, isTrue);
    router.goBack();
    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.canGoBack, isFalse);
    router.goBack();
    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.canGoBack, isFalse);
  });

  test('navigate rejects inaccessible targets without adding history', () {
    login.savedPermissions = List<int>.of(Perm.zeroes);
    router.navigate(AppRoute.patients);
    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.canGoBack, isFalse);
  });
}
