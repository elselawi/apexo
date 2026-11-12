@Tags(['serial'])
library;

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

void main() {
  late AppRouter router;
  late List<int> originalPermissions;
  late String originalToken;
  late bool originalOnline;
  late bool originalBookingReady;
  late String originalNotesChoice;
  late List<Note> originalNotes;

  setUp(() async {
    await login.ready;
    originalPermissions = login.savedPermissions;
    originalToken = login.token;
    originalOnline = network.isOnline();
    originalBookingReady = booking.ready();
    originalNotesChoice = globalSettings.notesFeatureChoice;
    originalNotes = notes.docs.values.toList();
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
    globalSettings.notesFeatureChoice = originalNotesChoice;
    notes.observableMap.clear();
    notes.setAll(originalNotes);
  });

  test('back falls back to the first visible route after permission loss', () {
    router.navigateWithoutSync(AppRoute.patients);
    router.navigateWithoutSync(AppRoute.settings);
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
    router.navigateWithoutSync(AppRoute.settings);
    booking.ready(false);

    router.goBack();

    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.currentIndex, 0);
  });

  test('back restores an accessible entry and consumes history', () {
    router.navigateWithoutSync(AppRoute.patients);
    router.navigateWithoutSync(AppRoute.settings);

    router.goBack();
    expect(router.currentRoute(), AppRoute.patients);
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

  test('an optional feature is offered only while it is on or has data', () {
    globalSettings.notesFeatureChoice = '';
    notes.observableMap.clear();
    expect(router.visibleRoutes, isNot(contains(AppRoute.notes)));

    notes.set(testNote(id: 'n1'));
    expect(router.visibleRoutes, contains(AppRoute.notes),
        reason: 'a clinic that already has notes keeps its screen');

    notes.observableMap.clear();
    globalSettings.notesFeatureChoice = '1';
    expect(router.visibleRoutes, contains(AppRoute.notes));

    globalSettings.notesFeatureChoice = '0';
    expect(router.visibleRoutes, isNot(contains(AppRoute.notes)),
        reason: 'an explicit off wins, even once the feature has data');
  });

  test('an optional feature still obeys its permission', () {
    expenses.observableMap.clear();
    globalSettings.expensesFeatureChoice = '1';
    addTearDown(() {
      globalSettings.expensesFeatureChoice = '';
      expenses.observableMap.clear();
    });
    expect(router.visibleRoutes, contains(AppRoute.expenses));

    final permissions = List<int>.of(Perm.full);
    permissions[Perm.expenses] = 0;
    login.savedPermissions = permissions;

    expect(router.visibleRoutes, isNot(contains(AppRoute.expenses)),
        reason: 'switching the feature on does not grant its permission');
  });

  test('switching an optional feature off takes its screen away', () async {
    notes.observableMap.clear();
    globalSettings.notesFeatureChoice = '1';
    router.navigateWithoutSync(AppRoute.notes);
    expect(router.currentRoute(), AppRoute.notes);

    globalSettings.notesFeatureChoice = '0';
    // Observers are dispatched asynchronously, like a real settings sync.
    await Future<void>.delayed(Duration.zero);

    expect(router.currentRoute(), AppRoute.dashboard);
    expect(router.canGoBack, isFalse);
    expect(router.currentIndex, 0);
  });
}
