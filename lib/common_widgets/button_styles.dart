import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

const greyButtonStyle = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.grey),
  foregroundColor: WidgetStatePropertyAll(Colors.white),
);

ButtonStyle filledButtonStyle(Color color) => ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(color),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
    );

class ButtonContent extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const ButtonContent(
    this.icon,
    this.txt, {
    this.size,
    super.key,
    this.inProgress = false,
    this.flipInRtl = false,
  });

  final String txt;
  final IconData icon;
  final double? size;
  final bool inProgress;

  /// Whether the icon says something directional — "open in", "next", "back" —
  /// and must therefore be mirrored where the app reads right to left, the way
  /// the text beside it already is.
  final bool flipInRtl;

  @override
  Widget build(BuildContext context) {
    final Widget glyph = inProgress
        ? const SizedBox(
            height: 20,
            width: 20,
            child: ProgressRing(
              strokeWidth: 4,
            ))
        : Icon(icon, size: size);
    // Only the glyph turns: the label beside it keeps reading its own way.
    final mirrored =
        flipInRtl && Directionality.of(context) == TextDirection.rtl
            ? Transform.scale(scaleX: -1, child: glyph)
            : glyph;
    return Row(
      spacing: 5,
      mainAxisSize: MainAxisSize.min,
      children: [
        mirrored,
        Txt(
          txt,
          style: TextStyle(
            fontSize: size,
            color: inProgress
                ? FluentTheme.of(context).inactiveColor.withValues(alpha: 0.3)
                : null,
          ),
        )
      ],
    );
  }
}
