import 'dart:async';
import 'dart:convert';

import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/row_panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/common_widgets/appointments_list_footer.dart';
import 'package:apexo/common_widgets/dental_chart_voice_action.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/context_menu_region.dart';
import 'package:apexo/features/appointments/appointment_menu_items.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:apexo/features/patients/patient_dental_chart.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_window.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:apexo/utils/print/print_link.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/qrlink.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/common_widgets/visits_button.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_gallery.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_owner_line.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart' hide TextBox;
import 'package:flutter/cupertino.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

part 'patient_panel_widgets.dart';

/// Opens the appointment a chart's history points at.
void _openAppointmentFromChart(String id) =>
    openAppointmentChartFromHistory(id);

/// Opens [patient]'s panel focused on [focus], adopting any standalone work.
Future<String?> openPatientPanel(Patient patient, {String? focus}) =>
    _openPatientPanel(Patient.fromJson(patient.toJson()), focus: focus);

/// Opens [patient] — its panel, or one of its windows on its own.
///
/// New patients are not made here: `addPatient` in `new_patient_dialog.dart`
/// asks for the name and phone and stores the record first, so nothing is
/// opened as a draft. Callers that have a patient in hand pass one.
Future<String?> openPatient(
    [Patient? patient, PatientWindow? window, BuildContext? context]) async {
  final editingCopy = Patient.fromJson(patient?.toJson() ?? {});
  // A window of a record whose panel is already open is that panel's window:
  // opening a second editor for the same teeth would give the record two
  // drafts, and whichever was saved last would win. The panel is brought
  // forward and asked for that window instead.
  final panelIsOpen =
      PanelsManager.active().any((panel) => panel.itemId == editingCopy.id);
  // A window that is not the panel's own body opens on its own: asking a table
  // for "this patient's appointments" should not unfold the whole record.
  if (!panelIsOpen && window != null && window != PatientWindow.details) {
    await _openPatientWindow(editingCopy, window);
    return null;
  }
  return _openPatientPanel(
    editingCopy,
    focus: window == PatientWindow.details ? null : window?.id,
    context: context,
  );
}

/// Shows the patient's whole list of visits, in its panel when the panel is up.
///
/// The list is a window of the patient's panel, opened from the record it
/// belongs to — a chart's title, a band's unsaved count. Opening it *here* means
/// the row arranges itself around it: at a width where the chart and the list do
/// not both fit, the list wins and the chart steps aside (it keeps its draft, and
/// the band keeps its chip).
Future<void> showPatientVisits(String patientId) async {
  final panel = PanelsManager.active()
      .where((panel) => panel.itemId == patientId)
      .firstOrNull;
  if (panel != null) {
    panel.showWindow(PatientWindow.appointments.id);
    return;
  }
  final patient = patients.get(patientId);
  if (patient == null) return;
  await openPatient(patient, PatientWindow.appointments);
}

/// The patient's record and nothing beside it: the panel, with none of the
/// windows it would otherwise open by itself. What a caller means when it wants
/// *the patient* rather than something the patient has — a dashboard row for a
/// new patient, say. Every window is still one click away in the dock.
Future<String?> openPatientRecord(Patient patient) => _openPatientPanel(
      Patient.fromJson(patient.toJson()),
      withWindows: false,
    );

/// The panel for [editingCopy], optionally focused on one of its windows.
Future<String?> _openPatientPanel(
  Patient editingCopy, {
  String? focus,
  bool withWindows = true,
  BuildContext? context,
}) async {
  final shown = await _ensurePatientPanel(
    editingCopy,
    focus: focus,
    withWindows: withWindows,
    context: context,
  );
  // The panel is done when the user saves it or closes it without saving.
  await shown.result;
  return shown.savedId;
}

/// Opens [patient]'s panel and hands it back **as soon as it is on screen**.
///
/// Not `openPatient`, which answers when the panel is saved or closed: a caller
/// that attaches something to the panel must not wait for the user to be finished
/// with it — that would attach to a panel the user has since closed (plan §7.1).
Future<Panel> ensurePatientPanel(Patient patient, {String? focus}) =>
    _ensurePatientPanel(
      Patient.fromJson(patient.toJson()),
      focus: focus,
      withWindows: true,
    );

/// The panel for [editingCopy], opening it if it is not up, and returning the one
/// on screen either way.
Future<Panel> _ensurePatientPanel(
  Patient editingCopy, {
  String? focus,
  bool withWindows = true,
  BuildContext? context,
}) async {
  // The panel holds these windows now, so the ones standing on their own for
  // this record have nothing left to show.
  final scope = 'patient:${editingCopy.id}';
  final stored = patients.get(editingCopy.id);

  // The patient's panel may already be on screen. Then this is not a new
  // panel: the editor is already there, and a panel built here would be thrown
  // away — taking the work it had adopted with it, silently. So the question
  // is asked *before* any window state is touched.
  final identifier = Panel.identifierFor(
    'patient',
    editingCopy.id,
    isNew: stored == null,
  );
  final existing = PanelsManager.find(identifier);
  if (existing != null) {
    if (focus == kDentalChartWindowId) {
      // The plan is the patient's chart, not a second chart beside the visit.
      // Leaving the visit here keeps its draft, owned by the panel and marked by
      // the Visits button.
      existing.detach();
      if (!await closeOpenDentalChartWindows(
          exceptScope: scope, context: context)) {
        return existing;
      }
    }
    closeBorrowedDentalChart(scope);
    WindowsManager.showOnPanel(existing, scope: scope, focus: focus);
    return existing;
  }

  // Work a window of this patient still holds comes in with the panel rather
  // than staying beside it as a second draft of the same record: the panel
  // adopts it and opens dirty on it, so its own Save is the one write.
  String? baseline;
  if (stored != null) {
    final carried = WindowsManager.adoptWork(scope, stored.toJson());
    if (carried != null) {
      editingCopy = Patient.fromJson(carried);
      baseline = jsonEncode(stored.toJson());
    }
  }
  WindowsManager.closeScope(scope);
  final chart = patientDentalChart(
    editingCopy,
    onOpenAppointment: _openAppointmentFromChart,
    footer: dentalHistoryVoiceAction(),
  );
  if (stored != null && baseline != null) {
    chart.setBaseline(
      teeth: stored.teeth,
      extraNotes: stored.teethExtraNotes,
    );
  }
  late final RowPanel<Patient> panel;
  panel = RowPanel<Patient>(
    singularName: "patient",
    accent: PanelAccents.patient,
    unicodeSymbol: "👤",
    // The two records on this screen save differently, and their buttons say so.
    saveLabel: 'savePatient',
    // The window that lists the visits this panel carries: where the band's
    // unsaved count leads.
    recordsWindowId: PatientWindow.appointments.id,
    // The record's own workspaces sit inside the record, as two prominent
    // buttons under its name: the chart and the visits list are what the record
    // is *for*, so they must not hide among header icons.
    workspaceWindows: [
      PatientWindow.dentalChart.id,
      PatientWindow.appointments.id
    ],
    attachmentLayout: true,
    // The window the caller asked for: a table cell that means "the
    // appointments" asks for it here rather than counting windows.
    initialWindow: focus,
    opensWithWindows: withWindows,
    item: editingCopy,
    store: patients,
    icon: FluentIcons.medication_admin,
    existing: patients.get(editingCopy.id) != null,
    // The record on screen carries work that is not stored yet, so the panel
    // starts with something to save.
    savedBaseline: baseline,
    onSave: () {
      patients.set(Patient.fromJson(jsonDecode(jsonEncode(editingCopy.toJson()))
          as Map<String, dynamic>));
      chart.markSaved();
    },
    validate: () =>
        Patient.isValidEmail(editingCopy.email) ? null : txt('invalidEmail'),
    // A localization key rather than a sentence: the header runs it through
    // txt(), so it follows the language the app is in now. A stored patient
    // gets their own name from readTitle() below instead.
    title: "newPatient",
    windows: [
      for (final entry in patientWindows())
        switch (entry) {
          PatientWindow.details => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              body: _PatientDetails(editingCopy),
            ),
          PatientWindow.dentalChart => dentalChartWindow(
              chart,
              // The patient's whole list of visits is also reachable from the
              // plan tab: the list is a property of the patient, not of the visit
              // whose chart happens to be open.
              actions: <Widget>[
                if (patients.get(editingCopy.id) != null)
                  PatientVisitsButton(
                    onPressed: () =>
                        unawaited(showPatientVisits(editingCopy.id)),
                  ),
              ],
            ),
          PatientWindow.appointments => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              subtitle: () => patientOwnerLine(editingCopy),
              body: PatientAppointments(editingCopy),
              footer: AppointmentsListFooter(forPatientID: editingCopy.id),
              onlyIfSaved: true,
              padding: 0,
              // The list is a side window, not a first pick: it is one button in
              // the header, and opening the record is not opening its history.
              byDefault: false,
              // One card per visit: the list asks for the room its visits take,
              // so a short history is a short window and a longer one is not
              // squeezed into half a screen.
              maxHeight: appointmentsListMaxHeight,
              minHeight: appointmentsListHeight(
                editingCopy.allAppointments.length,
              ),
            ),
          PatientWindow.gallery => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              subtitle: () => patientOwnerLine(editingCopy),
              body: PatientGallery(editingCopy),
              onlyIfSaved: true,
              padding: 0,
              // A patient's photos are an attachment of the record, not a row
              // window: a chip under the details, one click from its editor.
              attachedTo: PanelWindow.panelAttachment,
              // One card per visit that holds photos, so the window asks for
              // the room its cards take — as the visits list does.
              maxHeight: appointmentsListMaxHeight,
              minHeight: appointmentsListHeight(
                patientGalleryVisits(editingCopy).length,
              ),
            ),
          PatientWindow.page => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              subtitle: () => patientOwnerLine(editingCopy),
              body: _PatientQrPage(
                editingCopy: editingCopy,
                onFieldsSaved: (fields) => panel.markFieldsSaved(fields),
              ),
              onlyIfSaved: true,
              // The shareable page is an attachment of the record too.
              attachedTo: PanelWindow.panelAttachment,
            ),
        },
    ],
  );
  panel.workspace.revision.observe((_) {
    if (!panel.workspace.isOpen(kDentalChartWindowId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!PanelsManager.active().contains(panel) ||
          !panel.workspace.isOpen(kDentalChartWindowId)) {
        return;
      }
      if (!await closeOpenDentalChartWindows(exceptScope: scope)) {
        panel.workspace.hide(kDentalChartWindowId);
      }
    });
  });
  await panel.readTitle();
  return PanelsManager.open(panel);
}

/// A patient's window, shown on its own — no panel, so it carries the Save and
/// Close a panel would have offered (Close alone for a window that only reads).
///
/// This is what a table cell, a chart link or a context-menu item means when it
/// names one window: the edit the user asked for, not the whole record.
Future<void> _openPatientWindow(Patient patient, PatientWindow window) async {
  final scope = 'patient:${patient.id}';
  switch (window) {
    case PatientWindow.details:
      // The panel *is* the details; the caller wanted the record.
      await openPatient(patient);
    case PatientWindow.dentalChart:
      await openPatientDentalChart(
        patient,
        onOpenAppointment: _openAppointmentFromChart,
        onOpenRecord: () =>
            _openPatientPanel(patient, focus: PatientWindow.dentalChart.id),
      );
    case PatientWindow.appointments:
      late final FloatingWindow floating;

      /// The list was only a way in: whatever it opens — a visit it lists, or a
      /// new one it starts — it closes, so the panel has the screen to itself.
      void closeThen(void Function() open) {
        WindowsManager.close(floating);
        open();
      }

      floating = WindowsManager.showStandalone(
        PanelWindow(
          id: window.id,
          title: window.titleKey,
          icon: window.icon,
          subtitle: () => patientOwnerLine(patient),
          maxHeight: appointmentsListMaxHeight,
          minHeight: appointmentsListHeight(patient.allAppointments.length),
          padding: 0,
          body: PatientAppointments(
            patient,
            onOpenAppointment: (appointment, window) =>
                closeThen(() => openAppointment(appointment, window)),
          ),
          footer: AppointmentsListFooter(
            forPatientID: patient.id,
            onOpen: (draft) => closeThen(() => openAppointment(draft)),
          ),
        ),
        scope: scope,
        onOpenRecord: () => _openPatientPanel(patient, focus: window.id),
      );
    case PatientWindow.gallery:
      late final FloatingWindow floating;

      /// The gallery is only a way in: whatever it opens closes it, so the
      /// visit has the screen to itself.
      void closeThen(void Function() open) {
        WindowsManager.close(floating);
        open();
      }

      floating = WindowsManager.showStandalone(
        PanelWindow(
          id: window.id,
          title: window.titleKey,
          icon: window.icon,
          subtitle: () => patientOwnerLine(patient),
          maxHeight: appointmentsListMaxHeight,
          minHeight:
              appointmentsListHeight(patientGalleryVisits(patient).length),
          padding: 0,
          body: PatientGallery(
            patient,
            onOpenVisit: (appointment, visitWindow) =>
                closeThen(() => openAppointment(appointment, visitWindow)),
          ),
        ),
        scope: scope,
        onOpenRecord: () => _openPatientPanel(patient, focus: window.id),
      );
    case PatientWindow.page:
      WindowsManager.showStandalone(
        PanelWindow(
          id: window.id,
          title: window.titleKey,
          icon: window.icon,
          subtitle: () => patientOwnerLine(patient),
          body: _PatientQrPage(
            editingCopy: patient,
            onFieldsSaved: (_) {},
          ),
        ),
        scope: scope,
        onOpenRecord: () => _openPatientPanel(patient, focus: window.id),
      );
  }
}
