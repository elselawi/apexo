import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:apexo/utils/color_based_on_payment.dart';

void main() {
  group("colorBasedOnPayments", () {
    test('Returns blue when paid is greater than price', () {
      expect(colorBasedOnPayments(150.0, 100.0), Colors.blue);
    });

    test('Returns red when paid is less than price', () {
      expect(colorBasedOnPayments(50.0, 100.0), Colors.warningPrimaryColor);
    });

    test('Returns grey when paid is equal to price', () {
      expect(colorBasedOnPayments(100.0, 100.0), null);
    });

    test('treats zero totals according to the comparison result', () {
      expect(colorBasedOnPayments(0, 0), isNull);
      expect(colorBasedOnPayments(1, 0), Colors.blue);
      expect(colorBasedOnPayments(0, 1), Colors.warningPrimaryColor);
    });

    test('compares negative totals without special casing', () {
      expect(colorBasedOnPayments(-5, -10), Colors.blue);
      expect(colorBasedOnPayments(-10, -5), Colors.warningPrimaryColor);
      expect(colorBasedOnPayments(-5, -5), isNull);
    });

    test('returns null when a comparison contains NaN', () {
      expect(colorBasedOnPayments(double.nan, 100), isNull);
      expect(colorBasedOnPayments(100, double.nan), isNull);
    });
  });
}
