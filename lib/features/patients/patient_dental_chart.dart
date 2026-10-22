import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_owner_line.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF, globalSettings;
import 'package:apexo/services/ai_services/dental_history.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The chart a patient record edits: the patient's own baseline, with every
/// appointment of theirs as history. It is the record's **Dental Chart**.
///
/// This is the patients feature's half of the dental chart: the shared editor
/// knows teeth, not patients. Everything that reads a [Patient] lives here, so
/// `lib/shared/dental_chart/` never imports a feature back.
DentalChartSession patientDentalChart(
  Patient patient, {
  ValueChanged<String>? onOpenAppointment,
  Widget Function(DentalChartSession session)? footer,
  Future<void> Function()? onSave,
}) {
  return DentalChartSession(
    id: 'patient:${patient.id}',
    titleKey: kDentalChartTitleKey,
    subtitle: () => patientOwnerLine(patient),
    type: StateType.state,
    teeth: patient.teeth,
    extraNotes: patient.teethExtraNotes,
    historyTitle: 'toothAppointmentNotes',
    history: () => [
      for (final appointment in patient.allAppointments)
        ToothHistory(
          label: DF.allNumbers(appointment.date),
          date: appointment.date,
          appointmentId: appointment.id,
          teeth: Map.of(appointment.teeth),
          notes: Map.of(appointment.teethExtraNotes),
        ),
    ],
    oldNotes: () => patient.allAppointmentsDentalNotes,
    showPrimary: patient.age < 14,
    onOpenAppointment: onOpenAppointment,
    footer: footer,
    onSave: onSave,
  );
}

/// Shows [patient]'s dental chart on its own — a window with the Save and Close
/// a panel would have offered, and those are the only way out of it.
///
/// Meant for when no panel is open: a panel's chart is one of its own windows
/// and takes precedence while the panel is on screen.
Future<void> openPatientDentalChart(
  Patient patient, {
  ValueChanged<String>? onOpenAppointment,
  Future<void> Function()? onOpenRecord,
}) async {
  final draft = Patient.fromJson(patient.toJson());
  final session = patientDentalChart(
    draft,
    onOpenAppointment: onOpenAppointment,
    footer: dentalHistoryVoiceAction(),
    onSave: () async {
      final stored = patients.get(draft.id);
      if (stored == null) {
        throw StateError('Patient ${draft.id} is no longer stored');
      }
      patients.set(stored.copy(false)
        ..teeth = Map<String, String>.from(draft.teeth)
        ..teethExtraNotes = Map<String, String>.from(draft.teethExtraNotes));
    },
  );
  showDentalChartWindow(session, onOpenRecord: onOpenRecord);
}

/// The dictation button the chart carries, when the clinic has it turned on:
/// recorded notes are merged into the chart the session edits.
Widget Function(DentalChartSession session)? dentalHistoryVoiceAction() {
  if (!network.isOnline() || !globalSettings.aiServicesEnabled) return null;
  return (session) => AudioRecorderButton(
        hint: txt('dentalHistoryVoiceAutoFillHint'),
        label: txt('voiceAutoFill'),
        onRecordingComplete: (bytes, mimeType) async {
          try {
            final result = await DentalHistory.processAudioBytes(
              bytes,
              mimeType,
            );
            if (result.teeth.isNotEmpty) session.teeth.addAll(result.teeth);
            if (result.teethExtraNotes.isNotEmpty) {
              session.extraNotes.addAll(result.teethExtraNotes);
            }
            session.changed();
          } catch (e, s) {
            showErrorMessage(e, 'processingDentalHistory');
            logger('Error processing dental history audio: $e', s);
          }
        },
      );
}
