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

class NewPatientDialog extends StatefulWidget {
  const NewPatientDialog({
    super.key,
    required this.onSave,
    this.initialName,
    this.initialPhone,
  });

  final void Function(Patient patient) onSave;

  /// Prefill from a booking request; staff still confirm, and it never
  /// auto-merges.
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

/// Stores and returns the patient, or null when dismissed. No draft is opened.
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
