import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
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
          onPressed: () {
            final draft = Appointment.fromJson({
              if (forPatientID != null) "patientID": forPatientID,
              if (login.perm(Perm.patients).exact(1) ||
                  login.perm(Perm.appointments).exact(1) ||
                  login.currentLoginIsOperator)
                "operatorsIDs": [login.currentAccountID]
            });
            final open = onOpen;
            if (open != null) {
              open(draft);
              return;
            }
            openAppointment(draft);
          }),
    );
  }
}
