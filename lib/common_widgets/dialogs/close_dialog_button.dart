import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class CloseButtonInDialog extends StatelessWidget {
  final String buttonText;
  const CloseButtonInDialog({
    this.buttonText = "cancel",
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: greyButtonStyle,
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
