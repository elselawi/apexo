import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

class ExportPatientsDialog extends StatefulWidget {
  final List<String> ids;
  const ExportPatientsDialog({
    super.key,
    required this.ids,
  });

  @override
  State<ExportPatientsDialog> createState() => _ExportPatientsDialogState();
}

class _ExportPatientsDialogState extends State<ExportPatientsDialog> {
  late List<Patient?> selected;
  bool name = true;
  bool phoneNumber = true;
  bool age = false;
  bool gender = false;
  bool totalPayments = false;
  String get exportData {
    return selected
        .map(
          (patient) => [
            name ? patient!.title : null,
            phoneNumber ? patient!.phone : null,
            age ? patient!.age : null,
            gender ? patient!.gender : null,
            totalPayments ? patient!.paymentsMade.toStringAsFixed(2) : null,
          ].where((x) => x != null).join(","),
        )
        .join("\n");
  }

  @override
  void initState() {
    selected = widget.ids
        .map((id) => patients.get(id))
        .where((e) => e != null)
        .toList();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(txt("exportSelected")),
          IconButton(
              icon: const Icon(FluentIcons.cancel),
              onPressed: () => Navigator.pop(context))
        ],
      ),
      content: selected.isEmpty
          ? InfoBar(
              isIconVisible: true,
              severity: InfoBarSeverity.warning,
              title: Txt(txt("noPatientsSelected")),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Checkbox(
                      checked: name,
                      onChanged: (checked) => setState(() => name = checked!),
                      content: Txt(txt("name")),
                    ),
                    Checkbox(
                      checked: phoneNumber,
                      onChanged: (checked) =>
                          setState(() => phoneNumber = checked!),
                      content: Txt(txt("phone")),
                    ),
                    Checkbox(
                      checked: age,
                      onChanged: (checked) => setState(() => age = checked!),
                      content: Txt(txt("age")),
                    ),
                    Checkbox(
                      checked: gender,
                      onChanged: (checked) => setState(() => gender = checked!),
                      content: Txt(txt("gender")),
                    ),
                    Checkbox(
                      checked: totalPayments,
                      onChanged: (checked) =>
                          setState(() => totalPayments = checked!),
                      content: Txt(txt("total payments")),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  height: 200,
                  child: CupertinoTextField(
                    maxLines: null,
                    controller: TextEditingController(
                        text: exportData.replaceAll("\n", "\n\n")),
                    placeholder: "no data",
                  ),
                )
              ],
            ),
      style: dialogStyling(context, false),
      actions: const [CloseButtonInDialog(buttonText: "close")],
    );
  }
}
