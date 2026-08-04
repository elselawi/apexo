import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParsedPhoneNumber — international format', () {
    test('parses +1-555-123-4567 (US number)', () {
      final pn = ParsedPhoneNumber('+1-555-123-4567');
      expect(pn.countryCode, '1');
      expect(pn.nsn, '5551234567');
      expect(pn.e164, '+15551234567');
      expect(pn.isoCode, 'US');
    });

    test('parses +964 770 123 4567 (Iraq number)', () {
      final pn = ParsedPhoneNumber('+964 770 123 4567');
      expect(pn.countryCode, '964');
      expect(pn.isoCode, 'IQ');
    });

    test('parses number with dashes and parentheses', () {
      final pn = ParsedPhoneNumber('+1 (555) 123-4567');
      expect(pn.countryCode, '1');
      expect(pn.nsn, '5551234567');
    });

    test('parses international number with 00 prefix', () {
      final pn = ParsedPhoneNumber('0015551234567');
      expect(pn.countryCode, '1');
      expect(pn.e164, '+15551234567');
    });

    test('parses international number with 011 prefix', () {
      final pn = ParsedPhoneNumber('0111 555 123 4567');
      expect(pn.e164, '+15551234567');
    });
  });

  group('ParsedPhoneNumber — properties', () {
    test('rawInput preserves original input', () {
      final pn = ParsedPhoneNumber('+1 555-123-4567  ');
      expect(pn.rawInput, '+1 555-123-4567  ');
    });

    test('e164 returns canonical E.164 format', () {
      final pn = ParsedPhoneNumber('+1-555-123-4567');
      expect(pn.e164, '+15551234567');
    });

    test('toE164Format returns e164', () {
      final pn = ParsedPhoneNumber('+1-555-123-4567');
      expect(pn.toE164Format(), pn.e164);
    });

    test('toNationalFormat returns NSN (national significant number)', () {
      final pn = ParsedPhoneNumber('+1-555-123-4567');
      expect(pn.toNationalFormat(), isNotEmpty);
      expect(pn.toNationalFormat(), contains('555'));
    });

    test('toInternationalFormat returns formatted string with +', () {
      final pn = ParsedPhoneNumber('+1-555-123-4567');
      final fmt = pn.toInternationalFormat();
      expect(fmt.startsWith('+'), isTrue);
    });

    test('toString returns international format', () {
      final pn = ParsedPhoneNumber('+1-555-123-4567');
      expect(pn.toString(), pn.toInternationalFormat());
    });

    test('equality is based on e164', () {
      final a = ParsedPhoneNumber('+1-555-123-4567');
      final b = ParsedPhoneNumber('+1 555 123 4567');
      expect(a == b, isTrue);
    });

    test('hashCode is derived from e164', () {
      final a = ParsedPhoneNumber('+1-555-123-4567');
      final b = ParsedPhoneNumber('+1 555 123 4567');
      expect(a.hashCode, b.hashCode);
    });

    test('unequal canonical numbers are not equal', () {
      expect(ParsedPhoneNumber('+15551234567'),
          isNot(ParsedPhoneNumber('+12025550123')));
    });

    test('exposes validity and number-type classification', () {
      final pn = ParsedPhoneNumber('+9647701234567');

      expect(pn.isValid, isTrue);
      expect(pn.isMobile, isTrue);
      expect(pn.isFixedLine, isFalse);
    });
  });

  group('ParsedPhoneNumber — national numbers and invalid input', () {
    tearDown(() => overrideIsoCountryCode = null);

    test('uses the isolate ISO override for national numbers', () {
      overrideIsoCountryCode = 'IQ';
      final pn = ParsedPhoneNumber('0770.123.4567');

      expect(pn.e164, '+9647701234567');
      expect(pn.isoCode, 'IQ');
    });

    test('documents parser behavior for empty and non-numeric input', () {
      overrideIsoCountryCode = 'IQ';

      final empty = ParsedPhoneNumber('');
      final nonNumeric = ParsedPhoneNumber('not a phone number');
      expect(empty.isValid, isFalse);
      expect(nonNumeric.isValid, isFalse);
      expect(empty.e164, '+964');
      expect(nonNumeric.e164, '+964');
    });

    test('rejects an invalid national ISO override', () {
      overrideIsoCountryCode = 'NOT_A_COUNTRY';

      expect(() => ParsedPhoneNumber('07701234567'), throwsArgumentError);
    });
  });
}
