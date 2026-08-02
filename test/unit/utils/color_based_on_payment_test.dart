import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:apexo/utils/color_based_on_payment.dart';

void main() {
  group("colorBasedOnPayments", () {
    test('Returns blue when paid is greater than price', () {
      expect(colorBasedOnPayments(150.0, 100.0), Colors.blue);
    });

    test('Returns red when paid is less than price', () {
      expect(colorBasedOnPayments(50.0, 100.0), Colors.red);
    });

    test('Returns grey when paid is equal to price', () {
      expect(colorBasedOnPayments(100.0, 100.0), Colors.grey);
    });
  });
}
