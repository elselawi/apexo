import 'package:apexo/utils/money_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBuildContext extends Fake implements BuildContext {}

void main() {
  group('MoneyEditingController', () {
    test('extends TextEditingController', () {
      final ctrl = MoneyEditingController();
      expect(ctrl, isA<TextEditingController>());
      ctrl.dispose();
    });

    test('text property is empty by default', () {
      final ctrl = MoneyEditingController();
      expect(ctrl.text, isEmpty);
      ctrl.dispose();
    });

    test('text can be set and read', () {
      final ctrl = MoneyEditingController();
      ctrl.text = '123.45';
      expect(ctrl.text, '123.45');
      ctrl.dispose();
    });
  });

  group('MoneyEditingController.buildTextSpan', () {
    final context = _FakeBuildContext();

    TextSpan buildSpan(
      MoneyEditingController controller, {
      TextStyle? style,
      bool withComposing = false,
    }) {
      return controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    TextSpan childAt(TextSpan span, int index) =>
        span.children![index] as TextSpan;

    List<String?> childTexts(TextSpan span) =>
        span.children!.cast<TextSpan>().map((child) => child.text).toList();

    test('empty text delegates to the base controller span', () {
      final controller = MoneyEditingController();
      const style = TextStyle(fontSize: 20, color: Colors.blue);
      final span = buildSpan(controller, style: style);

      expect(span.text, isEmpty);
      expect(span.style, style);
      expect(span.children, isNull);
      controller.dispose();
    });

    test('integer-only text has one emphasized span', () {
      final controller = MoneyEditingController()..text = '1,234';
      const style = TextStyle(fontSize: 20, color: Colors.blue);
      final span = buildSpan(controller, style: style);
      final children = span.children!;

      expect(span.text, isNull);
      expect(children, hasLength(1));
      expect(childAt(span, 0).text, '1,234');
      expect(childAt(span, 0).style!.fontSize, 21);
      expect(childAt(span, 0).style!.fontWeight, FontWeight.w500);
      expect(childAt(span, 0).style!.color, Colors.blue);
      controller.dispose();
    });

    test('decimal text renders integer and fractional spans separately', () {
      final controller = MoneyEditingController()..text = '123.45';
      const style = TextStyle(fontSize: 20, color: Colors.red);
      final span = buildSpan(controller, style: style);
      final children = span.children!;

      expect(children, hasLength(2));
      expect(childAt(span, 0).text, '123');
      expect(childAt(span, 0).style!.fontSize, 21);
      expect(childAt(span, 0).style!.fontWeight, FontWeight.w500);
      expect(childAt(span, 1).text, '.45');
      expect(childAt(span, 1).style!.fontSize, 18);
      expect(childAt(span, 1).style!.color, Colors.red.withValues(alpha: 0.8));
      controller.dispose();
    });

    test('leaves child styles null when no style is supplied', () {
      final controller = MoneyEditingController()..text = '12.3';
      final span = buildSpan(controller);

      // `style?.copyWith(...)` returns null when no base style is supplied.
      expect(childAt(span, 0).style, isNull);
      expect(childAt(span, 1).style, isNull);
      controller.dispose();
    });

    test('uses the default font size when the supplied style omits it', () {
      final controller = MoneyEditingController()..text = '12.3';
      const style = TextStyle(color: Colors.blue);
      final span = buildSpan(controller, style: style);

      expect(childAt(span, 0).style!.fontSize, closeTo(14.7, 0.000001));
      expect(childAt(span, 1).style!.fontSize, closeTo(12.6, 0.000001));
      expect(childAt(span, 1).style!.color, Colors.blue.withValues(alpha: 0.8));
      controller.dispose();
    });

    test('retains a null fractional color when the style has no color', () {
      final controller = MoneyEditingController()..text = '12.3';
      const style = TextStyle(fontSize: 20);
      final span = buildSpan(controller, style: style);

      expect(childAt(span, 1).style!.color, isNull);
      controller.dispose();
    });

    test('keeps a trailing decimal point in the fractional span', () {
      final controller = MoneyEditingController()..text = '123.';
      final span = buildSpan(controller);

      expect(childTexts(span), ['123', '.']);
      controller.dispose();
    });

    test('handles a leading decimal point with an empty integer span', () {
      final controller = MoneyEditingController()..text = '.50';
      final span = buildSpan(controller);

      expect(childTexts(span), ['', '.50']);
      controller.dispose();
    });

    test('uses only the first fractional segment for multiple decimal points',
        () {
      final controller = MoneyEditingController()..text = '12.34.56';
      final span = buildSpan(controller);

      expect(childTexts(span), ['12', '.34']);
      controller.dispose();
    });

    test('does not change span structure when composing is enabled', () {
      final controller = MoneyEditingController()..text = '12.34';

      final normal = buildSpan(controller);
      final composing = buildSpan(controller, withComposing: true);

      expect(
        childTexts(composing),
        childTexts(normal),
      );
      controller.dispose();
    });
  });
}
