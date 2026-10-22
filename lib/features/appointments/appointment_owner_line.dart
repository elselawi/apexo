import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';

/// Whose visit a window belongs to: the patient, the day the visit is for, and
/// where the visit stands. Several windows can be open at once and their labels
/// repeat, so the line has to say which record each one is about — and a visit's
/// state is what tells two visits of the same patient apart.
///
/// It lives here rather than in the panel opener, which is where it started:
/// everything that shows a visit's window needs the line, and a chart that only
/// wants to label its record must not import the whole appointment panel (and
/// the 41 modules behind it) to get it.
String appointmentOwnerLine(Appointment appointment) {
  final patient = appointment.patient?.title ?? '';
  return [
    if (patient.isNotEmpty) patient,
    DF.allNumbers(appointment.date),
    txt(appointment.isDone ? 'done' : 'pending'),
  ].join(' · ');
}
