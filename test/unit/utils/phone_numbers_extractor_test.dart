import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// PhoneNumberExtractor tests.
///
/// The extractor reads the global settings store for its default region, but
/// national-number tests use the isolate override so that they remain
/// independent of persisted application settings.
void main() {
  group('PhoneNumberExtractor — isolation helpers', () {
    test('setIsoCountryCodeForIsolate sets the override', () {
      overrideIsoCountryCode = null;
      setIsoCountryCodeForIsolate('IQ');
      expect(overrideIsoCountryCode, 'IQ');
      overrideIsoCountryCode = null;
    });

    test('overrideIsoCountryCode defaults to null', () {
      overrideIsoCountryCode = null;
      expect(overrideIsoCountryCode, isNull);
    });

    test('overrideIsoCountryCode is globally settable', () {
      overrideIsoCountryCode = 'GB';
      expect(overrideIsoCountryCode, 'GB');
    });

    test('overrideIsoCountryCode survives being set to empty', () {
      overrideIsoCountryCode = '';
      expect(overrideIsoCountryCode, isEmpty);
    });
  });

  group('PhoneNumberExtractor — class structure', () {
    test('extract is a static method', () {
      // Verify the method exists and returns empty for empty input
      final results = PhoneNumberExtractor.extract('');
      expect(results, isEmpty);
    });

    test('extract returns List<String>', () {
      final results = PhoneNumberExtractor.extract('test');
      expect(results, isA<List<String>>());
    });

    test('extract with minLength parameter is callable', () {
      final results =
          PhoneNumberExtractor.extract('text without numbers', minLength: 10);
      expect(results, isEmpty);
    });

    test('extract with normalizeToE164 parameter is callable', () {
      final results = PhoneNumberExtractor.extract(
        'text',
        normalizeToE164: true,
        minLength: 5,
      );
      expect(results, isEmpty);
    });
  });

  group('PhoneNumberExtractor — international numbers', () {
    test('extracts a number surrounded by ordinary text', () {
      final results = PhoneNumberExtractor.extract(
        'Call the clinic at +964 770 123 4567 for an appointment.',
      );

      expect(results, ['+964 770 123 4567']);
    });

    test('extracts multiple numbers in their original order', () {
      final results = PhoneNumberExtractor.extract(
        'Primary: +964 770 123 4567; alternate: +1 202 555 0123.',
      );

      expect(results, ['+964 770 123 4567', '+1 202 555 0123']);
    });

    test('normalizes formatted international numbers to E.164', () {
      final results = PhoneNumberExtractor.extract(
        'Iraq: +964 (770) 123-4567 and US: +1 (202) 555-0123',
        normalizeToE164: true,
      );

      expect(results, ['+9647701234567', '+12025550123']);
    });

    test('supports 00 and 011 international prefixes', () {
      final results = PhoneNumberExtractor.extract(
        'Dial 00964 770 123 4567 or 0119647701234567.',
        normalizeToE164: true,
      );

      expect(results, ['+9647701234567', '+9647701234567']);
    });

    test('retains parentheses, hyphens, and spaces when not normalizing', () {
      final results = PhoneNumberExtractor.extract(
        'Phone: +964 (770) 123-4567',
      );

      expect(results, ['+964 (770) 123-4567']);
    });
  });

  group('PhoneNumberExtractor — national numbers and region override', () {
    setUp(() {
      setIsoCountryCodeForIsolate('IQ');
    });

    test('extracts a national number using the isolate country override', () {
      final results =
          PhoneNumberExtractor.extract('Local number: 0770 123 4567');

      expect(results, ['0770 123 4567']);
    });

    test('normalizes a national number using the isolate country override', () {
      final results = PhoneNumberExtractor.extract(
        'Call 0770-123-4567',
        normalizeToE164: true,
      );

      expect(results, ['+9647701234567']);
    });

    test('does not let a later token consume unrelated text', () {
      final results = PhoneNumberExtractor.extract(
        'Call 0770 123 4567 tomorrow at 10 30',
      );

      expect(results, ['0770 123 4567']);
    });
  });

  group('PhoneNumberExtractor — filtering and malformed input', () {
    setUp(() {
      setIsoCountryCodeForIsolate('IQ');
    });

    test('returns no results for null-like, empty, or whitespace-only text',
        () {
      expect(PhoneNumberExtractor.extract(''), isEmpty);
      expect(PhoneNumberExtractor.extract('   \n\t  '), isEmpty);
    });

    test('ignores alphabetic text and malformed phone-like fragments', () {
      final results = PhoneNumberExtractor.extract(
        'abc def +--- () 12-34 and not-a-number',
      );

      expect(results, isEmpty);
    });

    test('enforces the minimum digit length', () {
      final results = PhoneNumberExtractor.extract(
        'Short: 1234, valid: 0770 123 4567',
        minLength: 5,
      );

      expect(results, ['0770 123 4567']);
    });

    test('supports a custom minimum digit length', () {
      final results = PhoneNumberExtractor.extract(
        '0770 123 4567',
        minLength: 20,
      );

      expect(results, isEmpty);
    });

    test('handles punctuation between separate phone numbers', () {
      final results = PhoneNumberExtractor.extract(
        '[0770 123 4567] / (+964 770 123 4567)',
        normalizeToE164: true,
      );

      expect(results, ['+9647701234567', '+9647701234567']);
    });

    test('handles newlines and tabs as number-token whitespace', () {
      final results = PhoneNumberExtractor.extract(
        'Call +964\t770\n123 4567 now',
        normalizeToE164: true,
      );

      expect(results, ['+9647701234567']);
    });

    test(
        'does not return short fragments even with non-positive minimum length',
        () {
      expect(PhoneNumberExtractor.extract('Fragments 12 34', minLength: 0),
          isEmpty);
      expect(PhoneNumberExtractor.extract('Fragments 12 34', minLength: -1),
          isEmpty);
    });
  });

  tearDown(() {
    overrideIsoCountryCode = null;
  });
}
