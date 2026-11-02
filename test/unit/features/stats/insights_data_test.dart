@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/stats/insights_data.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

void main() {
  final periods = [
    Period(
        DateTime(2024, 1, 1), DateTime(2024, 1, 1, 23, 59, 59, 999), 'Jan 1'),
    Period(
        DateTime(2024, 1, 2), DateTime(2024, 1, 2, 23, 59, 59, 999), 'Jan 2'),
  ];

  test('empty range has finite zero totals and cumulative data', () {
    final data = InsightsData(periods: [], appointments: [], receipts: []);
    expect(data.totalAppointments, 0);
    expect(data.completionRate, 0);
    expect(data.uniquePatients, 0);
    expect(data.cashFlow, isEmpty);
    expect(data.scheduledHours, isEmpty);
    expect(data.completedHours, isEmpty);
    expect(data.returningVisits, isEmpty);
    expect(data.completedCharges, isEmpty);
    expect(data.completedPayments, isEmpty);
    expect(data.debtByAge, [0, 0, 0, 0]);
    expect(InsightsData.cumulative([]), isEmpty);
    expect(InsightsData.sum([]), 0);
  });

  test(
      'groups boundaries, preserves negative cash flow and clamps debt per visit',
      () {
    final data = InsightsData(periods: periods, appointments: [
      testAppointment(
          date: DateTime(2024, 1, 1), price: 100, paid: 40, isDone: true),
      testAppointment(
          date: DateTime(2024, 1, 2, 23, 59), price: 100, paid: 150),
      testAppointment(date: DateTime(2024, 1, 2, 12), price: 80, paid: 20),
      testAppointment(date: DateTime(2024, 1, 3), paid: 500),
      testAppointment(date: DateTime(2023, 12, 31), paid: 500),
    ], receipts: [
      testExpense(date: DateTime(2024, 1, 1), cost: 100),
      testExpense(date: DateTime(2024, 1, 2), cost: 10),
      testExpense(date: DateTime(2024, 1, 3), cost: 1000),
    ]);
    expect(data.counts, [1, 2]);
    expect(data.payments, [40, 170]);
    expect(data.expenses, [100, 10]);
    expect(data.outstanding, [60, 60]);
    expect(data.cashFlow, [-60, 160]);
    expect(InsightsData.cumulative(data.cashFlow), [-60, 100]);
    expect(data.done, [1, 0]);
    expect(data.completionRate, closeTo(100 / 3, 0.001));
  });

  test('counts genders once and new patients by first visit across all dates',
      () async {
    final originalPatients = patients.docs.values.toList();
    final originalAppointments = appointments.docs.values.toList();
    final originalPermissions = login.savedPermissions;
    login.savedPermissions = Perm.full;
    patients.observableMap.clear();
    appointments.observableMap.clear();
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(originalPatients);
      appointments.observableMap.clear();
      appointments.setAll(originalAppointments);
      login.savedPermissions = originalPermissions;
    });
    patients.setAll([
      testPatient(id: 'insights-female', gender: 0),
      testPatient(id: 'insights-male', gender: 1),
      testPatient(id: 'insights-unknown', gender: 2),
    ]);
    final older = testAppointment(
        patientID: 'insights-male', date: DateTime(2023, 12, 1));
    final visits = [
      testAppointment(patientID: 'insights-female', date: DateTime(2024, 1, 1)),
      testAppointment(patientID: 'insights-female', date: DateTime(2024, 1, 2)),
      testAppointment(patientID: 'insights-male', date: DateTime(2024, 1, 2)),
      testAppointment(
          patientID: 'insights-unknown', date: DateTime(2024, 1, 2)),
      testAppointment(patientID: 'missing-patient', date: DateTime(2024, 1, 2)),
    ];
    appointments.setAll([older, ...visits]);
    await Future<void>.microtask(() {});
    final data = InsightsData(
        periods: periods, appointments: visits.reversed.toList(), receipts: []);
    expect(data.uniquePatients, 3);
    expect(data.patientVisits, 4);
    expect(data.female, 1);
    expect(data.male, 1);
    expect(data.newPatients, [1, 1]);
    expect(data.returningVisits, [0, 2]);
  });

  test(
      'chair hours and completed care value exclude unfinished work from completed series',
      () {
    final data = InsightsData(periods: periods, appointments: [
      testAppointment(
          date: DateTime(2024, 1, 1),
          duration: 45,
          isDone: true,
          price: 120,
          paid: 100),
      testAppointment(
          date: DateTime(2024, 1, 1), duration: 15, price: 500, paid: 50),
      testAppointment(
          date: DateTime(2024, 1, 2),
          duration: -30,
          isDone: true,
          price: 80,
          paid: 100),
      testAppointment(
          date: DateTime(2024, 1, 2), duration: 90, price: 200, paid: 20),
      testAppointment(
          date: DateTime(2024, 1, 3), duration: 300, isDone: true, price: 900),
    ], receipts: []);
    expect(data.scheduledHours, [1, 1.5]);
    expect(data.completedHours, [0.75, 0]);
    expect(data.completedCharges, [120, 80]);
    expect(data.completedPayments, [100, 100]);
  });

  test(
      'debt age uses visit-day boundaries and excludes future, unfinished and out-of-range visits',
      () {
    final today = DateTime(2024, 4, 10);
    final dates = [0, 30, 31, 60, 61, 90, 91];
    final data = InsightsData(
      periods: [
        Period(DateTime(2024, 1, 1), DateTime(2024, 4, 30, 23, 59), 'Range')
      ],
      asOf: today,
      appointments: [
        for (final days in dates)
          testAppointment(
              date: today.subtract(Duration(days: days)),
              isDone: true,
              price: 100,
              paid: 20),
        testAppointment(
            date: today.add(const Duration(days: 1)),
            isDone: true,
            price: 1000),
        testAppointment(date: today, isDone: false, price: 1000),
        testAppointment(date: today, isDone: true, price: 100, paid: 150),
        testAppointment(
            date: DateTime(2023, 12, 31), isDone: true, price: 1000),
      ],
      receipts: [],
    );
    expect(data.debtByAge, [160, 160, 160, 80]);
  });

  test('CSV quotes labels, preserves precision and neutralizes formula labels',
      () {
    final csv = insightsCsv([
      'A,"B"',
      '=SUM(A1)',
      ' عيادة'
    ], [
      'Net, USD'
    ], [
      [1.25, -2.5, 0]
    ], 'Period');
    expect(csv,
        '"Period","Net, USD"\r\n"A,""B""",1.25\r\n"\'=SUM(A1)",-2.50\r\n" عيادة",0.00');
  });
}
