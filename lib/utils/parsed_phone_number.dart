import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Represents a phone number parsed from any input (national or international).
///
/// Provides synchronous access to country code, national number, ISO code,
/// number type, and formatted representations.
class ParsedPhoneNumber {
  final String rawInput;
  late final PhoneNumber parsed;
  late final bool _isValid;

  /// Parses [rawInput] using the given defaultRegion for national numbers.
  ///
  /// The input can be:
  /// - International format: starts with '+', '00', or '011'
  /// - National format: any number without international prefix, interpreted
  ///   as belonging to defaultRegion (e.g. '07701234567' for Iraq).
  ///
  /// Throws an [ArgumentError] if the input cannot be parsed into a valid
  /// phone number.
  ParsedPhoneNumber(this.rawInput) {
    // Clean input: remove spaces, dashes, parentheses, dots, etc.
    final cleaned = _normalize(rawInput);

    try {
      // Determine if international
      if (cleaned.startsWith('+') ||
          cleaned.startsWith('00') ||
          cleaned.startsWith('011')) {
        // International format – parse without region hint
        parsed = PhoneNumber.parse(cleaned);
      } else {
        // National format – use default region
        parsed = PhoneNumber.parse(
          cleaned,
          destinationCountry: IsoCode.values.byName(
            overrideIsoCountryCode ?? isoCC(),
          ),
        );
      }
      _isValid = parsed.isValid();
    } catch (e) {
      throw ArgumentError('Failed to parse phone number: $e');
    }
  }

  String _normalize(String input) {
    var value = input.trim();

    if (value.startsWith('00')) {
      value = '+${value.substring(2)}';
    }
    if (value.startsWith('011')) {
      value = '+${value.substring(3)}';
    }

    return value.replaceAll(RegExp(r'(?!^\+)\D'), '');
  }

  // ----------------------------------------------------------------------
  // Basic getters
  // ----------------------------------------------------------------------

  /// The E.164 representation (e.g. "+9647701234567").
  String get e164 => '+${parsed.countryCode}${parsed.nsn}';

  /// Numeric country dial code (e.g. "964", "1").
  String get countryCode => parsed.countryCode;

  /// National Number (e.g. "7701234567").
  String get nsn => parsed.nsn;

  /// Country dial code with '+' (e.g. "+964", "+1").
  String get countryDialCode => '+${parsed.countryCode}';

  /// ISO country code (e.g. "IQ", "US", "GB").
  String get isoCode => parsed.isoCode.name;

  /// True if the number is valid.
  bool get isValid => _isValid;

  // ----------------------------------------------------------------------
  // Number type detection
  // ----------------------------------------------------------------------

  bool get isMobile => parsed.isValid(type: PhoneNumberType.mobile);
  bool get isFixedLine => parsed.isValid(type: PhoneNumberType.fixedLine);

  // ----------------------------------------------------------------------
  // Formatting methods
  // ----------------------------------------------------------------------

  /// National format (e.g. "(212) 555-1234" for US, "0770 123 4567" for Iraq).
  String toNationalFormat() => parsed.formatNsn();

  /// International format with a space after country code (e.g. "+964 770 123 4567").
  String toInternationalFormat() {
    final full = e164;
    if (full.length > 2) {
      return '+${parsed.countryCode} ${parsed.formatNsn()}';
    }
    return full;
  }

  /// Returns the E.164 format (the same as [e164]).
  String toE164Format() => e164;

  // ----------------------------------------------------------------------
  // Comparison and equality
  // ----------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ParsedPhoneNumber && other.e164 == e164;
  }

  @override
  int get hashCode => e164.hashCode;

  @override
  String toString() => toInternationalFormat();
}
