/// A stretch of a day that is already taken by a visit.
typedef BusyStretch = ({DateTime start, Duration duration});

/// When a new visit on [day] is most likely to start.
///
/// A guess, not a booking rule. A visit added for today starts at the next
/// [step] minutes that have not passed yet; any other day starts at the
/// clinic's usual morning hour — or after the last visit already booked that
/// day, whichever is later, because a new visit queued behind the day's work is
/// where reception usually wants it. From there the guess walks forward until
/// [duration] fits without overlapping one of the [busy] stretches.
///
/// [preferred] is a moment the caller already has — a click on the timeline at
/// 10:00, say. The guess starts there instead of guessing, and only moves when
/// that moment clashes with a booking.
DateTime guessAppointmentStart({
  required DateTime day,
  required DateTime now,
  required Iterable<BusyStretch> busy,
  DateTime? preferred,
  int duration = 15,
  int step = 15,
  int morningHour = 9,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  final booked = busy
      .where((stretch) =>
          stretch.start.isBefore(dayEnd) &&
          stretch.start.add(stretch.duration).isAfter(dayStart))
      .toList();

  var candidate =
      preferred ?? _startingPoint(day, now, booked, step, morningHour);

  bool free(DateTime start) {
    final end = start.add(Duration(minutes: duration));
    return !booked.any((stretch) =>
        start.isBefore(stretch.start.add(stretch.duration)) &&
        stretch.start.isBefore(end));
  }

  // A day holds at most this many steps; walking further would be tomorrow.
  final attempts = (24 * 60 ~/ step) + 1;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (free(candidate)) break;
    candidate = candidate.add(Duration(minutes: step));
  }
  return candidate;
}

DateTime _startingPoint(
  DateTime day,
  DateTime now,
  List<BusyStretch> booked,
  int step,
  int morningHour,
) {
  if (day.year == now.year && day.month == now.month && day.day == now.day) {
    return _ceilToStep(now, step);
  }
  var start = DateTime(day.year, day.month, day.day, morningHour);
  for (final stretch in booked) {
    final end = stretch.start.add(stretch.duration);
    if (end.isAfter(start)) start = end;
  }
  return start;
}

/// [time] rounded up to the next [step]-minute boundary, seconds included: a
/// visit guessed at 10:15:30 would otherwise already be in the past.
DateTime _ceilToStep(DateTime time, int step) {
  final midnight = DateTime(time.year, time.month, time.day);
  final stepMicros = step * Duration.microsecondsPerMinute;
  final elapsed = time.difference(midnight).inMicroseconds;
  final rounded = ((elapsed + stepMicros - 1) ~/ stepMicros) * stepMicros;
  return midnight.add(Duration(microseconds: rounded));
}
