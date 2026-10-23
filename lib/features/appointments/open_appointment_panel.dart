import 'dart:async';
import 'dart:convert';

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/row_panel.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_dental_chart.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_window.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/features/labwork/open_labwork_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/ai_services/post_op_notes.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/utils/money_editing_controller.dart';
import 'package:apexo/utils/money_input_formatter.dart';
import 'package:apexo/utils/print/print_prescription.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/duration_pill.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/common_widgets/operators_picker.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/utils/uuid.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

part 'appointment_windows.dart';
part 'appointment_labwork_widgets.dart';

void closeAppointmentsPanels() {
  final List<String> toClose = [];
  for (var panel in PanelsManager.active()) {
    final identifier = panel.identifier;
    if (identifier.contains("appointments") ||
        appointments.get(identifier) != null) {
      toClose.add(identifier);
    }
  }
  for (final identifier in toClose) {
    PanelsManager.close(identifier);
  }
}

final transcriptionEditCounter = ObservableState(0);

/// Whether the post-op tab can be read for [appointment].
bool canViewPostOp(Appointment? appointment) =>
    login.perm(Perm.postOp).exact(2) ||
    (login.perm(Perm.postOp).exact(1) &&
        appointment?.operatorsIDs.contains(login.currentAccountID) == true);

/// Whether the user may change the visits operated by [operatorIDs].
///
/// An admin, whoever has full access to visits, and the visits' own operators
/// may; nobody else may. The gate for everything that writes to a visit — the
/// post-op record, its labwork order, its gallery — so that one rule cannot
/// be applied more loosely in one place than in another.
bool canEditAppointments(List<String> operatorIDs) {
  if (login.isAdmin) return true;
  if (login.perm(Perm.appointments).full) return true;
  return operatorIDs.contains(login.currentAccountID);
}

/// The windows the appointment panel offers, in the order it offers them.
///
/// The panel builds its list from [appointmentWindows], the row context menu
/// offers one item per entry, and callers name a window through the enum, so
/// none of them can drift from the others.
enum AppointmentWindow {
  details('details', "appointment", WindowsIcons.calendar),

  /// The dental chart, beside the details: the treatments given at this visit,
  /// with the record's own teeth and the other visits beside it as history.
  dentalChart(kDentalChartWindowId, kTreatmentsTitleKey, FluentIcons.teeth),
  operative('operative', "operativeDetails", FluentIcons.medical_care),
  labwork('labwork', "labwork", FluentIcons.manufacturing),
  gallery('gallery', "gallery", FluentIcons.camera);

  const AppointmentWindow(this.id, this.titleKey, this.icon);

  /// The window's [PanelWindow.id], for panels and openers to name it by.
  final String id;

  /// The window's title key, and the line that says whose it is. A side window
  /// must answer "which appointment is this?" on its own: several can be open at
  /// once, and their labels are all "Operative details".
  final String titleKey;
  final IconData icon;

  /// Whose window this is: the visit's patient, day and state.
  String Function() ownerFor(Appointment appointment) =>
      () => appointmentOwnerLine(appointment);
}

/// The appointment panel's windows for [appointment], in panel order.
List<AppointmentWindow> appointmentWindows(Appointment? appointment) => [
      AppointmentWindow.details,
      AppointmentWindow.dentalChart,
      if (canViewPostOp(appointment)) AppointmentWindow.operative,
      AppointmentWindow.labwork,
      AppointmentWindow.gallery,
    ];

/// Opens the appointment a chart's history points at.
void _openAppointmentFromChart(String id) {
  final previous = appointments.get(id);
  if (previous != null) openAppointment(previous);
}

/// Opens [appointment] — its panel, or one of its windows on its own.
///
/// A window that is not the panel's own body (the chart, the post-op record, the
/// labwork, the gallery) opens by itself when a caller names it, the way a table
/// cell means "the labwork of this visit" rather than "this whole record".
void openAppointment(
    [Appointment? appointment, AppointmentWindow? window]) async {
  final editingCopy = Appointment.fromJson(appointment?.toJson() ?? {});
  // A window of a record whose panel is already open is that panel's window:
  // opening a second editor for the same visit would give the record two
  // drafts, and whichever was saved last would win. The panel is brought
  // forward and asked for that window instead.
  final panelIsOpen = appointment != null &&
      PanelsManager.active().any((panel) => panel.itemId == editingCopy.id);
  // A window stands on its own only for a record that exists: a new visit has
  // nothing stored for its windows to write.
  if (!panelIsOpen &&
      appointment != null &&
      window != null &&
      window != AppointmentWindow.details) {
    await _openAppointmentWindow(editingCopy, window);
    return;
  }

  // A finished visit opens on its post-op record: that is what the user came
  // back to the appointment for.
  final focus = window ??
      (appointment != null && appointment.isDone && canViewPostOp(appointment)
          ? AppointmentWindow.operative
          : null);
  await _openAppointmentPanel(editingCopy, focus: focus?.id);
}

/// The visit's panel, focused on [focus] — where a window's own "open record"
/// button lands, and where the panel starts when it is opened for a record.
Future<void> _openAppointmentPanel(
  Appointment editingCopy, {
  String? focus,
}) async {
  // The visit's panel speaks for the visit, so the panel editing its labwork
  // order has nothing more to say. Only the panel does this: a window that
  // stands on its own is not a reason to close anything.
  closeLabworksPanels();

  // The panel holds these windows now, so the ones standing on their own for
  // this record have nothing left to show.
  final scope = 'appointment:${editingCopy.id}';
  final stored = appointments.get(editingCopy.id);

  // The visit's panel may already be on screen. Then this is not a new panel:
  // the editor is already there, and a panel built here would be thrown away —
  // taking the work it had adopted with it, silently. So the question is asked
  // *before* any window state is touched.
  final identifier = Panel.identifierFor(
    'appointment',
    editingCopy.id,
    isNew: stored == null,
  );
  final existing = PanelsManager.find(identifier);
  if (existing != null) {
    WindowsManager.showOnPanel(existing, scope: scope, focus: focus);
    return;
  }

  // Work a window of this visit still holds comes in with the panel rather than
  // staying beside it as a second draft of the same visit: the panel adopts it
  // and opens dirty on it, so its own Save is the one write.
  String? baseline;
  if (stored != null) {
    final carried = WindowsManager.adoptWork(scope, stored.toJson());
    if (carried != null) {
      editingCopy = Appointment.fromJson(carried);
      // The visit as it is stored: the panel opens dirty on the work it
      // adopted, and clean when there was none.
      baseline = jsonEncode(stored.toJson());
    }
  }
  WindowsManager.closeScope(scope);

  final chart = appointmentDentalChart(
    editingCopy,
    onOpenAppointment: _openAppointmentFromChart,
  );
  late final RowPanel<Appointment> panel;
  panel = RowPanel<Appointment>(
    singularName: "appointment",
    accent: PanelAccents.appointment,
    unicodeSymbol: "📅",
    initialWindow: focus,
    // `editingCopy` answers the post-op question exactly as the stored record
    // does — a new visit has no operator, so only the permission decides.
    item: editingCopy,
    store: appointments,
    icon: WindowsIcons.calendar,
    existing: appointments.get(editingCopy.id) != null,
    // The visit on screen carries work that is not stored yet, so the panel
    // starts with something to save.
    savedBaseline: baseline,
    // A localization key rather than a sentence: the header runs it through
    // txt(), so it follows the language the app is in now. A stored
    // appointment gets its own title from readTitle() instead.
    title: "addAppointment",
    windows: [
      for (final entry in appointmentWindows(editingCopy))
        switch (entry) {
          AppointmentWindow.details => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              body: _AppointmentDetails(editingCopy),
            ),
          AppointmentWindow.dentalChart => dentalChartWindow(chart),
          AppointmentWindow.operative => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              subtitle: entry.ownerFor(editingCopy),
              padding: 6,
              editsRecord: true,
              body: _OperativeDetails(editingCopy),
              footer:
                  operativeVoiceAction(editingCopy, onEdited: chart.changed),
            ),
          AppointmentWindow.labwork => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              subtitle: entry.ownerFor(editingCopy),
              editsRecord: true,
              body: AppointmentLabworkSection(appointment: editingCopy),
            ),
          AppointmentWindow.gallery => PanelWindow(
              id: entry.id,
              title: entry.titleKey,
              icon: entry.icon,
              subtitle: entry.ownerFor(editingCopy),
              // The gallery reads the panel back (its record, its progress
              // flag), so it is built once the panel exists.
              body: Builder(
                  builder: (context) => _AppointmentGallery(editingCopy,
                      onProgress: (value) => panel.inProgress(value),
                      onSaved: panel.markSaved)),
              onlyIfSaved: true,
              padding: 0,
            ),
        },
    ],
  );
  await panel.readTitle();
  PanelsManager.open(panel);
}

/// The post-op dictation button, when the clinic has it on: what is dictated is
/// merged into [editingCopy], and [onEdited] lets the owner redraw.
Widget? operativeVoiceAction(Appointment editingCopy,
    {VoidCallback? onEdited}) {
  if (!network.isOnline() || !globalSettings.aiServicesEnabled) return null;
  return AudioRecorderButton(
    hint: txt("postOperativeVoiceAutoFillHint"),
    label: txt("voiceAutoFill"),
    onRecordingComplete: (bytes, mimeType) async {
      try {
        final existing = PostOpData(
          postOpNotes: editingCopy.postOpNotes,
          prescriptions: editingCopy.prescriptions,
          price: editingCopy.price,
          paid: editingCopy.paid,
          teeth: editingCopy.teeth,
          teethExtraNotes: editingCopy.teethExtraNotes,
          hasLabwork: editingCopy.hasLabwork,
          labName: editingCopy.labName,
          labworkNotes: editingCopy.labworkNotes,
        );
        final result = await PostOpNotes.processAudioBytes(
          bytes,
          mimeType,
          existingFields: existing,
        );
        if (result.postOpNotes.isNotEmpty) {
          editingCopy.postOpNotes = result.postOpNotes;
        }
        if (result.prescriptions.isNotEmpty) {
          editingCopy.prescriptions = result.prescriptions;
        }
        if (result.price != 0) editingCopy.price = result.price;
        if (result.paid != 0) editingCopy.paid = result.paid;
        if (result.teeth.isNotEmpty) editingCopy.teeth.addAll(result.teeth);
        if (result.teethExtraNotes.isNotEmpty) {
          editingCopy.teethExtraNotes.addAll(result.teethExtraNotes);
        }
        editingCopy.hasLabwork = result.hasLabwork;
        if (result.labName.isNotEmpty) editingCopy.labName = result.labName;
        if (result.labworkNotes.isNotEmpty) {
          editingCopy.labworkNotes = result.labworkNotes;
        }
        transcriptionEditCounter(transcriptionEditCounter() + 1);
        onEdited?.call();
      } catch (e, s) {
        showErrorMessage(e, "processingPostOpNotes");
        logger("Error processing post-op notes audio: $e", s);
      }
    },
  );
}

/// A window of [appointment], shown on its own: the edit the caller asked for,
/// not the whole record.
Future<void> _openAppointmentWindow(
  Appointment draft,
  AppointmentWindow window,
) async {
  final scope = 'appointment:${draft.id}';
  var snapshot = jsonEncode(draft.toJson());
  // The visit as this window found it. A window owns the fields the user moves
  // here and nothing else — the chart beside the labwork may save the rest while
  // both are open, and writing the whole draft back would undo that.
  var asOpened = jsonDecode(snapshot) as Map<String, dynamic>;
  bool changed() => jsonEncode(draft.toJson()) != snapshot;
  // Saving a window leaves it clean, exactly as a panel's Save does: without
  // this the next Close would ask about work that has just been written.
  Future<void> save() async {
    await saveAppointmentDraft(draft, asOpened: asOpened);
    snapshot = jsonEncode(draft.toJson());
    // The next save is measured against what is stored now, so a field that was
    // added and then removed again is written back like any other change.
    asOpened = jsonDecode(snapshot) as Map<String, dynamic>;
  }

  switch (window) {
    case AppointmentWindow.details:
      openAppointment(draft);
    case AppointmentWindow.dentalChart:
      await openAppointmentDentalChart(
        draft,
        onOpenAppointment: _openAppointmentFromChart,
        onOpenRecord: () => _openAppointmentPanel(
          draft,
          focus: AppointmentWindow.dentalChart.id,
        ),
      );
    case AppointmentWindow.operative:
      WindowsManager.showStandalone(
        PanelWindow(
          id: window.id,
          title: window.titleKey,
          icon: window.icon,
          subtitle: window.ownerFor(draft),
          padding: 6,
          body: _OperativeDetails(draft),
          footer: operativeVoiceAction(draft),
        ),
        scope: scope,
        onSave: save,
        hasChanges: changed,
        transfer: (stored) =>
            mergeAppointmentJson(draft, asOpened: asOpened, into: stored),
        onOpenRecord: () => _openAppointmentPanel(
          draft,
          focus: AppointmentWindow.operative.id,
        ),
      );
    case AppointmentWindow.labwork:
      WindowsManager.showStandalone(
        PanelWindow(
          id: window.id,
          title: window.titleKey,
          icon: window.icon,
          subtitle: window.ownerFor(draft),
          body: AppointmentLabworkSection(appointment: draft),
        ),
        scope: scope,
        onSave: save,
        hasChanges: changed,
        transfer: (stored) =>
            mergeAppointmentJson(draft, asOpened: asOpened, into: stored),
        onOpenRecord: () => _openAppointmentPanel(
          draft,
          focus: AppointmentWindow.labwork.id,
        ),
      );
    case AppointmentWindow.gallery:
      WindowsManager.showStandalone(
        PanelWindow(
          id: window.id,
          title: window.titleKey,
          icon: window.icon,
          subtitle: window.ownerFor(draft),
          maxHeight: 680,
          // A grid of photos: it needs room for a row or two of them to be worth
          // opening, and scrolls itself beyond that.
          minHeight: 460,
          padding: 0,
          body: _AppointmentGallery(draft),
        ),
        scope: scope,
        onOpenRecord: () => _openAppointmentPanel(
          draft,
          focus: AppointmentWindow.gallery.id,
        ),
      );
  }
}

/// Opens one of [appointment]'s windows on its own — what a labwork table, a
/// patient's history or a gallery tile means when it names a window.
///
/// The same door as [openAppointment], on purpose: a visitor that names a window
/// of a visit whose panel is already open must reach that panel's window, not
/// start a second draft of the visit.
void openAppointmentWindow(Appointment appointment, AppointmentWindow window) {
  openAppointment(appointment, window);
}

Future<void> saveAppointmentDraft(
  Appointment draft, {
  required Map<String, dynamic> asOpened,
}) async {
  final stored = appointments.get(draft.id);
  appointments.set(appointments.modeling(stored == null
      // Nothing to merge with: the visit is not stored yet.
      ? jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>
      : mergeAppointmentJson(draft, asOpened: asOpened, into: stored.toJson())));
}

/// [draft]'s work, written over [into] — the visit as it is stored now.
///
/// Only the fields that differ from [asOpened] are written: another window of
/// the same visit may have saved the rest while this one was open, and writing
/// the whole draft back would undo it. A field back at the model's default is
/// absent from `toJson`, so writing that back means dropping the key.
///
/// The round-trips through JSON are not ceremony: `toJson` hands out the draft's
/// own maps, so the answer is detached from [draft] — it can be stored, or handed
/// to a panel as its item, without the two sharing state.
Map<String, dynamic> mergeAppointmentJson(
  Appointment draft, {
  required Map<String, dynamic> asOpened,
  required Map<String, dynamic> into,
}) {
  final merged = jsonDecode(jsonEncode(into)) as Map<String, dynamic>;
  final current = draft.toJson();
  for (final key in {...asOpened.keys, ...current.keys}) {
    if (jsonEncode(current[key]) == jsonEncode(asOpened[key])) continue;
    if (current.containsKey(key)) {
      merged[key] = current[key];
    } else {
      merged.remove(key);
    }
  }
  return jsonDecode(jsonEncode(merged)) as Map<String, dynamic>;
}

