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

/// The visit's treatments chart: it writes this visit's treatments, with the
/// patient's baseline and other visits as read-only history.
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
    // The standalone chart's footer; the visit's window overrides it with one
    // attached to the patient's panel, so the post-op record sits under the teeth.
    footer: (session) => AppointmentChartFooter(
      key: ValueKey('chart-footer-${appointment.id}'),
      appointment: appointment,
      session: session,
    ),
    onSave: onSave,
  );
}

/// Opens the visit focused on its chart, so it shares the visit's panel and draft;
/// a visit whose patient this account may not see opens standalone.
Future<void> openAppointmentDentalChart(
  Appointment appointment, {
  BuildContext? context,
}) =>
    openAppointment(appointment, AppointmentWindow.dentalChart);
