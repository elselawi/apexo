import 'dart:async';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class AppointmentsListFooter extends StatelessWidget {
  const AppointmentsListFooter({
    super.key,
    this.forPatientID,
    this.onOpen,
  });
  final String? forPatientID;

  /// A list drawn as its own window passes an opener here so that window closes
  /// itself before the new visit opens.
  final void Function(Appointment appointment)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FilledButton(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.add_event),
              const SizedBox(width: 10),
              Txt(txt("addAppointment"))
            ],
          ),
          onPressed: () async {
            // the sheet stores the visit before returning, so open it as a
            // record, not a draft.
            final created = await addAppointment(
              context,
              patientID: forPatientID,
            );
            if (created == null) return;
            final open = onOpen;
            if (open != null) {
              open(created);
              return;
            }
            unawaited(openAppointment(created));
          }),
    );
  }
}
