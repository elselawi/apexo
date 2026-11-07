import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Defaults the claim form borrows from the clinic's own settings.

/// The dial code of an ISO country code such as `IQ`, or null when unknown.
String? bookingDialCodeForCountry(String isoCode) {
  final code = isoCode.trim().toUpperCase();
  if (code.isEmpty) return null;
  try {
    // Only the country code is needed; the digits need only be well-formed.
    final probe =
        PhoneNumber.parse("1", destinationCountry: IsoCode.values.byName(code));
    return "+${probe.countryCode}";
  } catch (_) {
    return null;
  }
}

/// Rewrites a locally formatted clinic number into E.164 using [isoCode]; numbers
/// that already carry a country code are kept.
String? bookingInternationalPhone(String raw, String isoCode) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    if (trimmed.startsWith("+")) {
      return PhoneNumber.parse(trimmed).international;
    }
    final code = isoCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final parsed = PhoneNumber.parse(trimmed,
        destinationCountry: IsoCode.values.byName(code));
    return parsed.international;
  } catch (_) {
    return null;
  }
}
