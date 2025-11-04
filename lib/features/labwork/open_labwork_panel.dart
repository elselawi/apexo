import 'package:apexo/app/routes.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/call_button.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/operators_picker.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/features/labwork/labwork_model.dart';
import 'package:apexo/features/labwork/labworks_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

void openLabwork([Labwork? labwork]) {
  final editingCopy = Labwork.fromJson(labwork?.toJson() ?? {});

  routes.openPanel(Panel(
    item: editingCopy,
    store: labworks,
    icon: FluentIcons.manufacturing,
    title: labworks.get(editingCopy.id) == null ? txt("newLabwork") : editingCopy.title,
    tabs: [
      PanelTab(
        title: txt("labwork"),
        icon: FluentIcons.manufacturing,
        body: _LabworkEditing(editingCopy),
      ),
    ],
  ));
}

class _LabworkEditing extends StatefulWidget {
  final Labwork labwork;

  const _LabworkEditing(this.labwork);

  @override
  State<_LabworkEditing> createState() => _LabworkEditingState();
}

class _LabworkEditingState extends State<_LabworkEditing> {
  final TextEditingController labNameController = TextEditingController();
  final TextEditingController labPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    labNameController.text = widget.labwork.lab;
    labPhoneController.text = widget.labwork.phoneNumber;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: "${txt("date")}:",
          child: DateTimePicker(
            key: WK.fieldLabworkDate,
            initValue: widget.labwork.date,
            onChange: (d) => widget.labwork.date = d,
            buttonText: txt("changeDate"),
          ),
        ),
        InfoLabel(
          label: "${txt("patient")}:",
          child: PatientPicker(
              value: widget.labwork.patientID,
              onChanged: (id) {
                widget.labwork.patientID = id;
              }),
        ),
        InfoLabel(
          label: "${txt("doctors")}:",
          child: OperatorsPicker(
              value: widget.labwork.operatorsIDs,
              onChanged: (ids) {
                widget.labwork.operatorsIDs = ids;
              }),
        ),
        InfoLabel(
          label: "${txt("orderNotes")}:",
          child: CupertinoTextField(
            key: WK.fieldLabworkOrderNotes,
            controller: TextEditingController(text: widget.labwork.note),
            placeholder: "${txt("orderNotes")}...",
            onChanged: (val) {
              widget.labwork.note = val;
            },
            maxLines: null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InfoLabel(
                label: "${txt("priceIn")} ${globalSettings.get("currency_______").value}",
                child: NumberBox(
                  key: WK.fieldLabworkPrice,
                  style: textFieldTextStyle(),
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  value: widget.labwork.price,
                  onChanged: (n) => widget.labwork.price = n ?? 0.0,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Padding(
              padding: const EdgeInsets.only(top: 22.5),
              child: Checkbox(
                key: WK.fieldLabworkPaidToggle,
                checked: widget.labwork.paid,
                onChanged: (n) {
                  setState(() {
                    widget.labwork.paid = n == true;
                  });
                },
                content: widget.labwork.paid ? Txt(txt("paid")) : Txt(txt("unpaid")),
              ),
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InfoLabel(
                label: "${txt("laboratory")}:",
                child: AutoSuggestBox<String>(
                  key: WK.fieldLabworkLabName,
                  style: textFieldTextStyle(),
                  decoration: WidgetStatePropertyAll(textFieldDecoration()),
                  clearButtonEnabled: false,
                  placeholder: "${txt("laboratory")}...",
                  controller: labNameController,
                  noResultsFoundBuilder: (context) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Txt(txt("noSuggestions")),
                  ),
                  onChanged: (text, reason) {
                    widget.labwork.lab = text;
                    String? phoneNumber = labworks.getPhoneNumber(text);
                    if (phoneNumber != null) {
                      labPhoneController.text = phoneNumber;
                      widget.labwork.phoneNumber = phoneNumber;
                    }
                  },
                  items: labworks.allLabs.map((name) => AutoSuggestBoxItem<String>(value: name, label: name)).toList(),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: InfoLabel(
                label: "${txt("phone")}:",
                child: AutoSuggestBox<String>(
                  key: WK.fieldLabworkPhoneNumber,
                  style: textFieldTextStyle(),
                  decoration: WidgetStatePropertyAll(textFieldDecoration()),
                  clearButtonEnabled: false,
                  placeholder: "${txt("phone")}...",
                  controller: labPhoneController,
                  noResultsFoundBuilder: (context) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Txt(txt("noSuggestions")),
                  ),
                  onChanged: (text, reason) {
                    widget.labwork.phoneNumber = text;
                  },
                  trailingIcon: CallIconButton(phoneNumber: widget.labwork.phoneNumber),
                  items: labworks.allPhones.map((pn) => AutoSuggestBoxItem<String>(value: pn, label: pn)).toList(),
                ),
              ),
            ),
          ],
        )
      ].map((e) => [e, const SizedBox(height: 10)]).expand((e) => e).toList(),
    );
  }
}

BoxDecoration textFieldDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(5),
    border: Border.all(color: const Color.fromARGB(255, 192, 192, 192)),
  );
}

TextStyle textFieldTextStyle() {
  return const TextStyle(
    fontSize: 16,
  );
}
