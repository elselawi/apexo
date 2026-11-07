import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The frame every floating window shares: header, editor, optional footer.
class WindowShell extends StatelessWidget {
  const WindowShell({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.badge,
    this.actions = const <Widget>[],
    this.footer,
    this.padding = 10,
    this.scrollable = true,
    this.dirty = false,
    this.accent,
    this.active = true,
    this.onRaise,
    this.onDragUpdate,
  });

  final IconData icon;

  /// A localization key or a real name — translated here, at draw time.
  final String title;

  /// Whose window this is: the record's own name, over the window's label.
  final String? subtitle;

  /// The glyph that marks the record's kind — 📅 for a visit, 👤 for a patient.
  /// Two records share a row and their windows share labels ("Gallery").
  final String? badge;

  /// Header buttons, drawn after the title, spaced apart.
  final List<Widget> actions;

  /// The editor.
  final Widget child;

  final Widget? footer;

  final double padding;

  /// Whether this frame scrolls [child]; false for a body that scrolls itself.
  final bool scrollable;

  final bool dirty;

  final Color? accent;

  /// The frontmost window has a raised surface, a stronger edge and shadow.
  final bool active;

  /// Touching the window anywhere brings it in front of the others.
  final VoidCallback? onRaise;

  /// Dragging the header moves the window; null where windows do not move (the
  /// phone sheet, a window in a test).
  final ValueChanged<Offset>? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    // The body is flexible, so the host must cap the window's height.
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedHeight,
          'A window needs a bounded height: its body fills the room it is given, '
          'so whatever hosts it — WindowsLayer, a sheet, a panel — must cap it.',
        );
        return _buildFrame(context);
      },
    );
  }

  Widget _buildFrame(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final frame = Container(
      decoration: BoxDecoration(
        color: active
            ? resources.solidBackgroundFillColorBase
            : resources.solidBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? resources.surfaceStrokeColorDefault
              : resources.surfaceStrokeColorFlyout,
        ),
        boxShadow: [
          BoxShadow(
            color: resources.smokeFillColorDefault,
            offset: Offset(0, active ? 8 : 2),
            blurRadius: active ? 32 : 8,
          ),
          if (active)
            BoxShadow(
              color: resources.smokeFillColorDefault,
              offset: const Offset(0, 2),
              blurRadius: 6,
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: _buildBody()),
                  // The footer scrolls rather than overflowing a short window.
                  if (footer != null)
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: constraints.maxHeight),
                      child: SingleChildScrollView(child: footer!),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (onRaise == null) return frame;
    // Any touch brings the window forward, the way a click on a panel does.
    return Listener(onPointerDown: (_) => onRaise!(), child: frame);
  }

  Widget _buildBody() => LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          // Editors read the window's available size, not the full screen.
          return MediaQuery(
            data: media.copyWith(
                size: Size(
              constraints.maxWidth,
              constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : media.size.height,
            )),
            child: scrollable
                ? SingleChildScrollView(
                    padding: EdgeInsets.all(padding), child: child)
                : Padding(padding: EdgeInsets.all(padding), child: child),
          );
        },
      );

  Widget _buildHeader(FluentThemeData theme) {
    final line = subtitle;
    final header = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: active
            ? theme.resources.subtleFillColorSecondary
            : theme.resources.subtleFillColorTertiary,
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent ?? theme.accentColor),
          if (badge != null) ...[
            const SizedBox(width: 4),
            Txt(badge!, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (dirty) ...[
                      Tooltip(
                        message: txt('unsavedChanges'),
                        child: const UnsavedDot(),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Txt(
                        txt(title),
                        style:
                            theme.typography.bodyStrong?.copyWith(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (line != null && line.isNotEmpty)
                  Txt(
                    line,
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: actions,
              ),
            ),
        ],
      ),
    );
    if (onDragUpdate == null) return header;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      // The whole header drags; buttons in it still take their own taps.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onRaise?.call(),
        onPanUpdate: (details) => onDragUpdate!(details.delta),
        child: header,
      ),
    );
  }
}
