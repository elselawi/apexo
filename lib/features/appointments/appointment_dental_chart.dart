import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/appointments/appointment_chart_footer.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:flutter/widgets.dart';

/// The chart an appointment edits: this visit's treatments, with the patient's
/// baseline and the other visits as history. It is the visit's **Treatments** —
/// the same window as the record's chart, named for the scope it writes.
///
/// The appointments feature's half of the dental chart: the shared editor knows
/// teeth, not visits.
DentalChartSession appointmentDentalChart(
  Appointment appointment, {
  ValueChanged<String>? onOpenAppointment,
  Future<void> Function()? onSave,
}) {
  final patient = appointment.patient;
  return DentalChartSession(
    id: 'appointment:${appointment.id}',
    titleKey: kTreatmentsTitleKey,
    subtitle: () => appointmentOwnerLine(appointment),
    type: StateType.treatment,
    teeth: appointment.teeth,
    extraNotes: appointment.teethExtraNotes,
    historyTitle: 'toothHistory',
    history: () => [
      if (patient != null) ...[
        ToothHistory(
          label: txt('toothPatientHistory'),
          teeth: Map.of(patient.teeth),
          notes: Map.of(patient.teethExtraNotes),
        ),
        for (final previous in patient.allAppointments)
          if (previous.id != appointment.id)
            ToothHistory(
              label: DF.allNumbers(previous.date),
              date: previous.date,
              appointmentId: previous.id,
              teeth: Map.of(previous.teeth),
              notes: Map.of(previous.teethExtraNotes),
            ),
      ],
    ],
    oldNotes: () => patient?.allAppointmentsDentalNotes ?? const {},
    showPrimary: (patient?.age ?? 18) < 14,
    onOpenAppointment: onOpenAppointment ?? openAppointmentChartFromHistory,
    header: patient == null
        ? null
        : (session) => VisitScopeBar(
              patient: patient,
              session: session,
              currentAppointment: appointment,
            ),
    // The default is the standalone shape; the windows built for a visit beside
    // its patient override it with the visit's own footer, so the post-op record
    // sits under the teeth (see `appointmentSessionWindows`).
    footer: (session) => AppointmentChartFooter(
      key: ValueKey('chart-footer-${appointment.id}'),
      appointment: appointment,
      session: session,
    ),
    onSave: onSave,
  );
}

/// Opens the visit's chart — beside its patient, where the visit lives.
///
/// A visit's chart is one of its windows, so opening it is opening the visit
/// focused on the chart: same patient panel, same draft, same Save (plan §4.3).
/// With no patient the account may see, the chart stands on its own with the rest
/// of the visit's windows.
Future<void> openAppointmentDentalChart(
  Appointment appointment, {
  BuildContext? context,
}) =>
    openAppointment(appointment, AppointmentWindow.dentalChart);
