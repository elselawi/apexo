import 'package:apexo/features/settings/settings_stores.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// ISO country override for compute isolates, where [globalSettings] is unavailable.
String? overrideIsoCountryCode;

/// Set before spawning an isolate that calls [PhoneNumberExtractor].
void setIsoCountryCodeForIsolate(String code) {
  overrideIsoCountryCode = code;
}

/// Extracts valid phone numbers from any text.
class PhoneNumberExtractor {
  /// Finds valid phone numbers in [text], optionally normalizing them to E.164;
  /// [minLength] is the minimum digit count (default 5).
  static List<String> extract(
    String text, {
    bool normalizeToE164 = false,
    int minLength = 5,
  }) {
    final result = <String>[];

    final chunks = text.split(RegExp(r'[^\d+\-\(\)\s]+'));

    for (final chunk in chunks) {
      // Step 2: Extract individual space-separated tokens within this phone-like chunk.
      final tokens =
          chunk.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.isEmpty) continue;

      int i = 0;
      while (i < tokens.length) {
        PhoneNumber? longestValidNumber;
        int longestValidIndex = -1;
        String longestRawString = '';

        String currentRawString = '';

        // Step 3: Use a sliding window to reassemble tokens (handles numbers with spaces)
        for (int j = i; j < tokens.length; j++) {
          if (currentRawString.isEmpty) {
            currentRawString = tokens[j];
          } else {
            currentRawString += ' ${tokens[j]}';
          }
          // Enforce minimum digit count
          final digitCount =
              currentRawString.replaceAll(RegExp(r'\D'), '').length;
          if (digitCount < minLength) continue;

          // Try to parse the accumulated string window
          final phoneNumber = _parseNumber(
              currentRawString, globalSettings.get("ISO_country____").value);
          if (phoneNumber != null && phoneNumber.isValid()) {
            longestValidNumber = phoneNumber;
            longestValidIndex = j;
            longestRawString = currentRawString;
          }
        }

        // If a valid number was found, pick the longest match and advance the window past it
        if (longestValidNumber != null) {
          final output = normalizeToE164
              ? longestValidNumber.international
              : longestRawString;
          result.add(output);
          i = longestValidIndex + 1;
        } else {
          i++;
        }
      }
    }

    return result.toList();
  }

  /// Uses `phone_numbers_parser` to turn a string into a [PhoneNumber] object.
  static PhoneNumber? _parseNumber(String raw, String defaultRegion) {
    final trimmed = raw.trim();
    try {
      if (trimmed.startsWith('+') ||
          trimmed.startsWith('00') ||
          trimmed.startsWith('011')) {
        // International format – no region hint needed
        return PhoneNumber.parse(trimmed);
      } else {
        // Compute isolates have no store, so the pre-set override wins.
        final region = overrideIsoCountryCode ?? defaultRegion;
        return PhoneNumber.parse(
          trimmed,
          destinationCountry: IsoCode.values.byName(region),
        );
      }
    } catch (_) {
      // Parsing failed – not a valid phone number structure
      return null;
    }
  }
}
