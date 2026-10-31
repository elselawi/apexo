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

  /// How the list opens the visit it starts here. A list that is a window of its
  /// own passes its own opener, so a new visit makes way for the panel that holds
  /// it instead of leaving the list behind. Defaults to opening the visit.
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
            // The sheet fills in the visit; what it hands back is already
            // stored, so the visit opens as a record rather than a draft.
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
