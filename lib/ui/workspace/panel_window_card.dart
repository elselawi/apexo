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
    this.badge,
    this.dirty = false,
    this.active = true,
    this.onSave,
    this.onRaise,
    this.onDragUpdate,
    this.attachments,
  });

  final PanelWindow window;
  final VoidCallback onMinimize;

  /// The colour the record's kind is known by — the panel's own for its record,
  /// the session's for a visit it carries.
  final Color? accent;

  /// The glyph that marks whose record this window edits — 📅 or 👤.
  final String? badge;

  /// Whether the record behind this window has work that has not been stored.
  final bool dirty;

  /// Whether this window is in front of the other floating windows.
  final bool active;

  /// Writes the record this window edits — the **session's** own save, not the
  /// panel's. Null for a window that has nothing to write, which then gets no
  /// Save button.
  final Future<void> Function()? onSave;

  /// Touching the window brings it in front of the others.
  final VoidCallback? onRaise;

  /// Dragging the window by its header.
  final ValueChanged<Offset>? onDragUpdate;

  /// The editors this window carries with it — a visit chart's labwork and
  /// photos — drawn as an attachment tray under its own content.
  final Widget? attachments;

  @override
  Widget build(BuildContext context) {
    final save = onSave;
    final tray = attachments;
    final actions = window.footerActions;
    return WindowShell(
      icon: window.icon,
      title: window.title,
      subtitle: window.subtitle?.call(),
      accent: accent,
      active: active,
      badge: badge,
      onRaise: onRaise,
      onDragUpdate: onDragUpdate,
      actions: [
        // The window's own ways into what it belongs to, before its controls: a
        // chart's list of visits sits beside "minimize", not in its footer.
        ...window.headerActions,
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
      footer: save == null &&
              window.footer == null &&
              tray == null &&
              actions.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (window.footer != null) window.footer!,
                if (tray != null) tray,
                if (save != null || actions.isNotEmpty)
                  WindowActions(
                    // The editing is done in here, so the saving is done in here
                    // too: one record, one write — this is the session's own, and
                    // it says whose it is.
                    key: WK.windowSaveFooter(window.id),
                    savable: save != null,
                    dirty: dirty,
                    onSave: save ?? () async {},
                    saveLabel: window.saveLabel ?? 'save',
                    // Closing a docked window only puts it away: the panel still
                    // holds the draft, so there is nothing to ask about.
                    confirmClose: false,
                    onClose: onMinimize,
                    extraActions: actions,
                  ),
              ],
            ),
      padding: window.padding,
      scrollable: window.scrollable,
      child: window.body,
    );
  }
}
