import 'package:test/test.dart';
import 'package:apexo/utils/round.dart';

void main() {
  group('roundToPrecision', () {
    test('rounds to zero decimal places', () {
      expect(roundToPrecision(123.456, 0), 123);
    });

    test('rounds to one decimal place', () {
      expect(roundToPrecision(123.456, 1), 123.5);
    });

    test('rounds to two decimal places', () {
      expect(roundToPrecision(123.456, 2), 123.46);
    });

    test('rounds to three decimal places', () {
      expect(roundToPrecision(123.456, 3), 123.456);
    });

    test('rounds negative numbers correctly', () {
      expect(roundToPrecision(-123.456, 2), -123.46);
    });

    test('rounds to more decimal places than the number has', () {
      expect(roundToPrecision(123.4, 3), 123.4);
    });

    test('rounds using negative precision for tens and hundreds', () {
      expect(roundToPrecision(123.456, -1), 120);
      expect(roundToPrecision(123.456, -2), 100);
    });

    test('uses Dart rounding behavior for positive and negative half ties', () {
      expect(roundToPrecision(1.5, 0), 2);
      expect(roundToPrecision(-1.5, 0), -2);
    });

    test('rejects non-finite values through double.round', () {
      expect(() => roundToPrecision(double.nan, 2), throwsUnsupportedError);
      expect(
          () => roundToPrecision(double.infinity, 2), throwsUnsupportedError);
      expect(() => roundToPrecision(double.negativeInfinity, 2),
          throwsUnsupportedError);
    });
  });
}
