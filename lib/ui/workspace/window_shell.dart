import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The frame every floating window shares: a header naming it, the editor, and
/// anything the window pins under it.
///
/// One frame for a panel's windows and for a chart opened on its own keeps the
/// app's windows looking like one another — the same corners, the same header,
/// the same elevation — instead of as many near-copies as there are features.
class WindowShell extends StatelessWidget {
  const WindowShell({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.footer,
    this.padding = 10,
    this.scrollable = true,
    this.dirty = false,
    this.accent,
    this.onRaise,
    this.onDragUpdate,
  });

  final IconData icon;

  /// A localization key or a real name — translated here, at draw time.
  final String title;

  /// Whose window this is: the record's own name, over the window's label.
  final String? subtitle;

  /// Header buttons, drawn after the title, spaced apart.
  final List<Widget> actions;

  /// The editor.
  final Widget child;

  final Widget? footer;

  final double padding;

  /// Whether this frame scrolls [child]. `false` for a body that scrolls
  /// itself.
  final bool scrollable;

  /// Whether the draft behind this window has work the record does not: a dot
  /// beside the title says so, so the window holding it is recognisable at a
  /// glance and from the panel's dock.
  final bool dirty;

  /// The colour the record's kind is known by (a patient, a visit, an order):
  /// the icon wears it, so two windows of the same label are still told apart by
  /// which record they belong to.
  final Color? accent;

  /// Touching the window anywhere brings it in front of the others.
  final VoidCallback? onRaise;

  /// Dragging the header moves the window. Null where windows do not move — the
  /// phone sheet, a window in a test.
  final ValueChanged<Offset>? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    // A window is as tall as its content, and never taller than the room it was
    // given: without a ceiling the flexible body below has nothing to shrink
    // against, and a body that fills its space would be asked to fill infinity.
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
    final frame = Container(
      decoration: BoxDecoration(
        color: theme.resources.solidBackgroundFillColorBaseAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(120)),
        boxShadow: kElevationToShadow[16],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final media = MediaQuery.of(context);
                // A window's body reads the width it was given, not the width
                // of the screen: the dental chart picks its layout from
                // MediaQuery, and a chart in a narrow card must draw the
                // compact arch instead of the panoramic one.
                return MediaQuery(
                  data: media.copyWith(
                    size: Size(
                      constraints.maxWidth,
                      constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : media.size.height,
                    ),
                  ),
                  child: scrollable
                      ? SingleChildScrollView(
                          padding: EdgeInsets.all(padding),
                          child: child,
                        )
                      : Padding(
                          padding: EdgeInsets.all(padding),
                          child: child,
                        ),
                );
              },
            ),
          ),
          if (footer != null) footer!,
        ],
      ),
    );
    if (onRaise == null) return frame;
    // Any touch brings the window forward, the way a click on a panel does.
    return Listener(onPointerDown: (_) => onRaise!(), child: frame);
  }

  Widget _buildHeader(FluentThemeData theme) {
    final line = subtitle;
    final header = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent ?? theme.accentColor),
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
      // The whole header is the handle: the buttons in it still take their own
      // taps, and a pan that starts anywhere else on it moves the window.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onRaise?.call(),
        onPanUpdate: (details) => onDragUpdate!(details.delta),
        child: header,
      ),
    );
  }
}
