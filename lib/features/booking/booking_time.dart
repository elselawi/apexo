import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'booking_models.dart';

bool _timeZonesInitialized = false;

/// Loads the IANA database once. The Worker validates the same zone name.
void ensureBookingTimeZones() {
  if (_timeZonesInitialized) return;
  tzdata.initializeTimeZones();
  _timeZonesInitialized = true;
}

tz.Location? bookingLocation(String name) {
  ensureBookingTimeZones();
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

List<String> bookingTimeZoneNames() {
  ensureBookingTimeZones();
  final names = tz.timeZoneDatabase.locations.keys.toList()..sort();
  return names;
}

/// Windows zone names (what `DateTime.timeZoneName` reports) mapped to the IANA
/// zones the Worker validates; Dart exposes the OS name, not `zone.tab`.
const Map<String, String> _windowsTimeZones = {
  "Arabic Standard Time": "Asia/Baghdad",
  "Arab Standard Time": "Asia/Riyadh",
  "Arabian Standard Time": "Asia/Dubai",
  "Turkey Standard Time": "Europe/Istanbul",
  "Iran Standard Time": "Asia/Tehran",
  "Israel Standard Time": "Asia/Jerusalem",
  "Jordan Standard Time": "Asia/Amman",
  "Middle East Standard Time": "Asia/Beirut",
  "Syria Standard Time": "Asia/Damascus",
  "Egypt Standard Time": "Africa/Cairo",
  "Sudan Standard Time": "Africa/Khartoum",
  "Morocco Standard Time": "Africa/Casablanca",
  "South Africa Standard Time": "Africa/Johannesburg",
  "E. Africa Standard Time": "Africa/Nairobi",
  "West Africa Standard Time": "Africa/Lagos",
  "W. Central Africa Standard Time": "Africa/Lagos",
  "GMT Standard Time": "Europe/London",
  "W. Europe Standard Time": "Europe/Berlin",
  "Western Europe Standard Time": "Europe/Lisbon",
  "Romance Standard Time": "Europe/Paris",
  "Central Europe Standard Time": "Europe/Budapest",
  "Central European Standard Time": "Europe/Warsaw",
  "GTB Standard Time": "Europe/Bucharest",
  "FLE Standard Time": "Europe/Kiev",
  "E. Europe Standard Time": "Europe/Chisinau",
  "Russian Standard Time": "Europe/Moscow",
  "Azores Standard Time": "Atlantic/Azores",
  "Atlantic Standard Time": "America/Halifax",
  "Eastern Standard Time": "America/New_York",
  "Central Standard Time": "America/Chicago",
  "Mountain Standard Time": "America/Denver",
  "US Mountain Standard Time": "America/Phoenix",
  "Pacific Standard Time": "America/Los_Angeles",
  "Alaskan Standard Time": "America/Anchorage",
  "Hawaiian Standard Time": "Pacific/Honolulu",
  "Central Standard Time (Mexico)": "America/Mexico_City",
  "SA Pacific Standard Time": "America/Bogota",
  "SA Western Standard Time": "America/La_Paz",
  "SA Eastern Standard Time": "America/Cayenne",
  "E. South America Standard Time": "America/Sao_Paulo",
  "Argentina Standard Time": "America/Buenos_Aires",
  "Pacific SA Standard Time": "America/Santiago",
  "Azerbaijan Standard Time": "Asia/Baku",
  "Georgian Standard Time": "Asia/Tbilisi",
  "Armenian Standard Time": "Asia/Yerevan",
  "Caucasus Standard Time": "Asia/Yerevan",
  "Afghanistan Standard Time": "Asia/Kabul",
  "West Asia Standard Time": "Asia/Tashkent",
  "Central Asia Standard Time": "Asia/Almaty",
  "N. Central Asia Standard Time": "Asia/Novosibirsk",
  "Pakistan Standard Time": "Asia/Karachi",
  "India Standard Time": "Asia/Kolkata",
  "Sri Lanka Standard Time": "Asia/Colombo",
  "Nepal Standard Time": "Asia/Kathmandu",
  "Bangladesh Standard Time": "Asia/Dhaka",
  "Myanmar Standard Time": "Asia/Yangon",
  "SE Asia Standard Time": "Asia/Bangkok",
  "Singapore Standard Time": "Asia/Singapore",
  "China Standard Time": "Asia/Shanghai",
  "Taipei Standard Time": "Asia/Taipei",
  "Tokyo Standard Time": "Asia/Tokyo",
  "Korea Standard Time": "Asia/Seoul",
  "Ulaanbaatar Standard Time": "Asia/Ulaanbaatar",
  "W. Australia Standard Time": "Australia/Perth",
  "AUS Eastern Standard Time": "Australia/Sydney",
  "E. Australia Standard Time": "Australia/Brisbane",
  "Cen. Australia Standard Time": "Australia/Adelaide",
  "New Zealand Standard Time": "Pacific/Auckland",
  "UTC": "UTC",
  "Dateline Standard Time": "Etc/GMT+12",
};

/// The device's zone in IANA form, for the claim form's default.
String? bookingSystemTimeZone() {
  ensureBookingTimeZones();
  final mapped = _windowsTimeZones[DateTime.now().timeZoneName];
  if (mapped != null && bookingLocation(mapped) != null) return mapped;

  // Unknown name (localised Windows, or non-Windows): match the device offset
  // against the database rather than guessing a city.
  final offset = DateTime.now().timeZoneOffset;
  if (offset.inMinutes % 60 == 0) {
    final hours = offset.inMinutes ~/ 60;
    if (hours == 0) return "UTC";
    // `Etc/GMT` signs are inverted from the offset: +03:00 is `Etc/GMT-3`.
    final inverted = -hours;
    final name = "Etc/GMT${inverted > 0 ? "+" : ""}$inverted";
    if (bookingLocation(name) != null) return name;
  }
  for (final location in tz.timeZoneDatabase.locations.values) {
    if (tz.TZDateTime.now(location).timeZoneOffset == offset) return location.name;
  }
  return null;
}

String _pad(int value) => value.toString().padLeft(2, "0");

String bookingClinicDate(int epochMs, String timeZone) {
  final location = bookingLocation(timeZone);
  if (location == null) return "";
  final local = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(epochMs), location);
  return "${local.year.toString().padLeft(4, "0")}-"
      "${_pad(local.month)}-${_pad(local.day)}";
}

int bookingClinicMinutes(int epochMs, String timeZone) {
  final location = bookingLocation(timeZone);
  if (location == null) return 0;
  final local = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(epochMs), location);
  return local.hour * 60 + local.minute;
}

String bookingClinicTimeLabel(int epochMs, String timeZone) {
  final minutes = bookingClinicMinutes(epochMs, timeZone);
  return bookingMinutesToTime(minutes);
}

/// 1 = Monday … 7 = Sunday.
int bookingWeekdayOf(String date) {
  final weekday = DateTime.parse(date).weekday;
  return weekday;
}

String bookingAddDays(String date, int days) {
  final parsed = DateTime.parse("${date}T00:00:00Z");
  final shifted = parsed.add(Duration(days: days));
  return "${shifted.year.toString().padLeft(4, "0")}-"
      "${_pad(shifted.month)}-${_pad(shifted.day)}";
}

int bookingDaysBetween(String from, String to) =>
    DateTime.parse("${to}T00:00:00Z")
        .difference(DateTime.parse("${from}T00:00:00Z")).inDays;

class BookingMoment {
  BookingMoment({this.local, this.ambiguous = false, this.gap = false});

  /// The instant in the device's local zone, ready for the PMS editor; null when
  /// the clinic's wall clock does not exist (DST gap).
  final DateTime? local;
  final bool ambiguous;
  final bool gap;

  bool get needsManualConfirmation => local == null || ambiguous;
}

/// Converts a clinic-local wall clock to the device-local instant. DST gaps return
/// no instant; folds are reported so scheduling asks for confirmation.
BookingMoment bookingClinicMomentToLocal(
  String date,
  String time,
  String timeZone,
) {
  final location = bookingLocation(timeZone);
  if (location == null) return BookingMoment(gap: true);
  final parts = date.split("-").map(int.parse).toList();
  final clock = time.split(":").map(int.parse).toList();
  final wall = tz.TZDateTime(
      location, parts[0], parts[1], parts[2], clock[0], clock[1]);
  final isGap = wall.year != parts[0] ||
      wall.month != parts[1] ||
      wall.day != parts[2] ||
      wall.hour != clock[0] ||
      wall.minute != clock[1];
  if (isGap) return BookingMoment(gap: true);
  final wallEpoch = DateTime.utc(
      parts[0], parts[1], parts[2], clock[0], clock[1]).millisecondsSinceEpoch;
  bool sameWall(tz.TZDateTime candidate) =>
      candidate.year == parts[0] &&
      candidate.month == parts[1] &&
      candidate.day == parts[2] &&
      candidate.hour == clock[0] &&
      candidate.minute == clock[1];
  // Not all folds repeat an hour (Lord Howe repeats thirty minutes).
  final instants = <int>{};
  for (final zone in location.zones) {
    final epoch = wallEpoch - zone.offset.inMilliseconds;
    final candidate = tz.TZDateTime.fromMillisecondsSinceEpoch(location, epoch);
    if (sameWall(candidate)) instants.add(epoch);
  }
  final ambiguous = instants.length > 1;
  return BookingMoment(local: wall.toLocal(), ambiguous: ambiguous);
}

/// The first future intersection among the stored candidate dates, or null when
/// the preference expired, hits a closed date, or cannot fit the current hours.
BookingMoment? suggestedBookingMoment(
  BookingRequest request,
  BookingWeeklyHours effectiveHours, {
  List<String> closedDates = const [],
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = bookingClinicDate(current.millisecondsSinceEpoch, request.timeZone);
  if (request.expiresAt <= current.millisecondsSinceEpoch || !request.isPending) {
    return null;
  }
  final nowMinutes = bookingClinicMinutes(
      current.millisecondsSinceEpoch, request.timeZone) + 1;
  final from = bookingTimeToMinutes(request.windowFrom);
  final to = bookingTimeToMinutes(request.windowTo);
  for (final date in request.candidateDates) {
    if (date.compareTo(today) < 0 || closedDates.contains(date)) continue;
    final dayIndex = bookingWeekdayOf(date) - 1;
    final intervals = effectiveHours[bookingWeekdays[dayIndex]];
    for (final interval in intervals) {
      final start = bookingTimeToMinutes(interval[0]);
      final end = bookingTimeToMinutes(interval[1]);
      final lower = [from, start, date == today ? nowMinutes : 0]
          .reduce((a, b) => a > b ? a : b);
      final upper = to < end ? to : end;
      if (upper <= lower) continue;
      return bookingClinicMomentToLocal(
          date, bookingMinutesToTime(lower), request.timeZone);
    }
  }
  return null;
}
