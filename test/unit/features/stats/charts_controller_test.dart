import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../../helpers/model_factory.dart';

void main() {
  final injectedApptIds = <String>{};
  final injectedPatientIds = <String>{};
  final injectedExpenseIds = <String>{};
  late List<int> originalPerms;

  void cleanUp() {
    for (final id in injectedApptIds) {
      if (appointments.has(id)) appointments.archive(id);
    }
    for (final id in injectedPatientIds) {
      if (patients.has(id)) patients.archive(id);
    }
    for (final id in injectedExpenseIds) {
      if (expenses.has(id)) expenses.archive(id);
    }
    injectedApptIds.clear();
    injectedPatientIds.clear();
    injectedExpenseIds.clear();
  }

  setUpAll(() async {
    // initializeDateFormatting is required by _ChartsController._getLabel
    // which constructs DateFormat(pattern, locale.s.$code) for non-days
    // intervals (weeks, months, quarters, years).
    await initializeDateFormatting('en', null);
    await initializeDateFormatting('ar', null);
    await initializeDateFormatting('es', null);
    await initializeDateFormatting('el', null);
    await initializeDateFormatting('fa', null);

    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });

  setUp(() {
    appointments.nullifyAppointmentsCache(null);
    login.savedPermissions = Perm.full;
  });

  tearDown(cleanUp);
  tearDownAll(() {
    login.savedPermissions = originalPerms;
  });

  Future<void> flushObservers() => Future.microtask(() {});

  group('Charts controller — singleton & defaults', () {
    test('chartsCtrl singleton exists', () {
      expect(chartsCtrl, isNotNull);
    });

    test('filterByOperatorID defaults to empty string', () {
      chartsCtrl.filterByOperatorID('');
      expect(chartsCtrl.filterByOperatorID(), isEmpty);
    });

    test('start defaults to first day of current month', () {
      final now = DateTime.now();
      chartsCtrl.resetSelected();
      final expectedStart = DateTime(now.year, now.month, 1);
      expect(chartsCtrl.start().year, expectedStart.year);
      expect(chartsCtrl.start().month, expectedStart.month);
      expect(chartsCtrl.start().day, expectedStart.day);
    });

    test('end defaults to 31 days after start', () {
      final now = DateTime.now();
      chartsCtrl.resetSelected();
      final expectedEnd =
          DateTime(now.year, now.month, 1).add(const Duration(days: 31));
      expect(chartsCtrl.end().difference(expectedEnd).inDays, 0);
    });

    test('interval defaults to StatsInterval.days', () {
      chartsCtrl.resetSelected();
      expect(chartsCtrl.interval(), StatsInterval.days);
    });

    test('StatsInterval enum has 5 values', () {
      expect(StatsInterval.values, [
        StatsInterval.days,
        StatsInterval.weeks,
        StatsInterval.months,
        StatsInterval.quarters,
        StatsInterval.years
      ]);
    });

    test('intervalString returns the current interval name', () {
      chartsCtrl.interval(StatsInterval.weeks);
      expect(chartsCtrl.intervalString, 'weeks');
      chartsCtrl.interval(StatsInterval.months);
      expect(chartsCtrl.intervalString, 'months');
      chartsCtrl.interval(StatsInterval.days);
    });
  });

  group('Charts controller — filtered', () {
    test('filteredAppointments is a list', () async {
      await flushObservers();
      expect(chartsCtrl.filteredAppointments, isA<List<Appointment>>());
    });

    test('date range includes exact start and end boundaries', () async {
      final patient = testPatient(id: 'charts-boundary-patient');
      patients.set(patient);
      injectedPatientIds.add(patient.id);
      chartsCtrl.interval(StatsInterval.days);
      chartsCtrl.start(DateTime(2025, 1, 1));
      chartsCtrl.end(DateTime(2025, 1, 2, 23, 59, 59, 999));

      final atStart = testAppointment(
        id: 'charts-at-start',
        patientID: patient.id,
        date: DateTime(2025, 1, 1),
      );
      final atEnd = testAppointment(
        id: 'charts-at-end',
        patientID: patient.id,
        date: DateTime(2025, 1, 2, 23, 59),
      );
      final afterEnd = testAppointment(
        id: 'charts-after-end',
        patientID: patient.id,
        date: DateTime(2025, 1, 3),
      );
      appointments.setAll([atStart, atEnd, afterEnd]);
      injectedApptIds.addAll([atStart.id, atEnd.id, afterEnd.id]);

      await flushObservers();
      expect(chartsCtrl.filteredAppointments.map((a) => a.id),
          ['charts-at-start', 'charts-at-end']);
    });

    test('archived appointments and receipts are excluded', () async {
      chartsCtrl.interval(StatsInterval.days);
      chartsCtrl.start(DateTime(2025, 1, 1));
      chartsCtrl.end(DateTime(2025, 1, 31, 23, 59, 59));

      final archivedAppointment = testAppointment(
        id: 'charts-archived-appointment',
        date: DateTime(2025, 1, 10),
        archived: true,
      );
      final archivedExpense = testExpense(
        id: 'charts-archived-expense',
        date: DateTime(2025, 1, 10),
        cost: 500,
        archived: true,
      );
      appointments.set(archivedAppointment);
      expenses.set(archivedExpense);
      injectedApptIds.add(archivedAppointment.id);
      injectedExpenseIds.add(archivedExpense.id);

      await flushObservers();
      expect(chartsCtrl.filteredAppointments,
          isNot(contains(archivedAppointment)));
      expect(chartsCtrl.filteredReceipts, isNot(contains(archivedExpense)));
    });

    test('filteredReceipts is a list', () {
      expect(chartsCtrl.filteredReceipts, isA<List>());
    });

    test('filteredAppointments respects date range', () async {
      final p = testPatient(id: 'charts-pt-range');
      patients.set(p);
      injectedPatientIds.add(p.id);

      // Set a custom range
      chartsCtrl.interval(StatsInterval.days);
      chartsCtrl.start(DateTime(2025, 1, 1));
      chartsCtrl.end(DateTime(2025, 1, 31));

      final inRange = testAppointment(
        id: 'appt-in',
        patientID: p.id,
        date: DateTime(2025, 1, 15),
      );
      final outOfRange = testAppointment(
        id: 'appt-out',
        patientID: p.id,
        date: DateTime(2025, 6, 1),
      );
      appointments.set(inRange);
      appointments.set(outOfRange);
      injectedApptIds.addAll([inRange.id, outOfRange.id]);

      await flushObservers();
      final res = chartsCtrl.filteredAppointments;
      expect(res.any((a) => a.id == inRange.id), isTrue);
      expect(res.any((a) => a.id == outOfRange.id), isFalse);
    });

    test('filteredAppointments filters by operator when filter set', () async {
      final p = testPatient(id: 'charts-pt-op');
      patients.set(p);
      injectedPatientIds.add(p.id);

      chartsCtrl.resetSelected();
      chartsCtrl.filterByOperatorID('op-alpha');

      final withOp = testAppointment(
        id: 'appt-op-in',
        patientID: p.id,
        date: DateTime.now(),
        operatorsIDs: ['op-alpha'],
      );
      final withoutOp = testAppointment(
        id: 'appt-op-out',
        patientID: p.id,
        date: DateTime.now(),
        operatorsIDs: ['op-beta'],
      );
      appointments.set(withOp);
      appointments.set(withoutOp);
      injectedApptIds.addAll([withOp.id, withoutOp.id]);

      await flushObservers();
      final res = chartsCtrl.filteredAppointments;
      expect(res.any((a) => a.id == withOp.id), isTrue);
      expect(res.any((a) => a.id == withoutOp.id), isFalse);

      chartsCtrl.filterByOperatorID('');
    });
  });

  group('Charts controller — distributions', () {
    test('timeOfDayDistribution has 24 slots', () async {
      await flushObservers();
      expect(chartsCtrl.timeOfDayDistribution.length, 24);
    });

    test('dayOfMonthDistribution has 31 slots', () async {
      await flushObservers();
      expect(chartsCtrl.dayOfMonthDistribution.length, 31);
    });

    test('dayOfWeekDistribution has 7 slots', () async {
      await flushObservers();
      expect(chartsCtrl.dayOfWeekDistribution.length, 7);
    });

    test('monthOfYearDistribution has 12 slots', () async {
      await flushObservers();
      expect(chartsCtrl.monthOfYearDistribution.length, 12);
    });

    test('femaleMale has 2 slots defaulting to 0', () async {
      await flushObservers();
      final fm = chartsCtrl.femaleMale;
      expect(fm.length, 2);
      // Both should be ints
      expect(fm[0], isA<int>());
      expect(fm[1], isA<int>());
    });

    test('timeOfDayDistribution increments slot for matching appt', () async {
      final p = testPatient(id: 'charts-pt-tod');
      patients.set(p);
      injectedPatientIds.add(p.id);

      chartsCtrl.resetSelected();

      final morning = DateTime.now();
      final atHour = DateTime(morning.year, morning.month, morning.day, 9, 0);

      final appt = testAppointment(
        id: 'appt-tod',
        patientID: p.id,
        date: atHour,
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      await flushObservers();
      final dist = chartsCtrl.timeOfDayDistribution;
      // Slot 9 should be > 0
      expect(dist[9], greaterThan(0));
    });
  });

  group('Charts controller — periods', () {
    test('periods is non-empty for current month range', () {
      chartsCtrl.resetSelected();
      final ps = chartsCtrl.periods;
      expect(ps, isNotEmpty);
      for (final p in ps) {
        expect(p.start, isA<DateTime>());
        expect(p.end, isA<DateTime>());
        expect(p.label, isA<String>());
      }
    });

    test('periods respects interval=days producing daily buckets', () {
      chartsCtrl.resetSelected();
      chartsCtrl.interval(StatsInterval.days);
      final ps = chartsCtrl.periods;
      // 31 days → at least 31 period buckets
      expect(ps.length, greaterThanOrEqualTo(28));
    });

    test('periods respects interval=weeks producing ~5 buckets', () {
      chartsCtrl.resetSelected();
      chartsCtrl.interval(StatsInterval.weeks);
      final ps = chartsCtrl.periods;
      // 31 days = ~5 weeks
      expect(ps.length, greaterThanOrEqualTo(4));
      expect(ps.length, lessThanOrEqualTo(7));
    });

    test('resetSelected restores current-month range', () {
      // Move away first
      chartsCtrl.start(DateTime(2020, 1, 1));
      expect(chartsCtrl.start().year, 2020);

      chartsCtrl.resetSelected();
      final now = DateTime.now();
      expect(chartsCtrl.start().year, now.year);
      expect(chartsCtrl.start().month, now.month);
      expect(chartsCtrl.start().day, 1);
    });
  });

  group('Charts controller — date math helpers (via observable behavior)', () {
    test('_daysSinceMonthStart logic: first of month => period start == date',
        () {
      chartsCtrl.resetSelected();
      chartsCtrl.interval(StatsInterval.months);
      final ps = chartsCtrl.periods;
      // The first period's start should be the first of the month
      expect(ps.first.start.day, 1);
    });

    test('_daysSinceYearStart logic: Jan 1 normalizes to itself', () {
      chartsCtrl.resetSelected();
      final now = DateTime.now();
      chartsCtrl.start(DateTime(now.year, 1, 1));
      chartsCtrl.end(DateTime(now.year, 1, 31));
      chartsCtrl.interval(StatsInterval.years);
      final ps = chartsCtrl.periods;
      // For years interval, the period starts at Jan 1 of the year
      expect(ps.first.start.month, 1);
      expect(ps.first.start.day, 1);
    });

    test('_daysSinceQuarterStart: Q1 normalizes to Jan 1', () {
      chartsCtrl.resetSelected();
      final now = DateTime.now();
      chartsCtrl.start(DateTime(now.year, 1, 15));
      chartsCtrl.end(DateTime(now.year, 1, 31));
      chartsCtrl.interval(StatsInterval.quarters);
      final ps = chartsCtrl.periods;
      expect(ps.first.start.month, 1);
      expect(ps.first.start.day, 1);
    });
  });

  group('Charts controller — empty state', () {
    test('groupedAppointments returns list of lists per period', () async {
      chartsCtrl.resetSelected();
      await flushObservers();
      final ga = chartsCtrl.groupedAppointments;
      expect(ga, isA<List<List<Appointment>>>());
      expect(ga.length, chartsCtrl.periods.length);
    });

    test('groupedPayments returns list of doubles per period', () async {
      chartsCtrl.resetSelected();
      await flushObservers();
      final gp = chartsCtrl.groupedPayments;
      expect(gp, isA<List<double>>());
      expect(gp.length, chartsCtrl.periods.length);
    });

    test('groupedExpenses returns list of doubles per period', () async {
      chartsCtrl.resetSelected();
      await flushObservers();
      final ge = chartsCtrl.groupedExpenses;
      expect(ge, isA<List<double>>());
      expect(ge.length, chartsCtrl.periods.length);
    });

    test('doneAndMissedAppointments returns list of [done, missed] per period',
        () async {
      chartsCtrl.resetSelected();
      await flushObservers();
      final dm = chartsCtrl.doneAndMissedAppointments;
      expect(dm, isA<List<List<double>>>());
      for (final pair in dm) {
        expect(pair.length, 2);
      }
    });

    test('newPatients returns list of doubles per period', () async {
      chartsCtrl.resetSelected();
      await flushObservers();
      final np = chartsCtrl.newPatients;
      expect(np, isA<List<double>>());
      expect(np.length, chartsCtrl.periods.length);
    });
  });

  group('Charts controller — exact aggregations', () {
    test('groups appointments, payments, and expenses into daily buckets',
        () async {
      final patient = testPatient(id: 'charts-total-patient', gender: 1);
      patients.set(patient);
      injectedPatientIds.add(patient.id);

      chartsCtrl.interval(StatsInterval.days);
      chartsCtrl.start(DateTime(2025, 2, 1));
      chartsCtrl.end(DateTime(2025, 2, 2, 23, 59, 59));

      final first = testAppointment(
        id: 'charts-total-first',
        patientID: patient.id,
        date: DateTime(2025, 2, 1, 9),
        paid: 30,
        isDone: true,
      );
      final second = testAppointment(
        id: 'charts-total-second',
        patientID: patient.id,
        date: DateTime(2025, 2, 2, 15),
        paid: 70,
      );
      final receipt = testExpense(
        id: 'charts-total-expense',
        date: DateTime(2025, 2, 2, 12),
        cost: 45,
      );
      appointments.setAll([first, second]);
      expenses.set(receipt);
      injectedApptIds.addAll([first.id, second.id]);
      injectedExpenseIds.add(receipt.id);

      await flushObservers();
      expect(
          chartsCtrl.groupedAppointments
              .map((bucket) => bucket.map((a) => a.id).toList()),
          [
            ['charts-total-first'],
            ['charts-total-second'],
          ]);
      expect(chartsCtrl.groupedPayments, [30.0, 70.0]);
      expect(chartsCtrl.groupedExpenses, [0.0, 45.0]);
      expect(chartsCtrl.doneAndMissedAppointments, [
        [1.0, 0.0],
        [0.0, 1.0],
      ]);
      expect(chartsCtrl.timeOfDayDistribution[9], 1.0);
      expect(chartsCtrl.timeOfDayDistribution[15], 1.0);
      expect(chartsCtrl.dayOfMonthDistribution[0], 1.0);
      expect(chartsCtrl.dayOfMonthDistribution[1], 1.0);
      expect(chartsCtrl.monthOfYearDistribution[1], 2.0);
      expect(chartsCtrl.femaleMale, [0, 2]);
    });

    test('store mutations invalidate cached filtered results', () async {
      chartsCtrl.interval(StatsInterval.days);
      chartsCtrl.start(DateTime(2025, 3, 1));
      chartsCtrl.end(DateTime(2025, 3, 1, 23, 59, 59));
      expect(chartsCtrl.filteredAppointments, isEmpty);
      expect(chartsCtrl.filteredReceipts, isEmpty);

      final appointment = testAppointment(
        id: 'charts-cache-appointment',
        date: DateTime(2025, 3, 1, 10),
        paid: 20,
      );
      final receipt = testExpense(
        id: 'charts-cache-expense',
        date: DateTime(2025, 3, 1, 11),
        cost: 10,
      );
      appointments.set(appointment);
      expenses.set(receipt);
      injectedApptIds.add(appointment.id);
      injectedExpenseIds.add(receipt.id);
      await flushObservers();

      expect(chartsCtrl.filteredAppointments.map((a) => a.id),
          ['charts-cache-appointment']);
      expect(chartsCtrl.filteredReceipts.map((e) => e.id),
          ['charts-cache-expense']);
    });
  });

  group('Charts controller — interval toggle methods', () {
    test('setIntervalToDays sets interval to days', () {
      chartsCtrl.setIntervalToWeeks();
      expect(chartsCtrl.interval(), StatsInterval.weeks);
      chartsCtrl.setIntervalToDays();
      expect(chartsCtrl.interval(), StatsInterval.days);
    });

    test('setIntervalToWeeks sets interval to weeks', () {
      chartsCtrl.setIntervalToWeeks();
      expect(chartsCtrl.interval(), StatsInterval.weeks);
    });

    test('setIntervalToMonths sets interval to months', () {
      chartsCtrl.setIntervalToMonths();
      expect(chartsCtrl.interval(), StatsInterval.months);
    });

    test('setIntervalToQuarters sets interval to quarters', () {
      chartsCtrl.setIntervalToQuarters();
      expect(chartsCtrl.interval(), StatsInterval.quarters);
    });

    test('setIntervalToYears sets interval to years', () {
      chartsCtrl.setIntervalToYears();
      expect(chartsCtrl.interval(), StatsInterval.years);
    });

    test('toggleInterval cycles through enums with wrap', () {
      chartsCtrl.interval(StatsInterval.days);
      chartsCtrl.toggleInterval();
      expect(chartsCtrl.interval(), StatsInterval.weeks);
      chartsCtrl.toggleInterval();
      expect(chartsCtrl.interval(), StatsInterval.months);
      chartsCtrl.toggleInterval();
      expect(chartsCtrl.interval(), StatsInterval.quarters);
      chartsCtrl.toggleInterval();
      expect(chartsCtrl.interval(), StatsInterval.years);
      chartsCtrl.toggleInterval(); // wrap to start
      expect(chartsCtrl.interval(), StatsInterval.days);
    });

    test('filterByOperator(null) clears the operator filter', () {
      chartsCtrl.filterByOperatorID('temp');
      expect(chartsCtrl.filterByOperatorID(), 'temp');
      chartsCtrl.filterByOperator(null);
      expect(chartsCtrl.filterByOperatorID(), isEmpty);
    });
  });
}
