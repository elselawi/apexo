import 'dart:async';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PatientPicker extends StatelessWidget {
  const PatientPicker(
      {super.key,
      required this.onChanged,
      required this.value,
      this.enabled = true,
      this.fieldKey = WK.fieldPatient,
      this.tapOpensRecord = true});
  final void Function(String? id) onChanged;
  final String? value;
  final bool enabled;

  /// The key the picker's field carries. A picker that shares the screen with
  /// another one — a sheet opened over a panel — needs its own.
  final Key fieldKey;

  /// Whether tapping the selected patient opens their record. A sheet that is
  /// still being filled in turns this off: its answer is the patient, not the
  /// record behind the sheet.
  final bool tapOpensRecord;

  @override
  Widget build(BuildContext context) {
    return TagInputWidget(
      key: fieldKey,
      onItemTap: tapOpensRecord
          ? (tag) {
              final Patient? tapped = patients.get(tag.value ?? "");
              // A tag whose patient is gone is not a reason to start one.
              if (tapped != null) unawaited(openPatient(tapped));
            }
          : null,
      suggestions: patients.present.values
          .map((e) => TagInputItem(value: e.id, label: e.title))
          .toList(),
      onChanged: (s) {
        if (s.isEmpty) return onChanged(null);
        onChanged(s.first.value ?? "");
      },
      enabled: enabled,
      initialValue: value != null
          ? [
              TagInputItem(
                  value: value!, label: patients.get(value!)?.title ?? "null")
            ]
          : [],
      strict: true,
      limit: 1,
      placeholder: txt("selectPatient"),
    );
  }
}
