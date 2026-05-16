import 'package:fluent_ui/fluent_ui.dart';

class MoneyEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;
    if (text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final parts = text.split('.');
    final List<TextSpan> children = [];

    // Integer part
    children.add(TextSpan(
      text: parts[0],
      style: style?.copyWith(
        fontSize: (style.fontSize ?? 14) * 1.05,
        fontWeight: FontWeight.w500,
      ),
    ));

    // Fractional part (if exists)
    if (parts.length > 1) {
      children.add(TextSpan(
        text: '.${parts[1]}',
        style: style?.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.9,
          color: style.color?.withValues(alpha: 0.8),
        ),
      ));
    }

    return TextSpan(style: style, children: children);
  }
}
