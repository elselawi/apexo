import 'package:apexo/features/booking/booking_canonical.dart';
import 'package:apexo/features/booking/booking_clinic_service.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canonical fixtures are mirrored by `test/validate.test.ts` in
/// `apexo-booking-worker`; changing one side fails here too.
void main() {
  group("canonical JSON", () {
    test("sorts keys by UTF-16 code unit and keeps array order", () {
      expect(
          canonicalJson({
            "b": 1,
            "a": [2, 1],
            "A": "x"
          }),
          '{"A":"x","a":[2,1],"b":1}');
    });

    test("matches the operation-envelope fixture", () {
      final encoded = canonicalJson({
        "action": "register",
        "initialConfig": null,
        "version": 1,
      });
      expect(encoded, '{"action":"register","initialConfig":null,"version":1}');
      // Computed by the Worker's SHA-256 over the same bytes.
      expect(sha256Hex(encoded),
          "60cb5912d823720e3b6095bf6a85450a4b8c18993c88c5d221cb6d92b0312025");
    });

    test("escapes control characters minimally", () {
      expect(canonicalJson("é\u0001\"\\"), '"é\\u0001\\"\\\\"');
    });

    test("rejects doubles and lone surrogates", () {
      expect(() => canonicalJson({"value": 1.5}), throwsFormatException);
      expect(() => canonicalJson("\ud800"), throwsFormatException);
    });
  });

  group("phone normalization", () {
    test("maps Arabic-Indic and Persian digits", () {
      expect(normalizeBookingPhone("+٩٦٦ ٥٥ ١٢٣ ٤٥٦٧"), "+966551234567");
      expect(normalizeBookingPhone("+۹۶۶۵۵۱۲۳۴۵۶۷"), "+966551234567");
      expect(normalizeBookingPhone("+966 (55) 123-4567"), "+966551234567");
    });

    test("refuses national formats", () {
      expect(normalizeBookingPhone("0551234567"), isNull);
      expect(normalizeBookingPhone("+0123456789"), isNull);
      expect(normalizeBookingPhone("+966551"), isNull);
    });
  });

  group("weekly hours", () {
    test("requires seven ordered non-overlapping days", () {
      expect(BookingWeeklyHours.empty().validate("hours"), isNull);

      final overlapping = BookingWeeklyHours({
        ...BookingWeeklyHours.empty().days,
        "mon": [
          ["09:00", "12:00"],
          ["11:00", "13:00"],
        ],
      });
      expect(overlapping.validate("hours"), isNotNull);

      final reversed = BookingWeeklyHours({
        ...BookingWeeklyHours.empty().days,
        "mon": [
          ["13:00", "09:00"],
        ],
      });
      expect(reversed.validate("hours"), isNotNull);
    });

    test("intersects two weekly hour sets", () {
      final clinic = BookingWeeklyHours({
        ...BookingWeeklyHours.empty().days,
        "mon": [
          ["09:00", "17:00"],
        ],
      });
      final narrowed = BookingWeeklyHours({
        ...BookingWeeklyHours.empty().days,
        "mon": [
          ["08:00", "12:00"],
        ],
      });
      expect(clinic.intersect(narrowed)["mon"], [
        ["09:00", "12:00"]
      ]);
    });
  });

  group("clinic clock", () {
    test("adds calendar days instead of 24-hour increments", () {
      expect(bookingAddDays("2026-12-31", 1), "2027-01-01");
      expect(bookingAddDays("2028-02-28", 1), "2028-02-29");
      expect(bookingWeekdayOf("2026-11-09"), 1);
    });

    test("reports a DST gap and a fold", () {
      final gap =
          bookingClinicMomentToLocal("2026-03-29", "02:30", "Europe/Berlin");
      expect(gap.local, isNull);
      expect(gap.gap, isTrue);
      final fold =
          bookingClinicMomentToLocal("2026-10-25", "02:30", "Europe/Berlin");
      expect(fold.local, isNotNull);
      expect(fold.ambiguous, isTrue);
    });

    test("reports a non-hour DST fold", () {
      final fold = bookingClinicMomentToLocal(
          "2026-04-05", "01:45", "Australia/Lord_Howe");
      expect(fold.local, isNotNull);
      expect(fold.ambiguous, isTrue);
    });

    test("formats in the clinic zone", () {
      final instant = DateTime.utc(2026, 11, 20, 13);
      expect(bookingClinicDate(instant.millisecondsSinceEpoch, "Asia/Riyadh"),
          "2026-11-20");
      expect(
          bookingClinicTimeLabel(instant.millisecondsSinceEpoch, "Asia/Riyadh"),
          "16:00");
    });
  });

  group("suggested moment", () {
    BookingWeeklyHours weekly(List<List<String>> monday) => BookingWeeklyHours({
          ...BookingWeeklyHours.empty().days,
          "mon": monday,
        });

    BookingRequest request({List<String> dates = const ["2026-11-09"]}) =>
        BookingRequest(
          seq: 1,
          requestId: "req00000000001",
          reference: "1109-01",
          name: "Jane Doe",
          phone: "+966551234567",
          preference: BookingPreference(
            kind: "exact",
            date: "2026-11-09",
            from: "16:00",
            to: "21:00",
          ),
          candidateDates: dates,
          configRevision: 1,
          fromDate: "2026-11-09",
          toDate: "2026-11-09",
          windowFrom: "16:00",
          windowTo: "21:00",
          timeZone: "Asia/Riyadh",
          language: "en",
          createdAt: 0,
          expiresAt: DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch,
          version: 1,
          status: "pending",
        );

    test("picks the first future intersection", () {
      final suggestion = suggestedBookingMoment(
        request(),
        weekly([
          ["17:00", "20:00"],
        ]),
        now: DateTime.utc(2026, 11, 1),
      );
      expect(suggestion?.local, isNotNull);
      expect(suggestion?.needsManualConfirmation, isFalse);
    });

    test("returns nothing when the request is closed out", () {
      expect(
        suggestedBookingMoment(
          request(),
          weekly([
            ["09:00", "12:00"],
          ]),
          now: DateTime.utc(2026, 11, 1),
        ),
        isNull,
      );
    });

    test("never suggests the already-started current minute", () {
      final now = DateTime.utc(2026, 11, 9, 14, 20, 45);
      final suggestion = suggestedBookingMoment(
          request(),
          weekly([
            ["17:00", "20:00"]
          ]),
          now: now);
      expect(suggestion!.local!.isAfter(now), isTrue);
      expect(
          bookingClinicTimeLabel(
              suggestion.local!.millisecondsSinceEpoch, "Asia/Riyadh"),
          "17:21");
    });

    test("honours closed dates", () {
      expect(
        suggestedBookingMoment(
          request(),
          weekly([
            ["17:00", "20:00"],
          ]),
          closedDates: const ["2026-11-09"],
          now: DateTime.utc(2026, 11, 1),
        ),
        isNull,
      );
    });
  });

  group("pending operation allowlist", () {
    BookingClinicConfig validConfig() => BookingClinicConfig(
          profile:
              BookingProfile(name: "Jim Dental Clinic", phone: "+966551234567"),
          timeZone: "UTC",
          dialCode: "+966",
          hours: BookingWeeklyHours.empty(),
          closedDates: const [],
        );

    Map<String, Object?> attempt({
      Map<String, Object?>? config,
      String action = "register",
    }) =>
        {
          "action": action,
          "handle": "jimclinic",
          "clinicId": "0123456789abcdef0123456789abcdef",
          "serverUrl": "https://pb.hospital-clinic.dev",
          "challenge": "c" * 64,
          "adminKey": "A" * 43,
          "inboxKey": "B" * 43,
          "initialConfig":
              action == "register" ? (config ?? validConfig().toJson()) : null,
        };

    test("accepts a well-formed register attempt", () {
      final parsed = BookingPendingOperation.tryParse(attempt());
      expect(parsed, isNotNull);
      expect(parsed!.action, "register");
    });

    test("rejects unknown fields, duplicate keys and bad actions", () {
      expect(
          BookingPendingOperation.tryParse({
            ...attempt(),
            "extra": true,
          }),
          isNull);
      final duplicateKeys = attempt()..["inboxKey"] = "A" * 43;
      expect(BookingPendingOperation.tryParse(duplicateKeys), isNull);
      expect(
          BookingPendingOperation.tryParse({
            ...attempt(action: "recover"),
            "initialConfig": validConfig().toJson(),
          }),
          isNull);
    });

    test("treats malformed persisted JSON as an invalid attempt", () {
      expect(BookingPendingOperation.tryParse({1: "not a string key"}), isNull);
      expect(
          BookingPendingOperation.tryParse({
            ...attempt(),
            "initialConfig": {"profile": "not an object"}
          }),
          isNull);
    });

    test("rejects an unsupported server origin", () {
      expect(
          BookingPendingOperation.tryParse({
            ...attempt(),
            "serverUrl": "http://pb.hospital-clinic.dev",
          }),
          isNull);
    });

    test("normalizes text the same way the Worker does", () {
      final config = BookingClinicConfig(
        profile: BookingProfile(
          name: "  Jim Dental Clinic  ",
          phone: "+966 55 123 4567",
          accentColor: " #AABBCC ",
        ),
        timeZone: "UTC",
        dialCode: "+966",
        hours: BookingWeeklyHours.empty(),
        closedDates: const [],
      );
      final normalized = config.normalizedForProof();
      expect(normalized.profile.name, "Jim Dental Clinic");
      expect(normalized.profile.phone, "+966551234567");
      expect(normalized.profile.accentColor, "#aabbcc");
      expect(normalized.contactEmail, isNull);
      expect(normalized.enabled, isFalse);
    });
  });
}
