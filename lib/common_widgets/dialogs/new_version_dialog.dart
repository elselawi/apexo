import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/qrlink.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class NewVersionDialog extends StatelessWidget {
  const NewVersionDialog({super.key, required this.downloadLink});

  final String downloadLink;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(txt("newVersionDialogTitle")),
          IconButton(
              icon: const Icon(WindowsIcons.cancel),
              onPressed: () => Navigator.pop(context))
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Txt(txt("newVersionDialogContent")),
          const SizedBox(height: 10),
          QRLink(link: downloadLink),
        ],
      ),
      style: dialogStyling(context, false),
      actions: [
        FilledButton(
          child: ButtonContent(WindowsIcons.download, txt("download")),
          onPressed: () {
            launchUrl(Uri.parse(downloadLink));
          },
        ),
        const CloseButtonInDialog(buttonText: "close"),
      ],
    );
  }
}
