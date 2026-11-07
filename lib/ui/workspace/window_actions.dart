import 'dart:async';

import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A window's Save and Close row. Docked windows set [confirmClose] false:
/// closing one only returns it to its dock, losing nothing.
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
    this.saveLabel = 'save',
    this.extraActions = const <Widget>[],
  });

  final bool savable;

  /// Whether the draft was dirty at the last sample; [hasChanges] asks live.
  final bool dirty;

  /// The same question, asked live: a sample can be a beat behind the typing.
  final bool Function()? hasChanges;

  final Future<void> Function() onSave;
  final VoidCallback onClose;

  final bool confirmClose;

  /// Told after a save lands, so the window can re-read whether it is clean.
  final VoidCallback? onSaved;

  /// Localization key for the Save label, naming which record the row writes.
  final String saveLabel;

  final List<Widget> extraActions;

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
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          ...widget.extraActions,
          if (widget.savable)
            IconButton(
              key: WK.windowSave,
              // Enabled even when the sample says clean: a save with nothing
              // to write costs nothing, and a dead press looks broken.
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
                txt(widget.saveLabel),
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
