import 'dart:async';

import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The Save a window carries when it stands on its own, beside the Close that
/// goes with it.
///
/// Save is offered only by a window that writes something ([savable]); Close
/// asks before throwing away unsaved work, and reads as Cancel while there is
/// work to lose.
///
/// A window that is *docked* to a panel sets [confirmClose] to false: closing it
/// puts it back in the panel's dock and loses nothing — the draft, and the panel's
/// own Save, are still there.
class WindowActions extends StatefulWidget {
  const WindowActions({
    super.key,
    required this.savable,
    required this.dirty,
    required this.onSave,
    required this.onClose,
    this.hasChanges,
    this.onSaved,
    this.confirmClose = true,
  });

  /// Whether the window writes anything at all. A list or a scan does not, and
  /// gets Close alone.
  final bool savable;

  /// Whether the draft differs from what was stored, as last sampled. Its owner
  /// samples it once — the header's Close needs the same answer as this one.
  final bool dirty;

  /// The same question, asked live: a sample can be a beat behind the typing.
  final bool Function()? hasChanges;

  final Future<void> Function() onSave;
  final VoidCallback onClose;

  /// Whether closing has to ask first. True for a window that stands on its own
  /// — closing it destroys the only copy of the draft — and false for one docked
  /// to its panel, where closing only puts it away.
  final bool confirmClose;

  /// Told after a save lands, so the window can re-read whether it is clean.
  final VoidCallback? onSaved;

  @override
  State<WindowActions> createState() => _WindowActionsState();
}

class _WindowActionsState extends State<WindowActions> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
      widget.onSaved?.call();
    } catch (e, s) {
      showErrorMessage(e, 'savingFailed');
      logger('Saving a floating window failed', s);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dirty = widget.dirty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.savable)
            IconButton(
              key: WK.windowSave,
              // Pressable even while the sample still says "clean": a draft is
              // written in place, and a save that has nothing to write costs
              // nothing — while a Save that ignores the press looks broken.
              onPressed: _saving ? null : _save,
              style: greyButtonStyle.copyWith(
                textStyle:
                    const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
                backgroundColor: WidgetStatePropertyAll(
                  dirty ? Colors.blue : Colors.grey.withValues(alpha: 0.25),
                ),
              ),
              icon: ButtonContent(
                WindowsIcons.save,
                txt('save'),
                inProgress: _saving,
              ),
            ),
          WindowCloseButton(
            key: WK.windowClose,
            dirty: widget.confirmClose && dirty,
            hasChanges: widget.confirmClose ? widget.hasChanges : null,
            onClose: widget.onClose,
          ),
        ],
      ),
    );
  }
}
