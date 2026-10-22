import 'dart:async';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DeleteButton extends StatefulWidget {
  const DeleteButton({
    super.key,
    required this.child,
    required this.onConfirm,
    required this.preview,
    required this.actionText,
    required this.actionIcon,
    required this.restorable,
    this.style,
  });

  final Widget child;
  final VoidCallback onConfirm;
  final Widget preview;
  final String actionText;
  final IconData actionIcon;
  final bool restorable;
  final ButtonStyle? style;

  @override
  State<DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<DeleteButton> {
  final FlyoutController flyoutController = FlyoutController();

  @override
  void dispose() {
    flyoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
        controller: flyoutController,
        child: IconButton(
            style: widget.style,
            icon: widget.child,
            onPressed: () async {
              await flyoutFocusFix(context);
              unawaited(flyoutController.showFlyout<void>(builder: (ctx) {
                return ConfirmDeleteFlyout(
                  restorable: widget.restorable,
                  controller: flyoutController,
                  actionIcon: widget.actionIcon,
                  actionText: widget.actionText,
                  preview: widget.preview,
                  onConfirm: widget.onConfirm,
                );
              }));
            }));
  }
}

/// The last item of a row's context menu: it closes the menu, asks for
/// confirmation where the menu was, and runs [onConfirm] when confirmed.
///
/// [controller] is the context menu's own controller. Reusing it anchors the
/// confirmation to the row the menu belonged to instead of opening a flyout
/// somewhere else on the screen.
MenuFlyoutItem confirmDeleteMenuItem({
  required FlyoutController controller,
  required Widget preview,
  required VoidCallback onConfirm,
  String actionText = "delete",
  IconData actionIcon = WindowsIcons.delete,
  bool restorable = true,
}) {
  return MenuFlyoutItem(
    text: Txt(txt(actionText)),
    leading: Icon(actionIcon),
    onPressed: () {
      controller.close<void>();
      // The menu is still closing; show the confirmation once it has left the
      // controller free to open another flyout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller.showFlyout<void>(
          builder: (ctx) => ConfirmDeleteFlyout(
            restorable: restorable,
            controller: controller,
            actionIcon: actionIcon,
            actionText: txt(actionText),
            preview: preview,
            onConfirm: onConfirm,
          ),
        ));
      });
    },
  );
}

class ConfirmDeleteFlyout extends StatelessWidget {
  const ConfirmDeleteFlyout({
    super.key,
    required this.onConfirm,
    required this.controller,
    required this.restorable,
    this.actionText = "delete",
    this.actionIcon = WindowsIcons.delete,
    this.preview,
  });

  final bool restorable;
  final VoidCallback onConfirm;
  final FlyoutController controller;
  final String actionText;
  final IconData actionIcon;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    return FlyoutContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 5,
        children: [
          Txt("${txt("areYouSureYouWantTo")} ${txt(actionText)}?",
              style: FluentTheme.of(context)
                  .typography
                  .bodyStrong
                  ?.copyWith(color: FluentTheme.of(context).inactiveColor)),
          if (preview != null) ...[preview!],
          if (actionIcon != WindowsIcons.undo && actionIcon != FluentIcons.undo)
            Txt(
              "(${restorable ? txt("youCanRestoreFromDeletedItemsPage") : txt("youWillNotBeAbleToRestore")})",
              style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: restorable == false ? Colors.red : null,
                    fontWeight: restorable == false ? FontWeight.bold : null,
                  ),
            ),
          _buildDivider(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () {
                  controller.close<void>();
                  onConfirm();
                },
                style: const ButtonStyle(
                  backgroundColor:
                      WidgetStatePropertyAll(Colors.errorPrimaryColor),
                  foregroundColor: WidgetStatePropertyAll(Colors.white),
                ),
                child: Row(
                  children: [
                    Icon(actionIcon),
                    const SizedBox(width: 5),
                    Txt(txt(actionText)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close<void>();
                  }
                },
                style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.grey),
                  foregroundColor: WidgetStatePropertyAll(Colors.white),
                ),
                child: Row(
                  children: [
                    const Icon(WindowsIcons.cancel),
                    const SizedBox(width: 5),
                    Txt(txt("cancel")),
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Padding _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Divider(size: 250),
    );
  }
}
