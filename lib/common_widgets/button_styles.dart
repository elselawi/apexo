import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A button painted in one flat colour, for the rare action that must not look
/// like the WinUI standard button. Otherwise prefer [Button], [FilledButton] and
/// [IconButton]: their own styles are already the WinUI ones.
ButtonStyle filledButtonStyle(Color color) => ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(color),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );

/// The panel header's delete action: flat, with a critical-red label, and the
/// accent colour when the same button restores instead of deleting.
ButtonStyle panelDeleteButtonStyle(BuildContext context,
    {bool restoring = false}) {
  final theme = FluentTheme.of(context);
  return ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(
      restoring
          ? theme.accentColor.normal
          : theme.resources.systemFillColorCritical,
    ),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
  );
}

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

  /// Mirrors the icon in RTL; only for glyphs whose meaning has a direction.
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
        Flexible(
          child: Txt(
            txt,
            style: TextStyle(
              fontSize: size,
              color: inProgress
                  ? FluentTheme.of(context).inactiveColor.withValues(alpha: 0.3)
                  : null,
            ),
          ),
        )
      ],
    );
  }
}
