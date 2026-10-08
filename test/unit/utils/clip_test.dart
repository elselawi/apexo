import 'package:apexo/utils/clip.dart';
import 'package:test/test.dart';

/// Every string Flutter's paragraph builder will accept has a surrogate pair
/// written *whole*; a string that ends in half of one makes
/// `RenderParagraph` throw `Invalid argument(s): string is not well-formed
/// UTF-16` and the frame is lost. `substring` counts code units, so it is the
/// way an app produces one — `clipCodePoints` is what several screens use
/// instead.
bool wellFormed(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= text.length) return false;
      final next = text.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

void main() {
  group('clipCodePoints', () {
    test('leaves a short string alone', () {
      expect(clipCodePoints('e2e patient', 14), 'e2e patient');
      expect(clipCodePoints('', 14), '');
    });

    test('cuts a long ASCII string at the same place as substring', () {
      const name = 'e2e patient 0001';
      expect(clipCodePoints(name, 14), name.substring(0, 14));
    });

    test('never returns half of a surrogate pair', () {
      // The dashboard-style label: an emoji prefix plus a name. `substring(0, 14)`
      // would land inside whatever emoji the name holds.
      const labels = [
        '👥 patients today',
        '🦷 a patient with a tooth emoji',
        '🥼 Dr 𝒜na', // 𝒜 is a single non-BMP code point (U+1D49C)
        '🧑‍💼 a family-emoji name',
      ];
      for (final label in labels) {
        for (var max = 1; max <= label.length; max++) {
          final clipped = clipCodePoints(label, max);
          expect(wellFormed(clipped), isTrue,
              reason: 'clipCodePoints(${label.inspect()}, $max) produced '
                  '${clipped.inspect()}, which is not well-formed UTF-16');
          expect(clipped.length, lessThanOrEqualTo(label.length));
        }
      }
    });

    test('counts an emoji as one character, so the cut is where it looks', () {
      // Nine code points: the emoji, a space, and the seven letters of
      // "patient" — `substring(0, 9)` would stop after "patie" and a half.
      expect(clipCodePoints('👥 patients today', 9), '👥 patient');
      expect(clipCodePoints('👥 patients today', 9).runes.length, 9);
      expect(clipCodePoints('👥 patients today', 8), '👥 patien');
    });

    test('a maximum of zero or less is empty, not an exception', () {
      expect(clipCodePoints('anything', 0), '');
      expect(clipCodePoints('anything', -3), '');
    });
  });

  group('fitsInCodePoints', () {
    test('counts code points, not code units', () {
      // Ten code points, eleven code units: the old `name.length > 17` guard
      // counts the emoji twice.
      const label = '👥 patients';
      expect(label.length, 11);
      expect(label.runes.length, 10);
      expect(fitsInCodePoints(label, 10), isTrue);
      expect(fitsInCodePoints(label, 9), isFalse);
    });
  });
}

extension on String {
  String inspect() => '"$this" (${codeUnits.join(',')})';
}
