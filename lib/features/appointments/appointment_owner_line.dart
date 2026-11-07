import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';

/// Labels a visit window by patient, date and state, so simultaneously open
/// windows stay distinguishable; kept out of the panel to avoid its import.
String appointmentOwnerLine(Appointment appointment) {
  final patient = appointment.patient?.title ?? '';
  return [
    if (patient.isNotEmpty) patient,
    DF.allNumbers(appointment.date),
    txt(appointment.isDone ? 'done' : 'pending'),
  ].join(' · ');
}
