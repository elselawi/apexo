import 'dart:async';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_session.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;

export 'package:apexo/features/appointments/appointment_commands.dart'
    show
        appointmentCommand,
        canEditAppointments,
        canViewPostOp,
        liveAppointment,
        transcriptionEditCounter,
        writeVisitImages;
export 'package:apexo/features/appointments/appointment_dental_chart.dart'
    show appointmentDentalChart, openAppointmentDentalChart;
export 'package:apexo/features/appointments/appointment_labwork_widgets.dart'
    show AppointmentLabworkSection;
export 'package:apexo/features/appointments/appointment_windows.dart'
    show AppointmentWindow, appointmentWindows;

/// Opens [appointment] beside its patient. A patient the current account may not
/// see routes the visit to its standalone windows, never to the patient record.
Future<void> openAppointment([
  Appointment? appointment,
  AppointmentWindow? window,
]) =>
    _openVisit(
      appointment,
      focus: window?.id,
      preferBand: window == null || window == AppointmentWindow.details,
    );

/// Opens one of [appointment]'s windows where it belongs: standing on its own
/// while no panel is on screen, and in the visit's own panel — that window shown
/// by default — once one is. The same session owns the draft either way, so the
/// window's Save still writes the visit.
Future<void> openAppointmentWindowOnItsOwn(
  Appointment appointment,
  AppointmentWindow window,
) {
  // A window on its own still links back to its visit, but never to a patient
  // record this account may not see.
  final patient = patients.get(appointment.patientID ?? '');
  final hidden = patient == null || patient.locked;
  if (!hidden && !PanelsManager.allowsStandaloneWindows) {
    return openAppointment(appointment, window);
  }
  return _openStandaloneVisit(
    appointment,
    focus: window.id,
    onOpenRecord: hidden ? null : () => openAppointment(appointment),
  );
}

/// Opens a visit window through [openAppointment] on purpose: naming a window
/// must reach the visit, not start a second draft of it.
void openAppointmentWindow(Appointment appointment, AppointmentWindow window) {
  unawaited(openAppointment(appointment, window));
}

/// Makes [visitId] the selected visit of [patientId]'s panel, attaching it if
/// needed. Never prompts or drops a draft: switching visits is non-destructive.
Future<void> selectVisit(
  String patientId,
  String visitId, {
  String? focus,
  BuildContext? context,
}) async {
  final appointment = appointments.get(visitId);
  if (appointment == null) {
    await showAppointmentUnavailable();
    return;
  }
  await _openVisit(appointment,
      focus: focus, context: context, preferBand: focus == null);
}

/// Opens the visit a notification or deep link names. A missing id is reported
/// and opens nothing; it never means a new visit.
Future<void> openAppointmentById(String id) async {
  final appointment = appointments.get(id);
  if (appointment == null) {
    await showAppointmentUnavailable();
    return;
  }
  await openAppointment(appointment);
}

/// Detaches the selected visit from its patient panel, keeping every draft.
/// Losing a draft means disposing the session, which only a close prompt does.
void detachVisits() {
  for (final panel in PanelsManager.active()) {
    if (panel.attached != null) panel.detach();
  }
}

/// Shows the patient's own chart. Only one chart is on screen, so it replaces the
/// visit's chart and detaches the visit from the panel.
Future<void> showPatientChart(String patientId, {BuildContext? context}) async {
  final patient = patients.get(patientId);
  if (patient == null) return;
  final panel = PanelsManager.active()
      .where((panel) =>
          panel.singularName == 'patient' && panel.itemId == patient.id)
      .firstOrNull;
  panel?.detach();
  await openPatient(patient, PatientWindow.dentalChart, context);
}

Future<void> _openVisit(
  Appointment? appointment, {
  String? focus,
  BuildContext? context,
  bool preferBand = false,
}) async {
  if (appointment == null) return;
  appointment = liveAppointment(appointment.id) ?? appointment;
  final patient = patients.get(appointment.patientID ?? '');

  // A patient this account may not see sends the visit to its standalone windows,
  // never to the patient record (`Patient.locked`).
  if (patient == null || patient.locked) {
    await _openStandaloneVisit(appointment, focus: focus);
    return;
  }

  final session = appointmentSessions.getOrCreate(appointment);
  final compact = _isCompact(context);
  // A phone shows one surface: opening the visit itself lands on the band.
  final wanted = compact && preferBand ? null : _attachedFocus(focus);

  if (wanted == kDentalChartWindowId) {
    // Replacing a chart may cost its unsaved work, so only the user may allow it.
    // Read the direction first so the new chart slides into the old one's slot.
    final direction = dentalChartNavigationDirection(session.scope);
    if (!await closeOpenDentalChartWindows(
        exceptScope: session.scope, context: context, direction: direction)) {
      return;
    }
    session.chart.navigationDirection = direction;
  }

  final panel = await ensurePatientPanel(patient);
  if (compact && preferBand) {
    // Opening a visit means the band: bring the panel forward and take every chart
    // off its surface. Nothing is discarded by looking at the visit.
    PanelsManager.minimize(false);
    panel.workspace.hide(kDentalChartWindowId);
    panel.workspace.clearSlot(kAttachedSlot);
    // A phone draws one surface, so the panel's own window the visit was opened
    // from (the appointments list) gives way to the band instead of staying over
    // it, as if nothing had opened.
    panel.workspace.clearSlot(kHostSlot);
  }
  panel.attach(session, focus: wanted);
}

/// True for a phone-sized screen; with no screen at all (a test), not compact.
bool _isCompact(BuildContext? context) {
  BuildContext? target = context;
  if (target == null || !target.mounted) {
    try {
      target = bContext;
    } catch (_) {
      return false;
    }
  }
  if (!target.mounted) return false;
  final size = MediaQuery.maybeOf(target)?.size;
  return size != null && size.width < kWindowsBreakpoint;
}

/// The form is the band and the post-op record sits under the chart, so naming
/// either opens the chart they belong to.
String _attachedFocus(String? focus) {
  if (focus == null ||
      focus == AppointmentWindow.details.id ||
      focus == AppointmentWindow.operative.id) {
    return kDentalChartWindowId;
  }
  return focus;
}

/// A finished visit reopens on its post-op record, when the account may view it.
String? _defaultFocus(AppointmentSession session) =>
    session.item.isDone && canViewPostOp(session.item)
        ? AppointmentWindow.operative.id
        : null;

/// The visit's windows with no patient panel behind them: no panel is on screen,
/// or the patient is locked or missing. The window still saves the visit, but
/// there is no patient dock.
Future<void> _openStandaloneVisit(
  Appointment appointment, {
  String? focus,
  Future<void> Function()? onOpenRecord,
}) async {
  final session = appointmentSessions.getOrCreate(appointment);
  final wanted = focus ?? _defaultFocus(session);
  if (wanted == kDentalChartWindowId) {
    if (!await closeOpenDentalChartWindows(exceptScope: session.scope)) return;
    session.chart.navigationDirection =
        dentalChartNavigationDirection(session.scope);
  }
  final existing = WindowsManager.open()
      .where((floating) => floating.scope == session.scope)
      .toList();
  if (existing.isNotEmpty) {
    // Already on screen: raise what is there, or open the named window — never a
    // second copy of it.
    final named = wanted == null
        ? null
        : existing
            .where((floating) => floating.window.id == wanted)
            .firstOrNull;
    if (named != null) {
      WindowsManager.show(named);
      return;
    }
    if (wanted == null) {
      WindowsManager.show(existing.last);
      return;
    }
  }
  final windows = appointmentSessionWindows(
    session,
    onOpenRecord: () => openAppointment(session.item),
    attached: false,
  ).where((window) => !(window.onlyIfSaved && session.isNew)).toList();
  if (windows.isEmpty) return;
  final target = windows.where((window) => window.id == wanted).firstOrNull ??
      windows.first;
  WindowsManager.showStandalone(
    target,
    scope: session.scope,
    recordSession: session,
    onSave: target.editsRecord ? session.save : null,
    hasChanges: target.editsRecord ? () => session.hasPendingEdits : null,
    onOpenRecord: onOpenRecord,
  );
}
