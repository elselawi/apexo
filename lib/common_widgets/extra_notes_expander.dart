import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:fluent_ui/fluent_ui.dart';

class AppointmentExtraNotes extends StatelessWidget {
  const AppointmentExtraNotes({
    super.key,
    required this.patient,
    required this.initiallyExpanded,
    required this.title,
    this.bottomMargin = false,
    this.excludedAppointment,
  });

  final Patient patient;
  final bool initiallyExpanded;
  final bool bottomMargin;
  final Appointment? excludedAppointment;
  final String title;

  Patient get _patient => patient;

  @override
  Widget build(BuildContext context) {
    final allAppts = _patient.allAppointments;
    // Collect all extra notes from appointments grouped by tooth ISO
    final Map<String, List<(Appointment appt, String note)>> grouped = {};
    for (final appt in allAppts) {
      if (excludedAppointment != null && appt.id == excludedAppointment!.id) {
        continue; // Skip the excluded appointment
      }
      for (final entry in appt.teethExtraNotes.entries) {
        if (entry.value.isNotEmpty) {
          grouped.putIfAbsent(entry.key, () => []);
          grouped[entry.key]!.add((appt, entry.value));
        }
      }

      for (final entry in appt.teeth.entries) {
        if (entry.value.isNotEmpty &&
            !_patient.teethExtraNotes.containsKey(entry.key)) {
          // Only include dental notes that don't have a corresponding extra note
          grouped.putIfAbsent(entry.key, () => []);
          if (grouped[entry.key]!.where((e) => e.$1.id == appt.id).isEmpty) {
            grouped[entry.key]!.add((appt, entry.value));
          }
        }
      }
    }

    if (grouped.isEmpty) return const SizedBox.shrink();

    final sortedIsos = grouped.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    return Column(
      children: [
        Expander(
            initiallyExpanded: initiallyExpanded,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            leading: const Icon(WindowsIcons.history),
            header: Txt(
              title,
              style: FluentTheme.of(context)
                  .typography
                  .bodyStrong
                  ?.copyWith(fontSize: 13),
              softWrap: false,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...sortedIsos.map((iso) {
                  final entries = grouped[iso]!;
                  String treatmentLabel = _patient.teeth[iso] ?? '';
                  if (treatmentLabel.isEmpty && entries.isNotEmpty) {
                    treatmentLabel = entries.first.$1.teeth[iso] ?? '';
                  }
                  final color = labelToColor(treatmentLabel);

                  return Container(
                    decoration: BoxDecoration(
                      color: FluentTheme.of(context).cardColor,
                      border: BorderDirectional(
                        start:
                            BorderSide(color: color.withAlpha(200), width: 4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          offset: const Offset(0.0, 6.0),
                          blurRadius: 30.0,
                          spreadRadius: 5.0,
                          color: Colors.grey.withAlpha(50),
                        )
                      ],
                      borderRadius: BorderRadius.circular(5),
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          spacing: 10,
                          children: [
                            DentalNotation(
                                iso: iso, color: color, withTooltip: false),
                            Txt(
                              isoToTextualNotation(iso),
                              style: FluentTheme.of(context)
                                  .typography
                                  .bodyStrong!
                                  .copyWith(color: color, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Divider(),
                        const SizedBox(height: 4),
                        ...entries.map((entry) {
                          final appt = entry.$1;
                          final note = entry.$2;
                          final color = labelToColor(appt.teeth[iso] ?? '');
                          final icon = labelToIcon(appt.teeth[iso] ?? '');
                          return Padding(
                            padding: EdgeInsets.only(
                                bottom: entries.last == entry ? 0 : 8),
                            child: Column(
                              spacing: 3,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    Icon(icon, size: 25, color: color),
                                    FilledButton(
                                        style: filledButtonStyle(color),
                                        child: ButtonContent(
                                          WindowsIcons.calendar,
                                          DF.allNumbers(appt.date),
                                        ),
                                        onPressed: () {
                                          openAppointment(appt, 1);
                                        }),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 5,
                                  children: [
                                    const SizedBox(width: 30),
                                    const Icon(WindowsIcons.quick_note,
                                        size: 18),
                                    Txt(
                                      txt(note),
                                      style: FluentTheme.of(context)
                                          .typography
                                          .bodyStrong,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                if (entries.last != entry) ...[
                                  const Divider(),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }),
              ],
            )),
        if (bottomMargin) const SizedBox(height: 50),
      ],
    );
  }
}
