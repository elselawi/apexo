// The dashboard: the counts the shell lands on, and the lists behind them.
//
// Everything here is measured as a **delta**: the tests share one database and
// the reset happens once per run, so "the count went up by one" is the honest
// assertion (and the reason each test seeds its own record).
//
// The squares come in two shapes, which is why the fixtures differ:
//   top squares  — one number (`appointmentsToday`, `newPatientsToday`,
//                  `paymentsToday`), keyed `WK.dashboardCount(id)`;
//   list squares — a titled list with its own action button
//                  (`patientsToday`, `labworksDue`, `labworksUndelivered`,
//                  `expensesDue`), keyed `WK.dashboardSquare(id)`.
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

void registerDashboardTests() {
  group('dashboard', () {
    testWidgets('01: the dashboard renders its squares', (tester) async {
      await E2E.signIn(tester);

      // The top squares.
      for (final id in ['appointmentsToday', 'newPatientsToday']) {
        await E2E.waitFor(tester, find.byKey(WK.dashboardCount(id)),
            description: 'the "$id" square');
        expect(Fixtures.squareCount(tester, id), isNotNull,
            reason: 'the "$id" square does not show a number');
      }
      // The list squares, by the titles they carry.
      for (final title in [
        txt('patientsToday'),
        txt('labworks'),
        txt('expenses'),
      ]) {
        expect(find.textContaining(title), findsWidgets,
            reason: 'the dashboard has no "$title" square');
      }
    });

    testWidgets("02: today's appointment count follows a booking",
        (tester) async {
      await E2E.signIn(tester);
      final before = Fixtures.squareCount(tester, 'appointmentsToday') ?? 0;

      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now());

      await Fixtures.openDashboard(tester);
      expect(Fixtures.squareCount(tester, 'appointmentsToday'), before + 1,
          reason: "a visit booked for today is not counted today");
    });

    testWidgets('03: the new-patients square follows a first visit',
        (tester) async {
      await E2E.signIn(tester);
      final before = Fixtures.squareCount(tester, 'newPatientsToday') ?? 0;

      // A patient with no earlier visit, booked for today: that is what the
      // square counts.
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now());

      await Fixtures.openDashboard(tester);
      expect(Fixtures.squareCount(tester, 'newPatientsToday'), before + 1,
          reason: "a patient's first visit today is not counted");
    });

    testWidgets('04: the expenses square lists what a supplier owes',
        (tester) async {
      final name = Fixtures.stamp('e2e supplier');
      await E2E.signIn(tester);
      await Fixtures.createSupplier(tester, name);
      await Fixtures.openSupplier(tester, name);
      await Fixtures.addOrder(tester, cost: '90');
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openDashboard(tester);
      final square = find.byKey(WK.dashboardSquare('expensesDue'));
      await E2E.waitFor(tester, square, description: 'the expenses square');
      expect(
        find.descendant(of: square, matching: find.text(name)),
        findsOneWidget,
        reason: 'a supplier with an open order is not on the dashboard',
      );
      expect(Fixtures.squareItems(tester, 'expensesDue'), greaterThan(0),
          reason: 'the expenses square is empty');
    });

    testWidgets('05: a square opens the screen it counts', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openDashboard(tester);

      // The expenses square goes to the expenses screen…
      await Fixtures.tapSquare(tester, 'expensesDue');
      await E2E.waitFor(tester, find.byKey(WK.btnNewSupplier),
          description: 'the expenses screen');
      // …and the labworks one to the labworks screen.
      await Fixtures.openDashboard(tester);
      await Fixtures.tapSquare(tester, 'labworksDue');
      await E2E.waitFor(tester, find.byKey(WK.btnNewLabwork),
          description: 'the labworks screen');
    });

    // Skipped: changing the currency means writing the settings store through
    // the settings screen, which is §2.9's surface (this group is about the
    // squares). The square already renders `MoneyDisplay` with the currency the
    // screen read once.
    testWidgets('06: money totals use the clinic currency', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openDashboard(tester);
      expect(Fixtures.squareText(tester, 'paymentsToday'), isNotNull);
    }, skip: true);

    // Skipped: an empty clinic needs a *fresh* database, and the run resets its
    // state once, on the first boot (todo.md §4.3) — every test after that one
    // sees the records the earlier tests created. The empty-state path is a
    // separate run, not a test in this group.
    testWidgets('07: an empty clinic shows zeros, not spinners',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openDashboard(tester);
      expect(Fixtures.squareCount(tester, 'appointmentsToday'), 0);
    }, skip: true);
  });
}
