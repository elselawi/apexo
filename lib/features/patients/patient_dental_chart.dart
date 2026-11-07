import 'dart:async';

import 'package:apexo/common_widgets/dental_chart_voice_action.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/common_widgets/visits_button.dart';
import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_owner_line.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The patient half of the shared chart editor; `lib/shared/dental_chart/`
/// must not import a feature back.
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
    onOpenAppointment: onOpenAppointment ?? openAppointmentChartFromHistory,
    header: (session) => VisitScopeBar(patient: patient, session: session),
    footer: footer,
    onSave: onSave,
  );
}

/// Shows the chart on its own with its own Save/Close; an open panel's
/// session is reused so there is only ever one draft.
Future<void> openPatientDentalChart(
  Patient patient, {
  ValueChanged<String>? onOpenAppointment,
  Future<void> Function()? onOpenRecord,
  BuildContext? context,
}) async {
  final scope = 'patient:${patient.id}';
  final direction = dentalChartNavigationDirection(scope);
  if (!await closeOpenDentalChartWindows(
      exceptScope: scope, context: context, direction: direction)) {
    return;
  }
  final hosted = panelDentalChart(scope);
  if (hosted != null) hosted.navigationDirection = direction;
  final active = PanelsManager.active().lastOrNull;
  if (active != null &&
      active.singularName == 'patient' &&
      active.itemId == patient.id) {
    // The plan replaces the visit's chart: closing the visit keeps its draft.
    active.detach();
    closeBorrowedDentalChart(scope);
    WindowsManager.showOnPanel(
      active,
      scope: scope,
      focus: kDentalChartWindowId,
    );
    return;
  }
  if (hosted != null) {
    final owner = PanelsManager.active().firstWhere((panel) =>
        panel.singularName == 'patient' && panel.itemId == patient.id);
    WindowsManager.showStandalone(
      dentalChartWindow(hosted, actions: _visitsActions(patient)),
      scope: scope,
      recordSession: owner,
      onSave: owner.save,
      hasChanges: () => hosted.hasChanges,
      transfer: hosted.mergeInto,
      onOpenRecord: onOpenRecord ??
          () => openPatientPanel(patient, focus: kDentalChartWindowId),
    );
    return;
  }
  final current = patients.get(patient.id) ?? patient;
  final draft = Patient.fromJson(current.toJson());
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
  session.navigationDirection = direction;
  showDentalChartWindow(
    session,
    actions: _visitsActions(patient),
    onOpenRecord: onOpenRecord ??
        () => openPatientPanel(draft, focus: kDentalChartWindowId),
  );
}

/// The plan tab's way into the patient's visits list; the list belongs to the
/// patient, not to the chart scope.
List<Widget> _visitsActions(Patient patient) => <Widget>[
      PatientVisitsButton(
        onPressed: () => unawaited(showPatientVisits(patient.id)),
      ),
    ];
