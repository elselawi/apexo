// The insights screen (the `stats` feature): the charts, and the numbers behind
// them.
//
// The *drawings* are asserted through the chart widgets, and the *numbers*
// through the controller that feeds them (`chartsCtrl`) — reading a rendered
// subtitle back would mean parsing a localized sentence to get at a count.
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/stats/widgets/charts/bar.dart';
import 'package:apexo/features/stats/widgets/charts/line.dart';
import 'package:apexo/features/stats/widgets/charts/stacked.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

void registerInsightsTests() {
  group('insights', () {
    testWidgets('01: the charts render', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openInsights(tester);

      // The chart kinds the screen always draws (the money chart is behind the
      // revenue permission, so it is not asserted here).
      expect(find.byType(StyledBarChart), findsOneWidget,
          reason: 'the appointments bar chart did not render');
      expect(find.byType(StyledLineChart), findsWidgets,
          reason: 'the line charts did not render');
      expect(find.byType(StyledStackedChart), findsWidgets,
          reason: 'the stacked chart did not render');

      // The range selector, by the two ends it shows.
      expect(find.text(txt('start')), findsWidgets);
      expect(find.text(txt('end')), findsWidgets);
    });

    testWidgets('02: the appointment total follows the data', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openInsights(tester);
      final before = chartsCtrl.filteredAppointments.length;

      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now());

      // The window is a database read: the screen re-runs it on a committed
      // change, which is what keeps the charts honest.
      await Fixtures.openInsights(tester);
      expect(chartsCtrl.filteredAppointments.length, before + 1,
          reason: 'a booking made today did not reach the charts');
    });

    testWidgets('03: the period changes the numbers', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openInsights(tester);
      final perDay = chartsCtrl.periods.length;

      await Fixtures.setStatsInterval(tester, 'months');
      expect(chartsCtrl.interval(), StatsInterval.months,
          reason: 'the period switch did not take');
      expect(chartsCtrl.periods.length, isNot(perDay),
          reason: 'the chart periods did not change with the interval');
    });

    testWidgets('04: the calendar system changes the axis labels',
        (tester) async {
      // A setting (§2.9 `04`): the charts' labels come from the clinic's
      // calendar system, and switching it is that group's business.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('05: an empty clinic renders empty charts, not an error',
        (tester) async {
      // Needs a *fresh* database: the suite shares one, and by this point it has
      // appointments. Same reason `dashboard 06`/`07` are skipped.
      expect(true, isTrue);
    }, skip: true);
  });
}
