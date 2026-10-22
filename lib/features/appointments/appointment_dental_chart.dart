import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
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
    onOpenAppointment: onOpenAppointment,
    onSave: onSave,
  );
}

/// The same, for one visit: the chart of [appointment], saved onto it, shown on
/// its own when the visit's panel is not open.
Future<void> openAppointmentDentalChart(
  Appointment appointment, {
  ValueChanged<String>? onOpenAppointment,
  Future<void> Function()? onOpenRecord,
}) async {
  final draft = Appointment.fromJson(appointment.toJson());
  final session = appointmentDentalChart(
    draft,
    onOpenAppointment: onOpenAppointment,
    onSave: () async {
      final stored = appointments.get(draft.id);
      if (stored == null) {
        throw StateError('Appointment ${draft.id} is no longer stored');
      }
      appointments.set(stored.copy(false)
        ..teeth = Map<String, String>.from(draft.teeth)
        ..teethExtraNotes = Map<String, String>.from(draft.teethExtraNotes));
    },
  );
  showDentalChartWindow(session, onOpenRecord: onOpenRecord);
}
