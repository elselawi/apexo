import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF, globalSettings;
import 'package:apexo/services/localization/locale.dart';

String bookingWeekdayName(int weekday) =>
    txt("bookingWeekday${weekday.clamp(1, 7)}");

/// The 1-based weekday number (1 = Monday … 7 = Sunday) of a wire day key.
int bookingWeekdayNumber(String day) => bookingWeekdays.indexOf(day) + 1;

/// Wire day keys in the clinic's calendar order (Monday-first by default). Only
/// display order rotates; the configuration always travels as `mon … sun`.
List<String> bookingWeekdaysForDisplay([String? startDay]) {
  final first = switch ((startDay ?? globalSettings.startDayOfWeek)
      .trim()
      .toLowerCase()) {
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6,
    "sunday" => 7,
    _ => 1,
  };
  return [
    ...bookingWeekdays.sublist(first - 1),
    ...bookingWeekdays.sublist(0, first - 1),
  ];
}

/// The staff-facing preference label, derived from structured fields only.
String bookingPreferenceLabel(BookingRequest request) {
  final preference = request.preference;
  final window = "${preference.from}–${preference.to}";
  switch (preference.kind) {
    case "range":
      return "${request.fromDate} – ${request.toDate} · $window";
    case "weekday":
      final label = txt("bookingNextOccurrences")
          .replaceAll("{count}", "${preference.weeks ?? 1}")
          .replaceAll("{day}", bookingWeekdayName(preference.weekday ?? 1));
      return "$label · $window";
    default:
      return "${request.fromDate} · $window";
  }
}

String bookingStatusLabel(String status) => switch (status) {
      "handled" => txt("bookingStatusHandled"),
      "declined" => txt("bookingStatusDeclined"),
      _ => txt("bookingStatusPending"),
    };

String bookingSubmittedLabel(int epochMs) =>
    DF.full(DateTime.fromMillisecondsSinceEpoch(epochMs));

String bookingZoneSuffix(String timeZone) => "($timeZone)";
