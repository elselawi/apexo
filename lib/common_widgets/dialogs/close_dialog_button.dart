import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class CloseButtonInDialog extends StatelessWidget {
  const CloseButtonInDialog({
    this.buttonText = "cancel",
    super.key,
  });
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    return Button(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(WindowsIcons.cancel),
          const SizedBox(width: 10),
          Txt(txt(buttonText))
        ],
      ),
      onPressed: () => Navigator.pop(context),
    );
  }
}
