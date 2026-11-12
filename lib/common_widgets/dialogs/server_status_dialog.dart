import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A message the clinic's server publishes about itself.
///
/// A non-dismissable message offers no action, and its caller turns off the
/// barrier and the escape key so nothing can close it.
class ServerStatusDialog extends StatelessWidget {
  const ServerStatusDialog({
    super.key,
    required this.message,
    required this.dismissable,
  });

  final String message;
  final bool dismissable;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      style: dialogStyling(context, false, !dismissable),
      content: SingleChildScrollView(child: Txt(message)),
      actions:
          dismissable ? [const CloseButtonInDialog(buttonText: "close")] : null,
    );
  }
}
