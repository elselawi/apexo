import 'package:apexo/app/app.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

bool errorShown = false;

void showErrorMessage(Object message, String when) {
  if (errorShown) return;
  errorShown = true;
  showDialog(
      barrierDismissible: true,
      dismissWithEsc: true,
      context: bContext,
      builder: (ctx) {
        return ContentDialog(
          title: Txt(txt("error")),
          constraints: const BoxConstraints(maxHeight: 350, maxWidth: 400),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 5,
            children: [
              Txt(
                "${txt("errorHappenedWhen")}: ${txt(when)}",
                style: FluentTheme.of(bContext).typography.bodyStrong,
              ),
              StyledSelectableText(text: message.toString()),
            ],
          ),
          style: dialogStyling(ctx, true, true),
          actions: [
            Button(
              style: filledButtonStyle(Colors.grey),
              child: ButtonContent(WindowsIcons.cancel, txt("close")),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      }).then((_) => errorShown = false);
}
