import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The question a window asks before it goes away with unsaved work in it — for
/// the dismissals that have no button to hang a flyout on, such as a tap beside
/// a phone's sheet.
Future<bool> confirmDiscardFloatingWindow(BuildContext context) async {
  final discard = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (ctx) => ContentDialog(
      content: Txt(txt('sureClosePanel')),
      actions: [
        Button(
          child: Txt(txt('back')),
          onPressed: () => Navigator.pop(ctx, false),
        ),
        FilledButton(
          style: filledButtonStyle(Colors.warningPrimaryColor),
          onPressed: () => Navigator.pop(ctx, true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.check_mark, size: 16),
              const SizedBox(width: 5),
              Txt(txt('sure')),
            ],
          ),
        ),
      ],
    ),
  );
  return discard == true;
}

/// The Close a window that stands on its own has, wherever it is drawn: the one
/// in its header and the one in its footer are the same button, so both ask the
/// same question — this has unsaved work, leave it? — and cannot drift apart.
class WindowCloseButton extends StatefulWidget {
  const WindowCloseButton({
    super.key,
    required this.dirty,
    required this.onClose,
    this.hasChanges,
    this.compact = false,
  });

  /// Whether there is work that closing would throw away, as last sampled.
  final bool dirty;

  /// The same question, asked again when the button is pressed: the sample can
  /// be a beat behind the typing, and closing on a stale "clean" would lose it.
  final bool Function()? hasChanges;

  final VoidCallback onClose;

  /// The header's version: an icon with a tooltip, where a panel's window has
  /// its minimize. The footer's version spells the word out.
  final bool compact;

  @override
  State<WindowCloseButton> createState() => _WindowCloseButtonState();
}

class _WindowCloseButtonState extends State<WindowCloseButton> {
  final FlyoutController _confirmClose = FlyoutController();

  @override
  void dispose() {
    _confirmClose.dispose();
    super.dispose();
  }

  void _close() {
    final dirty = widget.hasChanges?.call() ?? widget.dirty;
    if (!dirty) {
      widget.onClose();
      return;
    }
    unawaited(_confirmDiscard());
  }

  Future<void> _confirmDiscard() async {
    await flyoutFocusFix(context);
    if (!mounted) return;
    unawaited(_confirmClose.showFlyout<void>(builder: (flyoutContext) {
      return FlyoutContent(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Column(
          spacing: 12,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Txt(txt('sureClosePanel')),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  style: filledButtonStyle(Colors.warningPrimaryColor),
                  onPressed: () {
                    Flyout.of(flyoutContext).close();
                    widget.onClose();
                  },
                  child: Row(
                    children: [
                      const Icon(FluentIcons.check_mark, size: 16),
                      const SizedBox(width: 5),
                      Txt(txt('sure')),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                CloseButtonInDialog(buttonText: txt('back')),
              ],
            ),
          ],
        ),
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.dirty ? txt('cancel') : txt('close');
    final button = IconButton(
      onPressed: _close,
      style: greyButtonStyle.copyWith(
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        backgroundColor: WidgetStatePropertyAll(
          widget.dirty ? Colors.orange : Colors.grey,
        ),
      ),
      icon: widget.compact
          ? const Icon(WindowsIcons.chrome_close, size: 14)
          : ButtonContent(WindowsIcons.cancel, label),
    );
    return FlyoutTarget(
      controller: _confirmClose,
      child: widget.compact ? Tooltip(message: label, child: button) : button,
    );
  }
}
