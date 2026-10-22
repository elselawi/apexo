import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The panel's window switches: one button per window it can float, with its
/// icon, its name and the mark that says "this opens over here".
///
/// They sit under the panel's header, where the tab strip used to be, and read
/// as surfaces of their own — flat, outlined, no tray behind them — so the eye
/// reads a row of buttons rather than a toolbar. The buttons wrap, so every
/// window keeps its label on any screen and in any language, and the row is in
/// the panel's own layout so it can never cover an editor.
class WindowDock extends StatelessWidget {
  const WindowDock({
    super.key,
    required this.windows,
    required this.isOpen,
    required this.onToggle,
    required this.enabled,
    this.accent,
  });

  final List<PanelWindow> windows;
  final bool Function(PanelWindow window) isOpen;
  final void Function(PanelWindow window) onToggle;

  /// Per-window permission to open it — false while a window needs the record
  /// to be saved first.
  final bool Function(PanelWindow window) enabled;

  /// The colour the record's kind is known by — the panel's own.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final window in windows)
            _WindowButton(
              window: window,
              open: isOpen(window),
              enabled: enabled(window),
              accent: accent,
              onPressed: () => onToggle(window),
            ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.window,
    required this.open,
    required this.enabled,
    required this.accent,
    required this.onPressed,
  });

  final PanelWindow window;
  final bool open;
  final bool enabled;
  final Color? accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = this.accent ?? theme.accentColor;
    final idle = theme.resources.solidBackgroundFillColorBase;
    final muted = theme.inactiveColor;

    final Color foreground;
    final Color background;
    final Color border;
    if (!enabled) {
      foreground = muted.withValues(alpha: 0.55);
      background = Colors.grey.withValues(alpha: 0.06);
      border = Colors.grey.withValues(alpha: 0.18);
    } else if (open) {
      foreground = accent;
      background = Color.alphaBlend(accent.withValues(alpha: 0.10), idle);
      border = accent.withValues(alpha: 0.55);
    } else {
      foreground = theme.typography.body?.color ?? muted;
      background = idle;
      border = Colors.grey.withValues(alpha: 0.35);
    }

    return Tooltip(
      // The button keeps its label on one line; the tooltip is where a long
      // translation can still be read in full.
      message: txt(window.title),
      child: HoverButton(
        key: WK.windowToggle(window.id),
        onPressed: enabled ? onPressed : null,
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) && enabled && open == false;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 7),
            decoration: BoxDecoration(
              color: hovered
                  ? Color.alphaBlend(
                      Colors.grey.withValues(alpha: 0.12), background)
                  : background,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(window.icon, size: 15, color: foreground),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Txt(
                    txt(window.title),
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  open
                      ? WindowsIcons.chrome_minimize
                      : WindowsIcons.open_in_new_window,
                  size: 12,
                  color: foreground,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
