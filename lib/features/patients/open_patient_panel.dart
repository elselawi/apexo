import 'dart:async';
import 'dart:convert';

import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/row_panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/common_widgets/app_combo_box.dart';
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
import 'package:apexo/features/patients/patient_follow_up_bar.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_window.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/utils/app_flyout_controller.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:apexo/utils/print/print_link.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/qrlink.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/follow_up_card.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
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

Future<String?> openPatient(
    [Patient? patient, PatientWindow? window, BuildContext? context]) async {
  final editingCopy = Patient.fromJson(patient?.toJson() ?? {});
  // A named window opens in the record's own panel, shown by default, whenever a
  // panel is on screen: a second editor would be a second draft, and beside
  // another record's panel a floating one is a second surface. Only with no panel
  // does it stand on its own. Details *is* the record, so it always opens the
  // panel.
  if (PanelsManager.allowsStandaloneWindows &&
      window != null &&
      window != PatientWindow.details) {
    await _openPatientWindow(editingCopy, window);
    return null;
  }
  return _openPatientPanel(
    editingCopy,
    focus: window == PatientWindow.details ? null : window?.id,
    context: context,
  );
}

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

/// Opens [patient]'s panel and returns it as soon as it is on screen, unlike
/// `openPatient`, which waits for the panel to be saved or closed.
Future<Panel> ensurePatientPanel(Patient patient, {String? focus}) =>
    _ensurePatientPanel(
      Patient.fromJson(patient.toJson()),
      focus: focus,
      withWindows: true,
    );

Future<Panel> _ensurePatientPanel(
  Patient editingCopy, {
  String? focus,
  bool withWindows = true,
  BuildContext? context,
}) async {
  final scope = 'patient:${editingCopy.id}';
  final stored = patients.get(editingCopy.id);

  // Ask before touching window state: a panel built while one is already on
  // screen would be discarded, silently taking the work it adopted with it.
  final identifier = Panel.identifierFor(
    'patient',
    editingCopy.id,
    isNew: stored == null,
  );
  final existing = PanelsManager.find(identifier);
  if (existing != null) {
    if (focus == kDentalChartWindowId) {
      // The plan is the patient's chart, not a second one beside the visit;
      // the visit keeps its draft under the panel.
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

  // Work still held by a standalone window is adopted by the panel, so its
  // Save is the only write.
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
    carriedDraftWindowId: PatientWindow.dentalChart.id,
    workspaceWindows: [
      PatientWindow.dentalChart.id,
      PatientWindow.appointments.id
    ],
    attachmentLayout: true,
    carriedBandFooter: PatientFollowUpBar(patientID: editingCopy.id),
    initialWindow: focus,
    opensWithWindows: withWindows,
    item: editingCopy,
    store: patients,
    icon: FluentIcons.medication_admin,
    existing: patients.get(editingCopy.id) != null,
    // Carried work is unsaved, so the panel starts with something to save.
    savedBaseline: baseline,
    onSave: () {
      patients.set(Patient.fromJson(jsonDecode(jsonEncode(editingCopy.toJson()))
          as Map<String, dynamic>));
      chart.markSaved();
    },
    validate: () =>
        Patient.isValidEmail(editingCopy.email) ? null : txt('invalidEmail'),
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
              byDefault: false,
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
              attachedTo: PanelWindow.panelAttachment,
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

/// A patient's window shown on its own — only ever with no panel on screen, so
/// nothing behind it competes for the record — with the Save/Close a panel would
/// have provided. Its Open record asks for the record itself, never the window
/// the user came from, which would leave the same list in front.
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
      );
    case PatientWindow.appointments:
      late final FloatingWindow floating;

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
        onOpenRecord: () => _openPatientPanel(patient),
      );
    case PatientWindow.gallery:
      late final FloatingWindow floating;

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
        onOpenRecord: () => _openPatientPanel(patient),
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
        onOpenRecord: () => _openPatientPanel(patient),
      );
  }
}
