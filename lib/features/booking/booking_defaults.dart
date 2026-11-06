import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Defaults the claim form borrows from the clinic's own settings.

/// The dial code of an ISO country code such as `IQ`, or null when unknown.
String? bookingDialCodeForCountry(String isoCode) {
  final code = isoCode.trim().toUpperCase();
  if (code.isEmpty) return null;
  try {
    // The parser resolves the calling code from the region alone; the digits
    // only need to be well-formed enough to carry the country.
    final probe =
        PhoneNumber.parse("1", destinationCountry: IsoCode.values.byName(code));
    return "+${probe.countryCode}";
  } catch (_) {
    return null;
  }
}

/// Rewrites a locally formatted clinic number into E.164 using the clinic's
/// country. Numbers that already carry a country code are kept as they are.
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
