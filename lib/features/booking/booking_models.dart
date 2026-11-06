import 'booking_canonical.dart';

/// The seven clinic weekday keys, Monday first, as the wire format uses them.
const List<String> bookingWeekdays = [
  "mon",
  "tue",
  "wed",
  "thu",
  "fri",
  "sat",
  "sun",
];

/// Every locale the app ships, in the app's own order. The public page has a
/// dictionary for each of these; the Worker rejects anything else.
const List<String> bookingLanguages = [
  "en",
  "ar",
  "es",
  "el",
  "fa",
  "ku",
  "fr",
  "tr",
  "it",
  "ur",
];

/// Native display names, so the picker never shows a bare two-letter code.
String bookingLanguageName(String code) => switch (code) {
      "ar" => "العربية",
      "el" => "Ελληνικά",
      "es" => "Español",
      "fa" => "فارسی",
      "fr" => "Français",
      "it" => "Italiano",
      "ku" => "کوردی",
      "tr" => "Türkçe",
      "ur" => "اردو",
      _ => "English",
    };

final RegExp bookingDatePattern = RegExp(r"^\d{4}-\d{2}-\d{2}$");
final RegExp bookingTimePattern = RegExp(r"^([01]\d|2[0-3]):[0-5]\d$");
final RegExp _accentPattern = RegExp(r"^#[0-9a-f]{6}$");

bool isBookingDate(String value) {
  if (!bookingDatePattern.hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  final parts = value.split("-").map(int.parse).toList();
  return parsed.year == parts[0] &&
      parsed.month == parts[1] &&
      parsed.day == parts[2];
}

bool isBookingTime(String value) => bookingTimePattern.hasMatch(value);

int bookingTimeToMinutes(String value) {
  final parts = value.split(":");
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String bookingMinutesToTime(int minutes) {
  final hour = (minutes ~/ 60) % 24;
  return "${hour.toString().padLeft(2, "0")}:"
      "${(minutes % 60).toString().padLeft(2, "0")}";
}

/// A validated seven-day weekly schedule. Intervals are `[start, end)` clock
/// strings, sorted and non-overlapping, at most four per day.
class BookingWeeklyHours {

  factory BookingWeeklyHours.empty() => BookingWeeklyHours({
        for (final day in bookingWeekdays) day: <List<String>>[],
      });

  factory BookingWeeklyHours.followClinic() => BookingWeeklyHours.empty();
  BookingWeeklyHours(this.days);

  final Map<String, List<List<String>>> days;

  List<List<String>> operator [](String day) => days[day] ?? const [];

  Map<String, Object?> toJson() => {
        for (final day in bookingWeekdays) day: days[day]!
            .map((interval) => [interval[0], interval[1]]).toList(),
      };

  bool get isEmpty => bookingWeekdays.every((day) => this[day].isEmpty);

  /// Returns an error key, or null when valid.
  String? validate(String field) {
    if (days.length != bookingWeekdays.length ||
        !bookingWeekdays.every(days.containsKey)) {
      return field;
    }
    for (final day in bookingWeekdays) {
      final intervals = days[day]!;
      if (intervals.length > 4) return "$field.$day";
      var previousEnd = -1;
      for (final interval in intervals) {
        if (interval.length != 2 ||
            !isBookingTime(interval[0]) ||
            !isBookingTime(interval[1])) {
          return "$field.$day";
        }
        final start = bookingTimeToMinutes(interval[0]);
        final end = bookingTimeToMinutes(interval[1]);
        if (start >= end || start <= previousEnd) return "$field.$day";
        previousEnd = end;
      }
    }
    return null;
  }

  static BookingWeeklyHours? fromJson(Object? value) {
    if (value is! Map) return null;
    if (!bookingWeekdays.every(value.containsKey)) return null;
    final days = <String, List<List<String>>>{};
    for (final day in bookingWeekdays) {
      final raw = value[day];
      if (raw is! List) return null;
      final intervals = <List<String>>[];
      for (final interval in raw) {
        if (interval is! List || interval.length != 2) return null;
        intervals.add([interval[0].toString(), interval[1].toString()]);
      }
      days[day] = intervals;
    }
    final hours = BookingWeeklyHours(days);
    return hours.validate("hours") == null ? hours : null;
  }

  BookingWeeklyHours intersect(BookingWeeklyHours other) {
    final result = <String, List<List<String>>>{};
    for (final day in bookingWeekdays) {
      final merged = <List<String>>[];
      for (final first in this[day]) {
        for (final second in other[day]) {
          final start = bookingTimeToMinutes(first[0]) >
                  bookingTimeToMinutes(second[0])
              ? bookingTimeToMinutes(first[0])
              : bookingTimeToMinutes(second[0]);
          final end = bookingTimeToMinutes(first[1]) <
                  bookingTimeToMinutes(second[1])
              ? bookingTimeToMinutes(first[1])
              : bookingTimeToMinutes(second[1]);
          if (end > start) {
            merged.add([bookingMinutesToTime(start), bookingMinutesToTime(end)]);
          }
        }
      }
      merged.sort((a, b) => a[0].compareTo(b[0]));
      result[day] = merged;
    }
    return BookingWeeklyHours(result);
  }
}

class BookingProfile {

  factory BookingProfile.fromJson(Map<String, Object?> json) => BookingProfile(
        name: (json["name"] ?? "").toString(),
        phone: (json["phone"] ?? "").toString(),
        address: (json["address"] ?? "").toString(),
        welcome: (json["welcome"] ?? "").toString(),
        accentColor: (json["accentColor"] ?? "").toString(),
        defaultLanguage: (json["defaultLanguage"] ?? "en").toString(),
      );
  BookingProfile({
    required this.name,
    required this.phone,
    this.address = "",
    this.welcome = "",
    this.accentColor = "",
    this.defaultLanguage = "en",
  });

  String name;
  String phone;
  String address;
  String welcome;
  String accentColor;
  String defaultLanguage;

  Map<String, Object?> toJson() => {
        "name": name,
        "phone": phone,
        "address": address,
        "welcome": welcome,
        "accentColor": accentColor,
        "defaultLanguage": defaultLanguage,
      };

  String? validate() {
    final normalized = nfc(name.trim());
    if (codePointLength(normalized) < 1 || codePointLength(normalized) > 100) {
      return "profile.name";
    }
    if (normalizeBookingPhone(phone) == null) return "profile.phone";
    if (codePointLength(nfc(address.trim())) > 300) return "profile.address";
    if (codePointLength(nfc(welcome.trim())) > 500) return "profile.welcome";
    // The accent is optional: an empty value asks the page to use its palette.
    final accent = accentColor.trim().toLowerCase();
    if (accent.isNotEmpty && !_accentPattern.hasMatch(accent)) {
      return "profile.accentColor";
    }
    if (!bookingLanguages.contains(defaultLanguage)) {
      return "profile.defaultLanguage";
    }
    return null;
  }
}

class BookingClinicConfig {

  factory BookingClinicConfig.blank() => BookingClinicConfig(
        profile: BookingProfile(name: "", phone: ""),
        timeZone: "UTC",
        dialCode: "+1",
        hours: BookingWeeklyHours.empty(),
        closedDates: [],
      );

  factory BookingClinicConfig.fromJson(Map<String, Object?> json) =>
      BookingClinicConfig(
        profile: BookingProfile.fromJson(
            (json["profile"] as Map?)?.cast<String, Object?>() ?? const {}),
        timeZone: (json["timeZone"] ?? "UTC").toString(),
        dialCode: (json["dialCode"] ?? "+1").toString(),
        hours: BookingWeeklyHours.fromJson(json["hours"]) ??
            BookingWeeklyHours.empty(),
        closedDates: (json["closedDates"] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
        contactEmail: json["contactEmail"]?.toString(),
        enabled: json["enabled"] == true,
      );
  BookingClinicConfig({
    required this.profile,
    required this.timeZone,
    required this.dialCode,
    required this.hours,
    required this.closedDates,
    this.contactEmail,
    this.enabled = false,
  });

  BookingProfile profile;
  String timeZone;
  String dialCode;
  BookingWeeklyHours hours;
  List<String> closedDates;
  String? contactEmail;
  bool enabled;

  Map<String, Object?> toJson() => {
        "profile": profile.toJson(),
        "timeZone": timeZone,
        "dialCode": dialCode,
        "hours": hours.toJson(),
        "closedDates": closedDates,
        "contactEmail": contactEmail,
        "enabled": enabled,
      };

  /// Mirrors the Worker's validation so the server never rejects a value the
  /// editor allowed.
  String? validate() {
    final profileError = profile.validate();
    if (profileError != null) return profileError;
    if (timeZone.isEmpty) return "timeZone";
    final dial = dialCode.trim();
    if (!dial.startsWith("+") || dial.length < 3 || dial.length > 5) {
      return "dialCode";
    }
    final hoursError = hours.validate("hours");
    if (hoursError != null) return hoursError;
    if (closedDates.length > 366) return "closedDates";
    for (final date in closedDates) {
      if (!isBookingDate(date)) return "closedDates";
    }
    if (closedDates.toSet().length != closedDates.length) return "closedDates";
    if (contactEmail != null && normalizeBookingEmail(contactEmail!) == null) {
      return "contactEmail";
    }
    return null;
  }

  /// The exact shape the operation proof binds: NFC-normalized text, a
  /// lowercased accent colour and `null` for an empty contact email. The Worker
  /// runs the same normalization before hashing.
  BookingClinicConfig normalizedForProof() {
    String text(String value) => nfc(value.trim());
    final normalizedPhone = normalizeBookingPhone(profile.phone) ?? profile.phone;
    final accent = profile.accentColor.trim().toLowerCase();
    return BookingClinicConfig(
      profile: BookingProfile(
        name: text(profile.name),
        phone: normalizedPhone,
        address: text(profile.address),
        welcome: text(profile.welcome),
        accentColor: accent,
        defaultLanguage: profile.defaultLanguage,
      ),
      timeZone: timeZone,
      dialCode: dialCode,
      hours: BookingWeeklyHours({
        for (final day in bookingWeekdays)
          day: hours[day]
              .map((interval) => [interval[0], interval[1]])
              .toList(),
      }),
      closedDates: List<String>.from(closedDates),
      contactEmail: (contactEmail == null || contactEmail!.isEmpty)
          ? null
          : normalizeBookingEmail(contactEmail!),
      enabled: enabled,
    );
  }
}

final RegExp _arabicIndic = RegExp("[\u0660-\u0669]");
final RegExp _extendedArabicIndic = RegExp("[\u06f0-\u06f9]");

String _mapDigits(String value) => value
    .replaceAllMapped(_arabicIndic,
        (match) => (match.group(0)!.codeUnitAt(0) - 0x0660).toString())
    .replaceAllMapped(_extendedArabicIndic,
        (match) => (match.group(0)!.codeUnitAt(0) - 0x06f0).toString());

/// E.164-shaped text, never a guessed national format.
String? normalizeBookingPhone(String raw) {
  final stripped = _mapDigits(raw).trim().replaceAll(RegExp(r"[ \-.()]"), "");
  return RegExp(r"^\+[1-9][0-9]{7,14}$").hasMatch(stripped) ? stripped : null;
}

String? normalizeBookingEmail(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.length > 254) return null;
  if (RegExp(r"\s").hasMatch(value)) return null;
  final parts = value.split("@");
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
  return value;
}

/// The three wire shapes of a patient's time preference.
class BookingPreference {

  factory BookingPreference.fromJson(Map<String, Object?> json) =>
      BookingPreference(
        kind: (json["kind"] ?? "exact").toString(),
        date: json["date"]?.toString(),
        start: json["start"]?.toString(),
        end: json["end"]?.toString(),
        weekday: json["weekday"] is int ? json["weekday"]! as int : null,
        weeks: json["weeks"] is int ? json["weeks"]! as int : null,
        from: (json["from"] ?? "09:00").toString(),
        to: (json["to"] ?? "17:00").toString(),
      );
  BookingPreference({
    required this.kind,
    this.date,
    this.start,
    this.end,
    this.weekday,
    this.weeks,
    required this.from,
    required this.to,
  });

  final String kind; // exact | range | weekday
  final String? date;
  final String? start;
  final String? end;
  final int? weekday;
  final int? weeks;
  final String from;
  final String to;

  Map<String, Object?> toJson() => switch (kind) {
        "range" => {
            "kind": "range",
            "start": start,
            "end": end,
            "from": from,
            "to": to,
          },
        "weekday" => {
            "kind": "weekday",
            "weekday": weekday,
            "weeks": weeks,
            "from": from,
            "to": to,
          },
        _ => {"kind": "exact", "date": date, "from": from, "to": to},
      };
}

/// One request as the Worker publishes it.
class BookingRequest {

  factory BookingRequest.fromJson(Map<String, Object?> json) => BookingRequest(
        seq: (json["seq"]! as num).toInt(),
        requestId: json["requestId"].toString(),
        reference: (json["reference"] ?? "").toString(),
        name: (json["name"] ?? "").toString(),
        phone: (json["phone"] ?? "").toString(),
        email: json["email"]?.toString(),
        note: json["note"]?.toString(),
        preference: BookingPreference.fromJson(
            (json["preference"] as Map?)?.cast<String, Object?>() ?? const {}),
        candidateDates: (json["candidateDates"] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
        configRevision: (json["configRevision"] as num?)?.toInt() ?? 0,
        fromDate: (json["fromDate"] ?? "").toString(),
        toDate: (json["toDate"] ?? "").toString(),
        windowFrom: (json["windowFrom"] ?? "").toString(),
        windowTo: (json["windowTo"] ?? "").toString(),
        timeZone: (json["timeZone"] ?? "UTC").toString(),
        language: (json["language"] ?? "en").toString(),
        createdAt: (json["createdAt"] as num?)?.toInt() ?? 0,
        expiresAt: (json["expiresAt"] as num?)?.toInt() ?? 0,
        version: (json["version"] as num?)?.toInt() ?? 1,
        status: (json["status"] ?? "pending").toString(),
        handledAt: (json["handledAt"] as num?)?.toInt(),
        linkedId: json["linkedId"]?.toString(),
      );
  BookingRequest({
    required this.seq,
    required this.requestId,
    required this.reference,
    required this.name,
    required this.phone,
    this.email,
    this.note,
    required this.preference,
    required this.candidateDates,
    required this.configRevision,
    required this.fromDate,
    required this.toDate,
    required this.windowFrom,
    required this.windowTo,
    required this.timeZone,
    required this.language,
    required this.createdAt,
    required this.expiresAt,
    required this.version,
    required this.status,
    this.handledAt,
    this.linkedId,
  });

  final int seq;
  final String requestId;

  /// Short human-facing code (`1106-03`), what the patient is asked to quote.
  final String reference;
  final String name;
  final String phone;
  final String? email;
  final String? note;
  final BookingPreference preference;
  final List<String> candidateDates;
  final int configRevision;
  final String fromDate;
  final String toDate;
  final String windowFrom;
  final String windowTo;
  final String timeZone;
  final String language;
  final int createdAt;
  final int expiresAt;
  final int version;
  final String status;
  final int? handledAt;
  final String? linkedId;

  Map<String, Object?> toJson() => {
        "seq": seq,
        "requestId": requestId,
        "reference": reference,
        "name": name,
        "phone": phone,
        "email": email,
        "note": note,
        "preference": preference.toJson(),
        "candidateDates": candidateDates,
        "configRevision": configRevision,
        "fromDate": fromDate,
        "toDate": toDate,
        "windowFrom": windowFrom,
        "windowTo": windowTo,
        "timeZone": timeZone,
        "language": language,
        "createdAt": createdAt,
        "expiresAt": expiresAt,
        "version": version,
        "status": status,
        "handledAt": handledAt,
        "linkedId": linkedId,
      };

  bool get isPending => status == "pending";
  bool get isExpired => expiresAt <= DateTime.now().millisecondsSinceEpoch;

  BookingRequest copyWith({
    String? status,
    int? version,
    int? handledAt,
    String? linkedId,
  }) =>
      BookingRequest(
        seq: seq,
        requestId: requestId,
        reference: reference,
        name: name,
        phone: phone,
        email: email,
        note: note,
        preference: preference,
        candidateDates: candidateDates,
        configRevision: configRevision,
        fromDate: fromDate,
        toDate: toDate,
        windowFrom: windowFrom,
        windowTo: windowTo,
        timeZone: timeZone,
        language: language,
        createdAt: createdAt,
        expiresAt: expiresAt,
        version: version ?? this.version,
        status: status ?? this.status,
        handledAt: handledAt ?? this.handledAt,
        linkedId: linkedId ?? this.linkedId,
      );
}

/// The staff-readable booking credential published by the clinic's superuser.
class BookingClinicRecord {

  factory BookingClinicRecord.fromRecord(Map<String, dynamic> data) =>
      BookingClinicRecord(
        handle: (data["handle"] ?? "").toString(),
        clinicId: (data["clinic_id"] ?? "").toString(),
        publicUrl: (data["public_url"] ?? "").toString(),
        inboxKey: (data["inbox_key"] ?? "").toString(),
        keyRevision: (data["key_revision"] as num?)?.toInt() ?? 1,
      );
  BookingClinicRecord({
    required this.handle,
    required this.clinicId,
    required this.publicUrl,
    required this.inboxKey,
    required this.keyRevision,
  });

  final String handle;
  final String clinicId;
  final String publicUrl;
  final String inboxKey;
  final int keyRevision;

  Map<String, Object?> toPocketBase() => {
        "handle": handle,
        "clinic_id": clinicId,
        "public_url": publicUrl,
        "inbox_key": inboxKey,
        "key_revision": keyRevision,
      };
}

/// The superuser-only booking identity record.
class BookingAdminRecord {

  factory BookingAdminRecord.fromRecord(Map<String, dynamic> data) =>
      BookingAdminRecord(
        clinicId: (data["clinic_id"] ?? "").toString(),
        adminKey: (data["admin_key"] ?? "").toString(),
        pendingOperation: (data["pending_operation"] as Map?)
            ?.cast<String, Object?>(),
      );
  BookingAdminRecord({
    required this.clinicId,
    required this.adminKey,
    this.pendingOperation,
  });

  final String clinicId;
  final String adminKey;
  final Map<String, Object?>? pendingOperation;

  Map<String, Object?> toPocketBase() => {
        "clinic_id": clinicId,
        "admin_key": adminKey,
        "pending_operation": pendingOperation,
      };
}

