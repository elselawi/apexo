import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

bool isOpen = false;

VoidCallback showLoadingBlockingDialog(BuildContext context, String text) {
  isOpen = true;
  showDialog(
      barrierDismissible: false,
      dismissWithEsc: false,
      context: context,
      builder: (BuildContext context) {
        return ContentDialog(
          title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Txt(text)]),
          content: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [ProgressRing()]),
          style: dialogStyling(context, false, true),
        );
      });

  return () {
    if (context.mounted && isOpen) {
      isOpen = false;
      Navigator.of(context).pop();
    }
  };
}
