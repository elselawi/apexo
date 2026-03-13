import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ConfirmDeleteFlyout extends StatelessWidget {
  const ConfirmDeleteFlyout({
    super.key,
    required this.onConfirm,
    required this.controller,
    this.actionText = "delete",
    this.actionIcon = FluentIcons.delete,
  });

  final VoidCallback onConfirm;
  final FlyoutController controller;
  final String actionText;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Txt("${txt(actionText)}?", style: FluentTheme.of(context).typography.bodyStrong?.copyWith(color: Colors.grey)),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () {
              controller.close();
              onConfirm();
            },
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.errorPrimaryColor),
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
                const Icon(FluentIcons.cancel),
                const SizedBox(width: 5),
                Txt(txt("cancel")),
              ],
            ),
          )
        ],
      ),
    );
  }
}
