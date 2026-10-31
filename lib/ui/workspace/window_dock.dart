import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// One row of window switches, drawn as a single joined control: under a panel's
/// header for the windows it floats, and inside a record's body for its own
/// workspaces. Each switch carries its window's icon, its name and the mark that
/// says "this opens over here".
///
/// The row is drawn the same way in both places: equal segments filling the
/// panel's width, joined with no gap, only the row's outer corners rounded, and a
/// flat stroke instead of the library's per-button gradient so two neighbours
/// share one hairline where they meet. It sits in the panel's own layout, so it
/// can never cover an editor.
///
/// A window that is open is drawn as a filled button in the record's accent; the
/// closed ones stay neutral, so the theme owns the colours in light and dark
/// alike. A label too long for its segment is ellipsised — the tooltip carries
/// it in full.
class WindowDock extends StatelessWidget {
  const WindowDock({
    super.key,
    required this.windows,
    required this.isOpen,
    required this.onToggle,
    required this.enabled,
    this.accent,
    this.keyForWindow,
    this.dirty,
    this.padding = const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
  });

  final List<PanelWindow> windows;
  final bool Function(PanelWindow window) isOpen;
  final void Function(PanelWindow window) onToggle;

  /// Per-window permission to open it — false while a window needs the record
  /// to be saved first.
  final bool Function(PanelWindow window) enabled;

  /// The colour the record's kind is known by — the panel's own.
  final Color? accent;

  /// A second dock on the same screen can namespace its buttons.
  final Key Function(PanelWindow window)? keyForWindow;

  /// Whether a window's switch carries the unsaved dot — for the one window that
  /// leads to a record whose draft is dirty but whose windows are not on screen
  /// (a patient's Visits switch while a retained visit holds work, plan §2.4).
  final bool Function(PanelWindow window)? dirty;

  /// The row's inset from the panel. A bar drawn inside the record's body gives
  /// it the body's spacing instead of the dock's.
  final EdgeInsetsDirectional padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (var index = 0; index < windows.length; index++)
            Expanded(
              child: _WindowButton(
                window: windows[index],
                toggleKey: keyForWindow?.call(windows[index]) ??
                    WK.windowToggle(windows[index].id),
                first: index == 0,
                last: index == windows.length - 1,
                open: isOpen(windows[index]),
                enabled: enabled(windows[index]),
                accent: accent,
                dirty: dirty?.call(windows[index]) ?? false,
                onPressed: () => onToggle(windows[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.window,
    required this.toggleKey,
    required this.first,
    required this.last,
    required this.open,
    required this.enabled,
    required this.accent,
    required this.dirty,
    required this.onPressed,
  });

  final PanelWindow window;
  final Key toggleKey;

  /// Whether this button is at one end of the row. Only the ends keep rounded
  /// corners; the corners that meet a neighbour stay square, which is what lets
  /// the buttons touch as one shape.
  final bool first;
  final bool last;
  final bool open;
  final bool enabled;
  final Color? accent;

  /// Whether the record this window leads to holds unsaved work.
  final bool dirty;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = (this.accent ?? theme.accentColor).toAccentColor();

    final content = Row(
      children: [
        if (dirty) ...[
          const UnsavedDot(size: 7),
          const SizedBox(width: 6),
        ],
        Icon(window.icon, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Txt(
            txt(window.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.bodyStrong?.copyWith(
              fontSize: 12,
              // The typography's own colour wins over the button's foreground,
              // which is what left an open label dark on the accent fill.
              color: open && enabled
                  ? theme.resources.textOnAccentFillColorPrimary
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          open ? WindowsIcons.chrome_minimize : WindowsIcons.open_in_new_window,
          size: 12,
        ),
      ],
    );

    // Only the corners facing out of the row are rounded; the ones meeting a
    // neighbour stay square, which is what makes the buttons touch as one shape.
    const radius = Radius.circular(4);
    final corners = BorderRadiusDirectional.only(
      topStart: first ? radius : Radius.zero,
      bottomStart: first ? radius : Radius.zero,
      topEnd: last ? radius : Radius.zero,
      bottomEnd: last ? radius : Radius.zero,
    );
    final style = ButtonStyle(
      // Taller than a stock button: these are what the record is for, not one
      // more action among many.
      padding: const WidgetStatePropertyAll(
        EdgeInsetsDirectional.fromSTEB(11, 8, 11, 8),
      ),
      // The open segment is filled with the record's own accent, shaded for
      // hover and press the way the library shades the theme's accent.
      backgroundColor: open
          ? WidgetStateProperty.resolveWith((states) {
              if (states.isDisabled) {
                return theme.resources.accentFillColorDisabled;
              }
              if (states.isPressed) {
                return accent.tertiaryBrushFor(theme.brightness);
              }
              if (states.isHovered) {
                return accent.secondaryBrushFor(theme.brightness);
              }
              return accent.defaultBrushFor(theme.brightness);
            })
          : null,
      foregroundColor: open
          ? WidgetStateProperty.resolveWith(
              (states) => FilledButton.foregroundColor(theme, states),
            )
          : null,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: corners,
          // A flat stroke instead of the library's per-button gradient: two
          // gradients side by side would draw a seam where the pair joins.
          side: BorderSide(
            color: open
                ? theme.resources.controlStrokeColorOnAccentDefault
                : theme.resources.controlStrokeColorDefault,
          ),
        ),
      ),
    );

    final button = open
        ? FilledButton(
            key: toggleKey,
            style: style,
            onPressed: enabled ? onPressed : null,
            child: content,
          )
        : Button(
            key: toggleKey,
            style: style,
            onPressed: enabled ? onPressed : null,
            child: content,
          );
    return Tooltip(
      message: txt(window.title),
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}
