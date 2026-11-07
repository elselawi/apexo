import 'package:apexo/features/booking/booking_defaults.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("claim form defaults", () {
    test("derives the dial code from the clinic's country", () {
      expect(bookingDialCodeForCountry("IQ"), "+964");
      expect(bookingDialCodeForCountry(" iq "), "+964");
      expect(bookingDialCodeForCountry("SA"), "+966");
      expect(bookingDialCodeForCountry("US"), "+1");
      expect(bookingDialCodeForCountry(""), isNull);
      expect(bookingDialCodeForCountry("XX"), isNull);
    });

    test("rewrites a national clinic number as E.164", () {
      expect(bookingInternationalPhone("07701234567", "IQ"), "+9647701234567");
      expect(bookingInternationalPhone("+9647518096323", "IQ"),
          "+9647518096323");
      expect(bookingInternationalPhone("", "IQ"), isNull);
      expect(bookingInternationalPhone("07", ""), isNull);
    });

    test("offers only languages the public page can render", () {
      expect(bookingLanguages.length, 10);
      expect(bookingLanguages.toSet().length, bookingLanguages.length);
      for (final code in bookingLanguages) {
        // A bare code in the picker was the reported complaint.
        expect(bookingLanguageName(code), isNot(code));
      }
    });

    test("prefers the device zone and always answers with a known name", () {
      final zone = bookingSystemTimeZone();
      if (zone != null) {
        expect(bookingTimeZoneNames(), contains(zone));
      }
    });
  });

  group("claim validation", () {
    BookingClinicConfig claim({String accent = ""}) => BookingClinicConfig(
          profile: BookingProfile(
            name: "Clinic",
            phone: "+9647518096323",
            address: "Street 1",
            welcome: "Welcome",
            accentColor: accent,
            defaultLanguage: "en",
          ),
          timeZone: "Asia/Baghdad",
          dialCode: "+964",
          hours: BookingWeeklyHours.empty(),
          closedDates: const [],
          contactEmail: null,
          enabled: false,
        );

    test("an empty accent colour is valid", () {
      // Hint text looked like a value but the field was empty, which the Worker rejected.
      expect(claim().validate(), isNull);
      expect(claim(accent: "  ").validate(), isNull);
      expect(claim(accent: "#0078d4").validate(), isNull);
      expect(claim(accent: "#0078D4").validate(), isNull);
      expect(claim(accent: "#12345").validate(), "profile.accentColor");
    });

    test("every shipped language is accepted", () {
      for (final code in bookingLanguages) {
        final config = claim();
        config.profile.defaultLanguage = code;
        expect(config.validate(), isNull, reason: code);
      }
      final config = claim();
      config.profile.defaultLanguage = "de";
      expect(config.validate(), "profile.defaultLanguage");
    });

    test("the dial code is validated after trimming", () {
      final config = claim();
      config.dialCode = " +964 ";
      expect(config.validate(), isNull);
      config.dialCode = "964";
      expect(config.validate(), "dialCode");
      config.dialCode = "+";
      expect(config.validate(), "dialCode");
    });
  });
}
