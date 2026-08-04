import 'package:apexo/utils/iso_to_textual.dart';
import 'package:flutter_test/flutter_test.dart';

/// txt() returns capitalized keys (e.g., "Permanent" not "permanent").
/// This matcher does case-insensitive substring matching.
Matcher containsI(String substring) => predicate<String>(
      (s) => s.toLowerCase().contains(substring.toLowerCase()),
      'contains case-insensitively "$substring"',
    );

void main() {
  group('isoToTextualNotation — permanent teeth', () {
    test('all 32 permanent teeth are parsable', () {
      for (final q in [1, 2, 3, 4]) {
        for (var t = 1; t <= 8; t++) {
          final iso = '$q$t';
          final s = isoToTextualNotation(iso);
          expect(s, isNotEmpty, reason: 'ISO $iso should produce non-empty');
          expect(s, containsI('permanent'));
        }
      }
    });

    test('includes exact stage, jaw, direction, and tooth name semantics', () {
      final upperRight = isoToTextualNotation('11');
      final lowerLeft = isoToTextualNotation('33');

      expect(
          upperRight,
          allOf(containsI('permanent'), containsI('upper'), containsI('right'),
              containsI('central')));
      expect(
          lowerLeft,
          allOf(containsI('permanent'), containsI('lower'), containsI('left'),
              containsI('canine')));
    });
  });

  group('isoToTextualNotation — primary teeth', () {
    test('all 20 primary teeth are parsable', () {
      for (final q in [5, 6, 7, 8]) {
        for (var t = 1; t <= 5; t++) {
          final iso = '$q$t';
          final s = isoToTextualNotation(iso);
          expect(s, isNotEmpty, reason: 'ISO $iso should produce non-empty');
          expect(s, containsI('primary'));
        }
      }
    });
  });

  group('isoToTextualNotation — string normalization', () {
    test('whitespace is collapsed to single spaces', () {
      final s = isoToTextualNotation('11');
      expect(s.contains('  '), isFalse);
    });

    test('result is trimmed (no leading/trailing space)', () {
      final s = isoToTextualNotation('11');
      expect(s.trim(), s);
    });
  });

  group('isoToTextualNotation — edge cases', () {
    test('throws when input is empty (substring fails)', () {
      expect(() => isoToTextualNotation(''), throwsA(isA<RangeError>()));
    });

    test('handles malformed input gracefully', () {
      expect(() => isoToTextualNotation('1'), throwsA(isA<FormatException>()));
    });

    test('throws for non-numeric suffixes and omits unknown multi-digit teeth',
        () {
      expect(() => isoToTextualNotation('1x'), throwsFormatException);
      expect(
          isoToTextualNotation('110'),
          allOf(
              containsI('permanent'), containsI('upper'), containsI('right')));
    });

    test('returns blank localized parts for unknown quadrants or teeth', () {
      expect(isoToTextualNotation('00'), isEmpty);
      expect(
          isoToTextualNotation('19'),
          allOf(
              containsI('permanent'), containsI('upper'), containsI('right')));
      expect(isoToTextualNotation('59'),
          allOf(containsI('primary'), containsI('upper'), containsI('right')));
    });
  });

  group('isoToTextualNotation — Tooth name maps', () {
    test('namePermanent has 8 entries', () {
      expect(namePermanent.length, 8);
      expect(namePermanent[1], 'centralIncisor');
      expect(namePermanent[2], 'lateralIncisor');
      expect(namePermanent[3], 'canine');
      expect(namePermanent[4], 'firstPremolar');
      expect(namePermanent[5], 'secondPremolar');
      expect(namePermanent[6], 'firstMolar');
      expect(namePermanent[7], 'secondMolar');
      expect(namePermanent[8], 'thirdMolar');
    });

    test('namePrimary has 5 entries', () {
      expect(namePrimary.length, 5);
      expect(namePrimary[1], 'centralIncisor');
      expect(namePrimary[2], 'lateralIncisor');
      expect(namePrimary[3], 'canine');
      expect(namePrimary[4], 'firstMolar');
      expect(namePrimary[5], 'secondMolar');
    });

    test('stage map: quadrants 1-4 = permanent, 5-8 = primary', () {
      expect(stage[1], 'permanent');
      expect(stage[5], 'primary');
    });

    test('jaw map: 1,2 = upper; 3,4 = lower', () {
      expect(jaw[1], 'upper');
      expect(jaw[3], 'lower');
    });

    test('direction map: 1,4,5,8 = right; 2,3,6,7 = left', () {
      expect(direction[1], 'right');
      expect(direction[2], 'left');
    });
  });
}
