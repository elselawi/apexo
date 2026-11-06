import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

/// The sheet a patient is created from.
///
/// Creation starts here rather than in an empty panel: the name — and the
/// phone reception books them by — are asked for before there is a record, so
/// [onSave] receives a patient that can be stored as it is. Nothing is opened
/// as a draft.
class NewPatientDialog extends StatefulWidget {
  const NewPatientDialog({
    super.key,
    required this.onSave,
    this.initialName,
    this.initialPhone,
  });

  final void Function(Patient patient) onSave;

  /// Contact details a booking request already carries. Prefill only: staff
  /// still confirm the record, and an unverified name/phone never auto-merges.
  final String? initialName;
  final String? initialPhone;

  @override
  State<NewPatientDialog> createState() => _NewPatientDialogState();
}

class _NewPatientDialogState extends State<NewPatientDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = widget.initialName ?? "";
    _phone.text = widget.initialPhone ?? "";
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// The phone is optional, but text that holds no number at all is worth
  /// flagging before the record is stored with a phone it cannot use.
  bool get _phoneHasNoNumber =>
      _phone.text.trim().isNotEmpty &&
      PhoneNumberExtractor.extract(_phone.text).isEmpty;

  void _save() {
    widget.onSave(Patient.fromJson({
      "title": _name.text.trim(),
      if (_phone.text.trim().isNotEmpty) "phone": _phone.text.trim(),
    }));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAwareView(
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        style: dialogStyling(context, false, true),
        title: Row(children: [
          const Icon(FluentIcons.add_friend),
          const SizedBox(width: 5),
          Txt(txt("newPatient")),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            InfoLabel(
              label: "${txt("name")}:",
              child: CupertinoTextField(
                key: WK.fieldNewPatientName,
                controller: _name,
                autofocus: true,
                placeholder: "${txt("name")}...",
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_name.text.trim().isNotEmpty) _save();
                },
              ),
            ),
            InfoLabel(
              label: "${txt("phone")}:",
              child: CupertinoTextField(
                key: WK.fieldNewPatientPhone,
                controller: _phone,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.phone,
                placeholder: "${txt("phone")}...",
                suffix: _phoneHasNoNumber
                    ? const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          WindowsIcons.warning,
                          color: Colors.warningPrimaryColor,
                        ),
                      )
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_phoneHasNoNumber) Txt(txt("noValidNumbersFound")),
          ],
        ),
        actions: [
          FilledButton(
            key: WK.btnCreatePatient,
            onPressed: _name.text.trim().isEmpty ? null : _save,
            child: ButtonContent(FluentIcons.add, txt("save")),
          ),
          const CloseButtonInDialog(),
        ],
      ),
    );
  }
}

/// Asks for a new patient's name and phone, and stores what the sheet says.
///
/// Returns the stored patient, or null when the sheet was dismissed. Callers
/// open the record — or use it — afterwards: the patient already exists, so
/// nothing they do can leave a draft behind.
Future<Patient?> addPatient(
  BuildContext context, {
  String? initialName,
  String? initialPhone,
}) async {
  Patient? collected;
  await showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (_) => NewPatientDialog(
      initialName: initialName,
      initialPhone: initialPhone,
      onSave: (patient) => collected = patient,
    ),
  );
  final created = collected;
  if (created == null) return null;
  patients.set(created);
  return created;
}
