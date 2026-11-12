import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart'
    show StyledSelectableText;
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The day's follow-ups as the clinic reads them while calling: who to call,
/// the numbers to try, and what the promise was about — one block per patient.
String followUpContactsText(List<FollowUpDue> followUps) {
  return followUps.map((followUp) {
    final patient = followUp.patient;
    final lines = <String>[patient.title];
    if (patient.phone.isNotEmpty) {
      final numbers =
          patient.phone.map((phone) => phone.toInternationalFormat());
      lines.add(numbers.join(', '));
    }
    final note = patient.followUpNote.trim();
    if (note.isNotEmpty) lines.add(note);
    return lines.join('\n');
  }).join('\n\n');
}

/// Opens the day's contacts, with their text ready to select or copy.
Future<void> showFollowUpContacts(
  BuildContext context,
  List<FollowUpDue> followUps,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (_) => FollowUpContactsDialog(followUps: followUps),
  );
}

class FollowUpContactsDialog extends StatelessWidget {
  const FollowUpContactsDialog({super.key, required this.followUps});

  final List<FollowUpDue> followUps;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      style: dialogStyling(context, false, true),
      constraints: const BoxConstraints(maxWidth: 460),
      title: Row(
        children: [
          const Icon(WindowsIcons.walk_solid, color: kFollowUpAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Txt('${txt('followUpContacts')} (${followUps.length})'),
          ),
          IconButton(
            icon: const Icon(WindowsIcons.cancel),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: StyledSelectableText(
          key: WK.followUpContactsText,
          text: followUpContactsText(followUps),
          height: 280,
          canSave: false,
          textDirection: Directionality.of(context),
        ),
      ),
      actions: const [CloseButtonInDialog(buttonText: "close")],
    );
  }
}
