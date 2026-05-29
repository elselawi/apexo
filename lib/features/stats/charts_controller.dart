import 'package:apexo/core/observable.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart' show showDateRangePicker;
import 'package:table_calendar/table_calendar.dart';

enum StatsInterval { days, weeks, months, quarters, years }

class Period {
  DateTime start;
  DateTime end;
  String label;
  Period(this.start, this.end, this.label);
}

class _ChartsController {
  final filterByOperatorID = ObservableState("");
  final start =
      ObservableState(DateTime(DateTime.now().year, DateTime.now().month, 1));
  final end = ObservableState(
      DateTime(DateTime.now().year, DateTime.now().month, 1)
          .add(const Duration(days: 31)));
  final interval = ObservableState(StatsInterval.days);
  String get intervalString {
    return chartsCtrl.interval().name;
  }

  _nullifyCache(_) {
    _filteredAppointments = null;
    _filteredReceipts = null;
  }

  List<Appointment>? _filteredAppointments;
  List<Appointment> get filteredAppointments {
    if (_filteredAppointments != null) return _filteredAppointments!;
    List<Appointment> res = [];
    for (var appointment in appointments.present.values) {
      if (appointment.date.isAfter(end())) continue;
      if (appointment.date.isBefore(start())) continue;
      if (filterByOperatorID().isNotEmpty &&
          !appointment.operatorsIDs.contains(filterByOperatorID())) continue;
      res.add(appointment);
    }
    _filteredAppointments = res..sort((a, b) => a.date.compareTo(b.date));
    return _filteredAppointments!;
  }

  List<Expense>? _filteredReceipts;
  List<Expense> get filteredReceipts {
    if (_filteredReceipts != null) return _filteredReceipts!;
    List<Expense> res = [];
    for (var receipt in expenses.present.values) {
      if (receipt.date.isAfter(end())) continue;
      if (receipt.date.isBefore(start())) continue;
      res.add(receipt);
    }
    _filteredReceipts = res..sort((a, b) => a.date.compareTo(b.date));
    return _filteredReceipts!;
  }

  List<List<Appointment>> get groupedAppointments {
    List<List<Appointment>> res = [];
    for (var period in periods) {
      List<Appointment> appointments = [];
      for (var appointment in filteredAppointments) {
        if (appointment.date.isAfter(period.end)) break;
        if (appointment.date.isBefore(period.start)) continue;
        appointments.add(appointment);
      }
      res.add(appointments);
    }
    return res;
  }

  List<double> get groupedPayments {
    List<double> res = [];
    for (var period in periods) {
      double payment = 0;
      for (var appointment in filteredAppointments) {
        if (appointment.date.isAfter(period.end)) break;
        if (appointment.date.isBefore(period.start)) continue;
        payment += appointment.paid;
      }
      res.add(payment);
    }
    return res;
  }

  List<double> get groupedExpenses {
    List<double> res = [];
    for (var period in periods) {
      double expense = 0;
      for (var receipt in filteredReceipts) {
        if (receipt.date.isAfter(period.end)) break;
        if (receipt.date.isBefore(period.start)) continue;
        expense += receipt.cost;
      }
      res.add(expense);
    }
    return res;
  }

  List<List<double>> get doneAndMissedAppointments {
    List<List<double>> res = [];
    for (var period in periods) {
      List<double> c = [0, 0];
      for (var appointment in filteredAppointments) {
        if (appointment.date.isAfter(period.end)) break;
        if (appointment.date.isBefore(period.start)) continue;
        if (appointment.isMissed) c[1]++;
        if (appointment.isDone) c[0]++;
      }
      res.add(c);
    }
    return res;
  }

  List<double> get newPatients {
    List<double> res = [];
    for (var period in periods) {
      double n = 0;
      for (var appointment in filteredAppointments) {
        if (appointment.date.isAfter(period.end)) continue;
        if (appointment.date.isBefore(period.start)) continue;
        if (appointment.patient == null) continue;
        if (appointment.patient!.allAppointments.firstOrNull == appointment)
          n++;
      }
      res.add(n);
    }
    return res;
  }

  List<double> get timeOfDayDistribution {
    List<double> res = List.generate(24, (index) => 0.0);
    for (var appointment in filteredAppointments) {
      final int hour = appointment.date.hour;
      res[hour]++;
    }
    return res;
  }

  List<double> get dayOfMonthDistribution {
    List<double> res = List.generate(31, (index) => 0.0);
    for (var appointment in filteredAppointments) {
      final int day = appointment.date.day;
      res[day - 1]++;
    }
    return res;
  }

  List<double> get dayOfWeekDistribution {
    List<double> res = List.generate(7, (index) => 0.0);
    for (var appointment in filteredAppointments) {
      final int day = appointment.date.weekday;
      res[day - 1]++;
    }
    return res;
  }

  List<double> get monthOfYearDistribution {
    List<double> res = List.generate(12, (index) => 0.0);
    for (var appointment in filteredAppointments) {
      final int month = appointment.date.month;
      res[month - 1]++;
    }
    return res;
  }

  List<int> get femaleMale {
    List<int> res = [0, 0];
    for (var appointment in filteredAppointments) {
      if (appointment.patient == null) continue;
      if (appointment.patient!.gender == 0) res[0]++;
      if (appointment.patient!.gender == 1) res[1]++;
    }
    return res;
  }

  List<Period> get periods {
    List<Period> periods = [];

    DateTime currentStart =
        _normalizeStart(DateTime(start().year, start().month, start().day));
    DateTime nextPeriod =
        _addInterval(currentStart).subtract(const Duration(seconds: 1));

    while (
        currentStart.isBefore(end()) || currentStart.isAtSameMomentAs(end())) {
      periods.add(Period(currentStart, nextPeriod, _getLabel(currentStart)));
      currentStart = nextPeriod.add(const Duration(days: 1));
      nextPeriod = _addInterval(nextPeriod);

      currentStart =
          DateTime(currentStart.year, currentStart.month, currentStart.day);
      nextPeriod = DateTime(
          nextPeriod.year, nextPeriod.month, nextPeriod.day, 23, 59, 59, 999);
    }

    return periods;
  }

  resetSelected() {
    final now = DateTime.now();
    start(DateTime(now.year, now.month, 1));
    end(DateTime(now.year, now.month, 1).add(const Duration(days: 31)));
    interval(StatsInterval.days);
  }

  int _daysSinceWeekStart(DateTime date) {
    int adjustedWeekday = (date.weekday -
            StartingDayOfWeek.values
                .indexWhere((e) => e.name == globalSettings.startDayOfWeek) -
            1) %
        7;
    return adjustedWeekday;
  }

  int _daysSinceMonthStart(DateTime date) {
    // The day of the month is already available as a property of DateTime
    // We subtract 1 because the days of the month are 1-indexed (1-31)
    return date.day - 1;
  }

  int _daysSinceQuarterStart(DateTime date) {
    int quarterStartMonth;
    if (date.month >= 1 && date.month <= 3) {
      quarterStartMonth = 1;
    } else if (date.month >= 4 && date.month <= 6) {
      quarterStartMonth = 4;
    } else if (date.month >= 7 && date.month <= 9) {
      quarterStartMonth = 7;
    } else {
      quarterStartMonth = 10;
    }
    DateTime quarterStartDate = DateTime(date.year, quarterStartMonth, 1);
    int daysSinceStart = date.difference(quarterStartDate).inDays;
    return daysSinceStart;
  }

  int _daysSinceYearStart(DateTime date) {
    DateTime yearStartDate = DateTime(date.year, 1, 1);

    // Calculate the difference in days
    int daysSinceStart = date.difference(yearStartDate).inDays;

    return daysSinceStart;
  }

  DateTime _normalizeStart(DateTime start) {
    switch (interval()) {
      case StatsInterval.days:
        return start;
      case StatsInterval.weeks:
        return start.subtract(Duration(days: _daysSinceWeekStart(start)));
      case StatsInterval.months:
        return start.subtract(Duration(days: _daysSinceMonthStart(start)));
      case StatsInterval.quarters:
        return start.subtract(Duration(days: _daysSinceQuarterStart(start)));
      default:
        return start.subtract(Duration(days: _daysSinceYearStart(start)));
    }
  }

  String _getLabel(DateTime start) {
    switch (interval()) {
      case StatsInterval.days:
        return DF.allNumbers(start);
      case StatsInterval.weeks:
        return "W${DateFormat("${_weekOfMonth(start)} MM/yy", locale.s.$code).format(start)}";
      case StatsInterval.months:
        return DateFormat("MMM/yy", locale.s.$code).format(start);
      case StatsInterval.quarters:
        return "Q${DateFormat("Q yyyy", locale.s.$code).format(start)}";
      default:
        return DateFormat("yyyy", locale.s.$code).format(start);
    }
  }

  int _weekOfMonth(DateTime date) {
    DateTime firstDayOfMonth = DateTime(date.year, date.month, 1);
    int firstWeekDay = (firstDayOfMonth.weekday % 7) + 1;
    int dayOfMonth = date.day;
    return ((dayOfMonth + firstWeekDay - 2) / 7).ceil();
  }

  DateTime _addInterval(DateTime input) {
    switch (interval()) {
      case StatsInterval.days:
        return input.add(const Duration(days: 1));
      case StatsInterval.weeks:
        return input.add(const Duration(days: 7));
      case StatsInterval.months:
        return _addMonths(input, 1);
      case StatsInterval.quarters:
        return _addMonths(input, 3);
      case StatsInterval.years:
        return _addYears(input, 1);
    }
  }

  DateTime _addMonths(DateTime input, int monthsToAdd) {
    // Calculate the target month and year
    int targetMonth = input.month + monthsToAdd;
    int targetYear = input.year + (targetMonth - 1) ~/ 12;
    targetMonth = (targetMonth - 1) % 12 + 1;

    // Get the last day of the target month
    int lastDayOfTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;

    // If the input day is greater than the last day of the target month,
    // or if it's the last day of the input month, use the last day of the target month
    int targetDay = (input.day > lastDayOfTargetMonth ||
            input.day == _daysInMonth(input.year, input.month))
        ? lastDayOfTargetMonth
        : input.day;

    return DateTime(
      targetYear,
      targetMonth,
      targetDay,
      input.hour,
      input.minute,
      input.second,
      input.millisecond,
      input.microsecond,
    );
  }

  DateTime _addYears(DateTime input, int yearsToAdd) {
    int newYear = input.year + yearsToAdd;
    int maxDayInNewMonth = _daysInMonth(newYear, input.month);
    int newDay = input.day > maxDayInNewMonth ? maxDayInNewMonth : input.day;

    return DateTime(newYear, input.month, newDay, input.hour, input.minute,
        input.second, input.millisecond, input.microsecond);
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  List<DateTime>? _cachedPeriod;
  void normalizeSelectedRange(bool useCached) {
    if (periods.isEmpty) return;

    if (useCached) {
      if (interval() == StatsInterval.weeks) {
        _cachedPeriod = [start(), end()];
      }

      if (interval() == StatsInterval.days && _cachedPeriod != null) {
        start(_cachedPeriod![0]);
        end(_cachedPeriod![1]);
      }
    } else {
      _cachedPeriod = null;
    }

    start(periods.first.start);
    end(periods.last.end);
  }

  void setIntervalToDays() {
    interval(StatsInterval.days);
    normalizeSelectedRange(false);
  }

  void setIntervalToWeeks() {
    interval(StatsInterval.weeks);
    normalizeSelectedRange(false);
  }

  void setIntervalToMonths() {
    interval(StatsInterval.months);
    normalizeSelectedRange(false);
  }

  void setIntervalToQuarters() {
    interval(StatsInterval.quarters);
    normalizeSelectedRange(false);
  }

  void setIntervalToYears() {
    interval(StatsInterval.years);
    normalizeSelectedRange(false);
  }

  void toggleInterval() {
    int currentIndex = StatsInterval.values.indexOf(interval());
    if (currentIndex == StatsInterval.values.length - 1) {
      interval(StatsInterval.values[0]);
    } else {
      interval(StatsInterval.values[currentIndex + 1]);
    }
    normalizeSelectedRange(true);
  }

  void filterByOperator(String? value) {
    filterByOperatorID(value ?? "");
  }

  rangePicker(BuildContext context) async {
    final selectedRange = await showDateRangePicker(
      currentDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: start(), end: end()),
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 9999)),
      lastDate: DateTime.now().add(const Duration(days: 9999)),
    );

    if (selectedRange != null) {
      interval(StatsInterval.days);
      start(selectedRange.start);
      end(selectedRange.end);
      normalizeSelectedRange(false);
    }
  }

  _ChartsController() {
    final filters = List<ObservableState<DateTime>>.from([start, end]);
    for (final ObservableState<DateTime> filter in filters) {
      filter.observe(_nullifyCache);
    }
    filterByOperatorID.observe(_nullifyCache);
    // also bind to showArchived
    showArchived.observe((_) => start(start()));
  }
}

final chartsCtrl = _ChartsController();
