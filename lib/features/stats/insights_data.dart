import 'dart:math' as math;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/stats/charts_controller.dart';

/// One aggregation per dashboard rebuild, shared by cards, charts and tables.
class InsightsData {
  InsightsData({
    required this.periods,
    required List<Appointment> appointments,
    required List<Expense> receipts,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    counts = List.filled(periods.length, 0.0);
    payments = List.filled(periods.length, 0.0);
    expenses = List.filled(periods.length, 0.0);
    done = List.filled(periods.length, 0.0);
    missed = List.filled(periods.length, 0.0);
    newPatients = List.filled(periods.length, 0.0);
    outstanding = List.filled(periods.length, 0.0);
    scheduledHours = List.filled(periods.length, 0.0);
    completedHours = List.filled(periods.length, 0.0);
    completedCharges = List.filled(periods.length, 0.0);
    completedPayments = List.filled(periods.length, 0.0);
    returningVisits = List.filled(periods.length, 0.0);
    final patients = <String>{};
    final firstVisitIDs = <String, String?>{};
    for (final appointment in appointments) {
      final index = _periodIndex(appointment.date);
      if (index < 0) continue;
      counts[index]++;
      payments[index] += appointment.paid;
      outstanding[index] += math.max(0, appointment.price - appointment.paid);
      final hours = math.max(0, appointment.duration) / 60;
      scheduledHours[index] += hours;
      if (appointment.isDone) {
        done[index]++;
        completedHours[index] += hours;
        completedCharges[index] += appointment.price;
        completedPayments[index] += appointment.paid;
        final visitDay = DateTime.utc(appointment.date.year,
            appointment.date.month, appointment.date.day);
        final age = today.difference(visitDay).inDays;
        if (age >= 0) {
          final bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
          debtByAge[bucket] += math.max(0, appointment.price - appointment.paid);
        }
      }
      if (appointment.isMissed) missed[index]++;
      final patient = appointment.patient;
      if (patient != null) {
        patientVisits++;
        if (patients.add(patient.id)) {
          if (patient.gender == 0) female++;
          if (patient.gender == 1) male++;
          firstVisitIDs[patient.id] = patient.allAppointments.firstOrNull?.id;
        }
        if (firstVisitIDs[patient.id] == appointment.id) {
          newPatients[index]++;
        } else if (firstVisitIDs[patient.id] != null) {
          returningVisits[index]++;
        }
      }
    }
    uniquePatients = patients.length;
    for (final receipt in receipts) {
      final index = _periodIndex(receipt.date);
      if (index >= 0) expenses[index] += receipt.cost;
    }
  }

  final List<Period> periods;
  late final List<double> counts, payments, expenses, done, missed;
  late final List<double> newPatients, outstanding, returningVisits;
  late final List<double> scheduledHours, completedHours;
  late final List<double> completedCharges, completedPayments;
  final List<double> debtByAge = List.filled(4, 0.0);
  late final int uniquePatients;
  int female = 0, male = 0, patientVisits = 0;

  List<String> get labels => periods.map((period) => period.label).toList();
  List<double> get cashFlow => List.generate(
      periods.length, (index) => payments[index] - expenses[index]);
  double get totalAppointments => sum(counts);
  double get completionRate =>
      totalAppointments == 0 ? 0 : sum(done) / totalAppointments * 100;

  int _periodIndex(DateTime date) {
    var low = 0;
    var high = periods.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final period = periods[middle];
      if (date.isBefore(period.start)) {
        high = middle - 1;
      } else if (date.isAfter(period.end)) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return -1;
  }

  static double sum(Iterable<double> values) =>
      values.fold(0.0, (total, value) => total + value);

  static List<double> cumulative(List<double> values) {
    var total = 0.0;
    return values.map((value) => total += value).toList();
  }
}

String insightsCsv(List<String> labels, List<String> names,
    List<List<double>> series, String periodLabel) {
  // Quote every cell, including translated labels containing separators.
  String cell(String value) {
    // Spreadsheet applications must not interpret labels as formulas.
    if (RegExp(r'^[\s]*[=+@-]').hasMatch(value)) value = "'$value";
    return '"${value.replaceAll('"', '""')}"';
  }

  return [
    [periodLabel, ...names].map(cell).join(','),
    for (var index = 0; index < labels.length; index++)
      [
        cell(labels[index]),
        ...series.map((values) => values[index].toStringAsFixed(2)),
      ].join(','),
  ].join('\r\n');
}
