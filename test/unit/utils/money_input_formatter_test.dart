import 'package:apexo/utils/money_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The formatter class is private, so these tests exercise it through the
/// public [moneyInputFormatter] singleton's [TextInputFormatter.formatEditUpdate].
void main() {
  TextEditingValue fmt(String input, [String oldInput = '']) {
    return moneyInputFormatter.formatEditUpdate(
      TextEditingValue(text: oldInput),
      TextEditingValue(text: input),
    );
  }

  TextEditingValue fmtValue(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return moneyInputFormatter.formatEditUpdate(oldValue, newValue);
  }

  group('moneyInputFormatter basics', () {
    test('moneyInputFormatter is a TextInputFormatter', () {
      expect(moneyInputFormatter, isA<TextInputFormatter>());
    });

    test('empty input passes through unchanged', () {
      expect(fmt('').text, '');
    });

    test('non-digit-only input keeps selection pinned to the end', () {
      final result = fmt('1234');
      expect(result.selection.baseOffset, result.text.length);
      expect(result.selection.extentOffset, result.text.length);
    });
  });

  group('thousands separators', () {
    test('1234 becomes 1,234', () {
      expect(fmt('1234').text, '1,234');
    });

    test('12345 becomes 12,345', () {
      expect(fmt('12345').text, '12,345');
    });

    test('1234567 becomes 1,234,567', () {
      expect(fmt('1234567').text, '1,234,567');
    });

    test('values under 1000 are not grouped', () {
      expect(fmt('999').text, '999');
    });
  });

  group('leading zeros', () {
    test('007 becomes 7', () {
      expect(fmt('007').text, '7');
    });

    test('000 becomes 0', () {
      expect(fmt('000').text, '0');
    });
  });

  group('decimal handling', () {
    test('decimal input is preserved (12.50)', () {
      final result = fmt('12.50');
      expect(result.text, '12.50');
    });

    test('decimal with large integer part keeps grouping (1234.5)', () {
      expect(fmt('1234.5').text, '1,234.5');
    });

    test('leading dot starts with 0 (".5" → "0.5")', () {
      final result = fmt('.5');
      expect(result.text, '0.5');
    });

    test('trailing dot is kept ("5." → "5.")', () {
      expect(fmt('5.').text, '5.');
    });

    test('just a dot becomes "0."', () {
      expect(fmt('.').text, '0.');
    });

    test('multiple dots keep the first fractional group (1.2.3 → 1.2)', () {
      expect(fmt('1.2.3').text, '1.2');
    });

    test('repeated dots produce an empty fraction (1..2 → 1.)', () {
      expect(fmt('1..2').text, '1.');
    });

    test('fractional zeros are preserved (5.00)', () {
      expect(fmt('5.00').text, '5.00');
    });

    test('formatted integer part with decimals (0001234.5 → 1,234.5)', () {
      expect(fmt('0001234.5').text, '1,234.5');
    });
  });

  group('stripping non-numeric characters', () {
    test('letters are stripped (abc12x → 12)', () {
      expect(fmt('abc12x').text, '12');
    });

    test('only non-numeric text passes through (no digits → newValue)', () {
      final result = fmt('abc');
      expect(result.text, 'abc');
    });

    test('mixed digits and letters keep digits, then format (12a34 → 1,234)',
        () {
      expect(fmt('12a34').text, '1,234');
    });

    test(
        r'currency symbol stripped, separators re-applied ($1,234.56 → 1,234.56)',
        () {
      expect(fmt(r'$1,234.56').text, '1,234.56');
    });

    test('spaces inside numbers stripped, then formatted (Rs 1 234 → 1,234)',
        () {
      expect(fmt('Rs 1 234').text, '1,234');
    });
  });

  group('edit transitions', () {
    test('clearing an existing formatted value returns empty', () {
      expect(fmt('', '1,234').text, '');
    });

    test('huge integer overflow formats as infinity, not oldValue', () {
      // double.tryParse succeeds (returns Infinity) so the oldValue fallback
      // branch is never reached for overflow — it formats as "∞".
      final huge = '9' * 400;
      final result = fmt(huge);
      expect(result.text, '∞');
    });

    test('collapses an insertion cursor to the formatted end', () {
      final result = fmtValue(
        const TextEditingValue(
            text: '1,234', selection: TextSelection.collapsed(offset: 2)),
        const TextEditingValue(
            text: '19,234', selection: TextSelection.collapsed(offset: 2)),
      );

      expect(result.text, '19,234');
      expect(result.selection, const TextSelection.collapsed(offset: 6));
    });

    test('collapses replacement selections to the formatted end', () {
      final result = fmtValue(
        const TextEditingValue(
            text: '1,234',
            selection: TextSelection(baseOffset: 1, extentOffset: 4)),
        const TextEditingValue(
            text: '19', selection: TextSelection.collapsed(offset: 2)),
      );

      expect(result.text, '19');
      expect(result.selection, const TextSelection.collapsed(offset: 2));
    });

    test('does not support negative values and uses dot as the display decimal',
        () {
      expect(fmt('-1234.50').text, '1,234.50');
      expect(fmt('1234,50').text, '123,450');
    });

    test('preserves long fractions but ignores subsequent decimal segments',
        () {
      expect(fmt('1.12345678901234567890').text, '1.12345678901234567890');
      expect(fmt('1.2.3.4').text, '1.2');
    });
  });
}
