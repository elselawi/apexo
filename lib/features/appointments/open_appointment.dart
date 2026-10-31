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

/// Opens [appointment] **beside its patient** — the one way into a visit.
///
/// The visit does not become a panel: it becomes a session — one draft, one Save,
/// one identity — whose windows are drawn in the patient panel's own row
/// (plan §0). Every entry point in the app ends up here: a calendar drag's row,
/// a dashboard's reminder, a patient's history, a photo, a notification.
///
/// [window] names the window the caller came for. The opener resolves the patient
/// first, and a patient the current account may not see routes the visit to its
/// standalone windows instead — the visit's own windows, and never the patient
/// record (plan §0.1).
///
/// On a phone, opening **the visit itself** — no window, or its form — opens the
/// patient panel with the visit's band and nothing over it. The chart is 960
/// pixels of workspace; as a sheet it would cover the date, time and duration the
/// user came to read. A caller that names a window still gets that window, because
/// it asked for it.
Future<void> openAppointment([
  Appointment? appointment,
  AppointmentWindow? window,
]) =>
    _openVisit(
      appointment,
      focus: window?.id,
      preferBand: window == null ||
          window == AppointmentWindow.details ||
          window == AppointmentWindow.operative,
    );

/// Opens one of [appointment]'s windows **on its own** — no patient panel, no
/// chart, no other window of the visit.
///
/// This is what a labwork row means: the order is the thing the user came for,
/// and unfolding the patient's record beside it buries the order under the
/// record it belongs to. The same session still owns the draft, so the window's
/// Save writes the visit.
Future<void> openAppointmentWindowOnItsOwn(
  Appointment appointment,
  AppointmentWindow window,
) {
  // A window on its own still needs a way back to the visit it edits — but never
  // to a patient record this account may not see (plan §0.1).
  final patient = patients.get(appointment.patientID ?? '');
  return _openStandaloneVisit(
    appointment,
    focus: window.id,
    onOpenRecord: patient == null || patient.locked
        ? null
        : () => openAppointment(appointment),
  );
}

/// Opens one of [appointment]'s windows — the same door as [openAppointment], on
/// purpose: a caller that names a window of a visit must reach the visit, not
/// start a second draft of it.
void openAppointmentWindow(Appointment appointment, AppointmentWindow window) {
  unawaited(openAppointment(appointment, window));
}

/// Makes [visitId] the selected visit of [patientId]'s panel, attaching it if it
/// is not attached yet.
///
/// Every control that can change the selection calls this — the Visits list, the
/// chart's scope bar, an itinerary row — so two controls can never disagree about
/// which visit is selected (plan §4.8). It never discards a draft and never
/// prompts: switching visits is not destructive, because the drafts are retained.
Future<void> selectVisit(
  String patientId,
  String visitId, {
  String? focus,
  BuildContext? context,
}) async {
  final appointment = appointments.get(visitId);
  if (appointment == null) {
    // A notification names a visit that is gone — or has not synced yet. There is
    // nothing to open, and opening a blank editor for it would be worse.
    await showAppointmentUnavailable();
    return;
  }
  await _openVisit(appointment,
      focus: focus,
      context: context,
      // Choosing a visit from a list is opening the visit; choosing a scope in a
      // chart is opening that chart. On a phone only the first lands on the band.
      preferBand: focus == null);
}

/// Opens the visit with [id] — what a notification or a deep link carries.
///
/// A record that is not on this device says so once and opens nothing: resolving
/// by id is the whole contract, and a missing id is not a new visit.
Future<void> openAppointmentById(String id) async {
  final appointment = appointments.get(id);
  if (appointment == null) {
    await showAppointmentUnavailable();
    return;
  }
  await openAppointment(appointment);
}

/// Takes the selected visit out of its patient panel's row, keeping every draft.
///
/// What "close the visit" means now that a visit is not a panel: the patient
/// panel stays, the visit's windows leave, and nothing typed is lost — the draft
/// is still owned by the panel, dotted where the band and the dock say so
/// (plan §4.6). A caller that means to *lose* the draft disposes the session
/// instead, which only a close prompt does.
void detachVisits() {
  for (final panel in PanelsManager.active()) {
    if (panel.attached != null) panel.detach();
  }
}

/// Opens the patient's own chart, putting the visit's chart away.
///
/// One chart is on screen at a time (plan §4.3): the visit's chart replaces the
/// patient's while a visit is attached, and asking for the patient's plan is
/// asking to see the other one.
Future<void> showPatientChart(String patientId, {BuildContext? context}) async {
  final patient = patients.get(patientId);
  if (patient == null) return;
  // The patient's plan is the other chart, not a second one beside the visit.
  // Switching to it closes the visit from the panel — the band belongs to the
  // visit, and its draft is retained for when the visit is reopened.
  final panel = PanelsManager.active()
      .where((panel) =>
          panel.singularName == 'patient' && panel.itemId == patient.id)
      .firstOrNull;
  panel?.detach();
  await openPatient(patient, PatientWindow.dentalChart, context);
}

/// The one opener: resolve the patient, attach the visit, or stand the visit on
/// its own.
Future<void> _openVisit(
  Appointment? appointment, {
  String? focus,
  BuildContext? context,
  bool preferBand = false,
}) async {
  // There is no such thing as opening "no visit": a new visit is created by the
  // dialog that stores it first (plan §8.3).
  if (appointment == null) return;
  appointment = liveAppointment(appointment.id) ?? appointment;
  final patient = patients.get(appointment.patientID ?? '');

  // A patient the current account may not see takes the visit's windows with it,
  // and never the patient record: that is exactly what `Patient.locked` is for
  // (plan §0.1).
  if (patient == null || patient.locked) {
    await _openStandaloneVisit(appointment, focus: focus);
    return;
  }

  final session = appointmentSessions.getOrCreate(appointment);
  final compact = _isCompact(context);
  // A phone shows one surface at a time. When the user opened *the visit*, the
  // band is that surface: a chart sheet would cover the date, time and duration
  // the band exists to show (the design brief).
  final wanted = compact && preferBand ? null : _attachedFocus(focus);

  if (wanted == kDentalChartWindowId) {
    // One chart on screen, and replacing another one may cost its unsaved work:
    // only the user can say whether it may. The direction between the two scopes
    // is read *before* the old chart is hidden — that is what makes the change of
    // visit a slide in the slot the chart already occupies (plan §4.3).
    final direction = dentalChartNavigationDirection(session.scope);
    if (!await closeOpenDentalChartWindows(
        exceptScope: session.scope, context: context, direction: direction)) {
      return;
    }
    session.chart.navigationDirection = direction;
  }

  final panel = await ensurePatientPanel(patient);
  if (compact && preferBand) {
    // The panel may be minimized, or still showing a chart sheet — its own or
    // the previous visit's. Opening a visit means the band: bring the panel
    // forward and take every chart off the panel's own surface. The drafts stay
    // on their records; nothing is discarded by looking at the visit.
    PanelsManager.minimize(false);
    panel.workspace.hide(kDentalChartWindowId);
    panel.workspace.clearSlot(kAttachedSlot);
  }
  panel.attach(session, focus: wanted);
}

/// Whether the screen [context] draws on is a phone-sized one, where a panel
/// fills the window and windows come over it one at a time. Null when there is no
/// screen to ask — a test opening a visit without an app — and then the caller is
/// not on a phone.
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

/// Which window a visit shows when it is drawn **beside its patient**.
///
/// The appointment's own form is the band, and the post-op record sits under the
/// visit's chart: so "the visit" means **the chart**, and asking for the form or
/// the post-op record opens the chart they are part of. A finished visit opens
/// exactly as a pending one does — both have their whole record in the same
/// three places (the design brief).
String _attachedFocus(String? focus) {
  if (focus == null ||
      focus == AppointmentWindow.details.id ||
      focus == AppointmentWindow.operative.id) {
    return kDentalChartWindowId;
  }
  return focus;
}

/// A finished visit reopens on its post-op record — what the user came back to
/// the visit for. Standing on its own, that record is still its own window, so
/// the old rule survives where it still has a window to point at.
String? _defaultFocus(AppointmentSession session) =>
    session.item.isDone && canViewPostOp(session.item)
        ? AppointmentWindow.operative.id
        : null;

/// The visit's windows with no patient panel behind them: the record the current
/// account may not see, or one whose patient is gone.
///
/// The requested window opens on its own, carrying the session's own Save; the
/// visit's other windows are one click away from a dock on the same window. No
/// patient dock, no patient window, no band (plan §0.1, §4.7).
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
    // The visit is already on screen: asking for it again raises what is there,
    // and asking for one of its windows opens that one — never a second copy of
    // the window that happens to be up.
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
