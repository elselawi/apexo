import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('colorsWithoutYellow', () {
    test('is non-empty', () {
      expect(colorsWithoutYellow, isNotEmpty);
    });

    test('length is one less than accent colors', () {
      expect(colorsWithoutYellow.length, Colors.accentColors.length - 1);
    });

    test('does not contain yellow (index 0 of accentColors)', () {
      final yellow = Colors.accentColors[0];
      expect(colorsWithoutYellow, isNot(contains(yellow)));
    });

    test('index access returns consistent color', () {
      final c1 = colorsWithoutYellow[0];
      final c2 = colorsWithoutYellow[0];
      expect(c1, c2);
    });

    test('contains valid Colors', () {
      for (final color in colorsWithoutYellow) {
        expect(color, isA<Color>());
      }
    });

    test('order is reversed from original', () {
      // The list skips index 0 and reverses
      final originalSkipped = Colors.accentColors.skip(1).toList();
      final expectedReversed = originalSkipped.reversed.toList();
      expect(colorsWithoutYellow, expectedReversed);
    });
  });
}
