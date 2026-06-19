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
              flyoutController.showFlyout(builder: (ctx) {
                return ConfirmDeleteFlyout(
                  restorable: widget.restorable,
                  controller: flyoutController,
                  actionIcon: widget.actionIcon,
                  actionText: widget.actionText,
                  preview: widget.preview,
                  onConfirm: widget.onConfirm,
                );
              });
            }));
  }
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
                  controller.close();
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
                    controller.close();
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
