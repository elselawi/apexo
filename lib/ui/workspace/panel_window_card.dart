import 'dart:async';

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_actions.dart';
import 'package:apexo/ui/workspace/window_shell.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A panel's window while it is floated: the shared frame, plus the one control
/// a window always has — minimize, spelled out rather than hidden behind a
/// glyph.
///
/// The window goes back to the panel's dock; it never outlives the panel that
/// opened it, so it has no close of its own. Its header is also what you drag it
/// by.
class PanelWindowCard extends StatelessWidget {
  const PanelWindowCard({
    super.key,
    required this.window,
    required this.onMinimize,
    this.accent,
    this.dirty = false,
    this.onSave,
    this.onRaise,
    this.onDragUpdate,
  });

  final PanelWindow window;
  final VoidCallback onMinimize;

  /// The colour the record's kind is known by — the panel's own.
  final Color? accent;

  /// Whether the record behind this window has work that has not been stored.
  final bool dirty;

  /// Writes the record this window edits — the panel's own save. Null for a
  /// window that has nothing to write, which then gets no Save button.
  final Future<void> Function()? onSave;

  /// Touching the window brings it in front of the others.
  final VoidCallback? onRaise;

  /// Dragging the window by its header.
  final ValueChanged<Offset>? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final save = onSave;
    return WindowShell(
      icon: window.icon,
      title: window.title,
      subtitle: window.subtitle?.call(),
      accent: accent,
      onRaise: onRaise,
      onDragUpdate: onDragUpdate,
      actions: [
        Button(
          key: WK.windowMinimize(window.id),
          onPressed: onMinimize,
          style: greyButtonStyle.copyWith(
            padding: const WidgetStatePropertyAll(
              EdgeInsetsDirectional.fromSTEB(8, 2, 10, 2),
            ),
            textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11)),
          ),
          child: ButtonContent(
            WindowsIcons.chrome_minimize,
            txt('minimize'),
            size: 11,
          ),
        ),
      ],
      footer: save == null && window.footer == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (window.footer != null) window.footer!,
                if (save != null)
                  WindowActions(
                    // The editing is done in here, so the saving is done in here
                    // too: one record, one write — this is the panel's own.
                    key: WK.windowSaveFooter(window.id),
                    savable: true,
                    dirty: dirty,
                    onSave: save,
                    // Closing a docked window only puts it away: the panel still
                    // holds the draft, so there is nothing to ask about.
                    confirmClose: false,
                    onClose: onMinimize,
                  ),
              ],
            ),
      padding: window.padding,
      scrollable: window.scrollable,
      child: window.body,
    );
  }
}
