import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/ui/design/mica_backdrop.dart';
import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The frame every floating window shares: header, editor, optional footer.
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
    this.active = true,
    this.onRaise,
    this.onClose,
    this.closeDirty = false,
    this.closeHasChanges,
    this.closeButtonKey,
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

  /// Whether this frame scrolls [child]; false for a body that scrolls itself.
  final bool scrollable;

  final bool dirty;

  final Color? accent;

  /// The frontmost window has a raised surface, a stronger edge and shadow.
  final bool active;

  /// Touching the window anywhere brings it in front of the others.
  final VoidCallback? onRaise;

  /// The standard header close button; it may minimize a panel-backed window, or
  /// fully close a standalone one.
  final VoidCallback? onClose;

  /// Whether the window's close action is currently dirty and should prompt.
  final bool closeDirty;

  /// Re-checks whether the draft is still dirty before closing.
  final bool Function()? closeHasChanges;

  final Key? closeButtonKey;

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
    final materials = FluentMaterials.of(context);
    final frame = AcrylicSurface(
      radius: FluentMaterials.radiusSurface,
      blur: 20,
      color: active ? materials.acrylic : materials.card,
      borderColor: materials.strongStroke,
      shadows: active ? materials.windowShadow : materials.windowShadowInactive,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, materials),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: _buildBody()),
                  // The footer scrolls rather than overflowing a short window.
                  if (footer != null)
                    Container(
                      color: materials.glassTint,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: constraints.maxHeight),
                        child: SingleChildScrollView(child: footer!),
                      ),
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

  Widget _buildHeader(FluentThemeData theme, FluentMaterials materials) {
    final line = subtitle;
    final headerActions = <Widget>[...actions];
    if (onClose != null) {
      headerActions.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: WindowCloseButton(
              key: closeButtonKey ?? WK.windowHeaderClose,
              dirty: closeDirty,
              hasChanges: closeHasChanges,
              onClose: onClose!,
              compact: true,
            ),
          ),
        ),
      );
    }
    final header = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 6),
      decoration: BoxDecoration(
        color: materials.glassTint,
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Divider(
              direction: Axis.vertical,
              size: 20,
              style: DividerThemeData(
                  verticalMargin: const EdgeInsets.all(0),
                  decoration: BoxDecoration(
                      color: materials.strongStroke.withAlpha(70))),
            ),
          ),
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
          if (headerActions.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: headerActions,
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
