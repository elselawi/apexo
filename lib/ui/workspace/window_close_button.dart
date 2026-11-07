import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The confirm for dismissals with no button to attach a flyout to, such as a
/// tap beside a phone's sheet.
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

  /// Re-checks on press: [dirty] can lag behind typing, and closing on a stale
  /// "clean" would lose work.
  final bool Function()? hasChanges;

  final VoidCallback onClose;

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
