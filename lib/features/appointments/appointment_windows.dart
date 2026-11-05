import 'dart:async';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/duration_pill.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/operators_picker.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/common_widgets/visits_button.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointment_chart_footer.dart';
import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/follow_up_field.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/appointment_labwork_widgets.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/appointments/appointment_operators_widgets.dart';
import 'package:apexo/features/appointments/appointment_session.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/visit_attachment_chips.dart';
import 'package:apexo/features/appointments/visit_gallery.dart';
import 'package:apexo/features/patients/new_patient_dialog.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/ai_services/post_op_notes.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/money_editing_controller.dart';
import 'package:apexo/utils/money_input_formatter.dart';
import 'package:apexo/utils/print/print_prescription.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// The windows a visit offers, in the order it offers them.
///
/// The visit's session builds its list from [appointmentWindows], the row context
/// menu offers one item per entry, and callers name a window through the enum,
/// so none of them can drift from the others.
enum AppointmentWindow {
  /// The pre-op form: when the visit is, who operates it, and what is planned.
  details('details', "appointment", WindowsIcons.calendar),

  /// The dental chart, beside the pre-op form: the treatments given at this
  /// visit, with the record's own teeth and the other visits beside it as
  /// history.
  dentalChart(kDentalChartWindowId, kTreatmentsTitleKey, FluentIcons.teeth),
  operative('operative', "operativeDetails", FluentIcons.medical_care),
  labwork('labwork', "labwork", FluentIcons.manufacturing),
  gallery('gallery', "gallery", FluentIcons.camera);

  const AppointmentWindow(this.id, this.titleKey, this.icon);

  /// The window's [PanelWindow.id], for panels and openers to name it by.
  final String id;

  /// The window's title key. A side window must answer "which appointment is
  /// this?" on its own: several visits can be open at once, and their labels are
  /// all "Operative details".
  final String titleKey;
  final IconData icon;

  /// Whose window this is: the visit's patient, day and state.
  String Function() ownerFor(Appointment appointment) =>
      () => appointmentOwnerLine(appointment);
}

/// The windows a visit offers [appointment], in the order it offers them.
List<AppointmentWindow> appointmentWindows(Appointment? appointment) => [
      AppointmentWindow.details,
      AppointmentWindow.dentalChart,
      if (canViewPostOp(appointment)) AppointmentWindow.operative,
      AppointmentWindow.labwork,
      AppointmentWindow.gallery,
    ];

/// The window of a visit that is the record's own opening form: what an opener
/// means when it asks for "the visit" rather than for one of its tools.
String get appointmentRecordWindowId => AppointmentWindow.details.id;

/// The windows of [session]'s visit, built once and owned by the session.
///
/// A window says what it is, whose it is and which record its Save writes: the
/// session is that record, and no window names a different one (plan §6.2-6).
///
/// [onOpenRecord] is how a photo's own window leads back to the visit that holds
/// it — null while the visit is already beside its patient, where there is
/// nowhere further to go.
///
/// [attached] says whether these windows are drawn beside the visit's patient. A
/// visit in its patient's panel cannot change patient by being saved — that would
/// re-host a live draft — so its patient line is read-only there (plan §8.2). The
/// same windows standing on their own keep the picker: that is how an orphan gets
/// a patient at all.
List<PanelWindow> appointmentSessionWindows(
  AppointmentSession session, {
  Future<void> Function()? onOpenRecord,
  bool attached = true,
}) {
  final appointment = session.item;
  if (attached) {
    // Beside the patient: the **chart is the visit's window**, the appointment
    // itself is the band's, and everything else hangs off the band as an
    // attachment (the design brief).
    return <PanelWindow>[
      _chartWindow(session, attached: true),
      // The visit's labwork order and photos are attachments, never dock chips:
      // the band is the visit's identity and stays on screen even when the chart
      // is put away, so it is the frame that can offer them — and the post-op
      // card inside the chart draws the same tray again.
      _labworkWindow(session, attachedTo: PanelWindow.bandAttachment),
      _galleryWindow(
        session,
        onOpenRecord: onOpenRecord,
        attachedTo: PanelWindow.bandAttachment,
      ),
    ];
  }
  // On their own — a patient this account may not see, or a visit whose patient
  // is gone: every part keeps a window, because there is no band to hold the
  // appointment and no chart to hang the rest off.
  return <PanelWindow>[
    for (final entry in appointmentWindows(appointment))
      switch (entry) {
        AppointmentWindow.details => PanelWindow(
            id: entry.id,
            title: entry.titleKey,
            icon: entry.icon,
            subtitle: entry.ownerFor(appointment),
            // The pre-op form is wide on purpose: the schedule row, the
            // operators, the notes and the price stop wrapping at 560.
            matchesPanelWidth: false,
            preferredWidth: kAppointmentDetailsWindowWidth,
            minHeight: 440,
            maxHeight: 780,
            editsRecord: true,
            saveLabel: 'saveVisit',
            padding: 8,
            body: AppointmentDetailsForm(
              appointment,
              onEdited: session.refreshDirty,
            ),
          ),
        AppointmentWindow.dentalChart => _chartWindow(session, attached: false),
        AppointmentWindow.operative => PanelWindow(
            id: entry.id,
            title: entry.titleKey,
            icon: entry.icon,
            subtitle: entry.ownerFor(appointment),
            padding: 6,
            minHeight: 420,
            editsRecord: true,
            saveLabel: 'saveVisit',
            body: AppointmentOperativeForm(
              appointment,
              onEdited: session.refreshDirty,
            ),
            // The operative details' own delete, in the window's footer beside
            // its Save and Close — whichever window shows this record.
            footerActions: [
              _DeleteVisitButton(
                key: WK.operativeDeleteVisit,
                session: session,
              ),
            ],
          ),
        AppointmentWindow.labwork => _labworkWindow(session),
        AppointmentWindow.gallery =>
          _galleryWindow(session, onOpenRecord: onOpenRecord),
      },
  ];
}

/// The visit's chart, with the post-op record under it.
///
/// Beside the patient the chart is the visit's **workspace**: the appointment is
/// in the band above, the teeth in the middle, and the post-op record pinned at
/// the foot — one surface, no tabs to hunt through (the design brief).
PanelWindow _chartWindow(
  AppointmentSession session, {
  required bool attached,
}) {
  final appointment = session.item;
  final patient = appointment.patient;
  return dentalChartWindow(
    session.chart,
    saveLabel: 'saveVisit',
    // The chart carries the post-op record when it is the visit's window, so it
    // asks for the room both need; standing on its own it is the chart alone.
    minHeight:
        attached ? kDentalChartWindowMinHeight : kDentalChartBodyMinHeight,
    maxHeight: attached ? kDentalChartWindowMaxHeight : 720,
    overlayFooter: attached,
    footer: AppointmentChartFooter(
      key: ValueKey('chart-footer-${appointment.id}'),
      appointment: appointment,
      session: session.chart,
      attached: attached,
    ),
    actions: attached && patient != null
        ? <Widget>[
            // The patient's whole list of visits, from the chart's own title:
            // reaching the list must not cost the chart its place in the row.
            PatientVisitsButton(
              onPressed: () => unawaited(showPatientVisits(patient.id)),
            ),
          ]
        : const <Widget>[],
    // Where the visit's operative record is shown, its delete is too: beside the
    // patient that record lives under this chart, so this window's footer is the
    // one that carries it — the same action the operative window offers on its
    // own, and the one the band keeps for the visit beside its patient.
    footerActions: [
      _DeleteVisitButton(key: WK.chartDeleteVisit, session: session),
    ],
  );
}

PanelWindow _labworkWindow(AppointmentSession session, {String? attachedTo}) {
  // Shared by the window's body and its footer: the editor starts an order and
  // the footer takes it away, so either end has to see the other's answer.
  final hasOrder = ValueNotifier<bool>(session.item.hasLabwork);
  return PanelWindow(
    attachedTo: attachedTo,
    id: AppointmentWindow.labwork.id,
    title: AppointmentWindow.labwork.titleKey,
    icon: AppointmentWindow.labwork.icon,
    subtitle: AppointmentWindow.labwork.ownerFor(session.item),
    minHeight: 340,
    editsRecord: true,
    saveLabel: 'saveVisit',
    body: AppointmentLabworkSection(
      appointment: session.item,
      hasOrder: hasOrder,
      onEdited: session.refreshDirty,
    ),
    footerActions: [
      _RemoveLabworkButton(
        appointment: session.item,
        hasOrder: hasOrder,
      ),
    ],
    // A chip that only says "Labwork" cannot tell an order from an empty
    // form; the badge says one was written, and whether it came back.
    chipPreview: () => VisitLabworkChipBadge.of(session.item),
  );
}

/// The visit's delete, in the footer of whichever window shows its operative
/// record — beside that window's Save and Close.
///
/// Beside its patient the operative record lives at the foot of the chart, so
/// the chart window carries this; standing on its own the visit has the
/// operative window, which carries it too. Both are the same write.
class _DeleteVisitButton extends StatelessWidget {
  const _DeleteVisitButton({super.key, required this.session});

  final AppointmentSession session;

  @override
  Widget build(BuildContext context) {
    // Archiving a visit takes its clinical record with it: full access to
    // visits, the same rule its context menu keeps.
    if (!session.canArchive) return const SizedBox.shrink();
    final appointment = session.item;
    return DeleteButton(
      restorable: true,
      actionText: 'deleteVisit',
      actionIcon: WindowsIcons.delete,
      preview: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          const Icon(WindowsIcons.calendar),
          Txt("${txt("appointment")} ${DF.commonDate(appointment.date)}"),
        ],
      ),
      onConfirm: () => unawaited(_deleteVisit(session)),
      style: _footerDeleteStyle,
      child: ButtonContent(WindowsIcons.delete, txt('deleteVisit')),
    );
  }
}

/// The labwork window's remove, in its footer beside its Save and Close.
///
/// It is there only while an order is: what it offers is taking the order away,
/// and with no order there is nothing to take.
class _RemoveLabworkButton extends StatelessWidget {
  const _RemoveLabworkButton({
    required this.appointment,
    required this.hasOrder,
  });

  final Appointment appointment;

  /// The same answer the window's body shows, so starting an order there brings
  /// this button out and removing it here puts the body's link back.
  final ValueNotifier<bool> hasOrder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: hasOrder,
      builder: (context, hasLabwork, _) {
        if (!hasLabwork) return const SizedBox.shrink();
        return DeleteButton(
          key: WK.btnRemoveLabwork,
          restorable: false,
          actionText: 'removeLabwork',
          actionIcon: WindowsIcons.delete,
          preview: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              const Icon(FluentIcons.manufacturing),
              Txt("${txt("labwork")}:"),
              Txt(appointment.patient?.title ?? ""),
            ],
          ),
          // The body owns the change: it flips the order off, marks the visit
          // edited, and redraws both ends of the window from the one answer.
          onConfirm: () => hasOrder.value = false,
          style: _footerDeleteStyle,
          child: ButtonContent(WindowsIcons.delete, txt('removeLabwork')),
        );
      },
    );
  }
}

/// A footer delete reads like the Save and Close beside it, in the colour of the
/// action it performs.
final ButtonStyle _footerDeleteStyle = greyButtonStyle.copyWith(
  textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
  backgroundColor: const WidgetStatePropertyAll(Colors.errorPrimaryColor),
  foregroundColor: const WidgetStatePropertyAll(Colors.white),
);

PanelWindow _galleryWindow(
  AppointmentSession session, {
  Future<void> Function()? onOpenRecord,
  String? attachedTo,
}) =>
    PanelWindow(
      attachedTo: attachedTo,
      id: AppointmentWindow.gallery.id,
      title: AppointmentWindow.gallery.titleKey,
      icon: AppointmentWindow.gallery.icon,
      subtitle: AppointmentWindow.gallery.ownerFor(session.item),
      body: AppointmentGalleryPane(
        session.item,
        onProgress: (uploading) => session.inProgress(uploading),
        onFieldsSaved: (fields) => session.markFieldsSaved(fields),
        onOpenRecord: onOpenRecord,
      ),
      onlyIfSaved: true,
      padding: 0,
      // A grid of photos: it needs room for a row or two of them to be worth
      // opening, and scrolls itself beyond that.
      minHeight: 460,
      maxHeight: 680,
      // A camera icon says a gallery exists; two of its pictures say what is in
      // it, which is the question asked before opening it.
      chipPreview: () => VisitGalleryChipPreviews.of(session.item),
    );

/// Deletes the visit [session] edits: archives it, takes it off any panel
/// carrying it, and puts away the windows standing on it.
///
/// A visit deleted from one of its own windows has nothing left to show — the
/// archive is the record's, and the draft it drew goes with the window, the way
/// the band's delete takes the visit off the patient's panel.
Future<void> _deleteVisit(AppointmentSession session) async {
  try {
    await session.setArchived(true);
  } catch (e, s) {
    logger('Deleting "${session.itemId}" failed', s);
    showErrorMessage(e, 'savingFailed');
    return;
  }
  for (final panel in PanelsManager.active().toList()) {
    if (identical(panel.attached, session)) panel.detach();
  }
  for (final floating in WindowsManager.open()
      .where((window) => window.scope == session.scope)
      .toList()) {
    WindowsManager.close(floating);
  }
}

/// The width the pre-op form asks for, when a visit stands on its own. The band
/// replaces it beside a patient; this is what the standalone window still uses.
const double kAppointmentDetailsWindowWidth = 560.0;

/// Says once that a visit is gone — a notification that names a record this
/// device no longer has, or has not synced yet.
///
/// One message, and nothing opens: an editor for a record that is not there
/// would write a new one, under an id nobody chose (plan §4.7).
Future<void> showAppointmentUnavailable() async {
  final BuildContext? context;
  try {
    // The app installs this when its own content is built; a test that only
    // exercises an opener has none, and a record that is gone is not worth
    // failing a test over.
    context = bContext;
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => ContentDialog(
      title: Txt(txt('appointmentUnavailable')),
      actions: [CloseButtonInDialog(buttonText: txt('close'))],
    ),
  );
}

/// The post-op dictation button, when the clinic has it on: what is dictated is
/// merged into [appointment], and [onEdited] lets the owner redraw.
Widget? operativeVoiceAction(Appointment appointment,
    {VoidCallback? onEdited}) {
  if (!network.isOnline() || !globalSettings.aiServicesEnabled) return null;
  return AudioRecorderButton(
    hint: txt("postOperativeVoiceAutoFillHint"),
    label: txt("voiceAutoFill"),
    onRecordingComplete: (bytes, mimeType) async {
      try {
        final existing = PostOpData(
          postOpNotes: appointment.postOpNotes,
          prescriptions: appointment.prescriptions,
          price: appointment.price,
          paid: appointment.paid,
          teeth: appointment.teeth,
          teethExtraNotes: appointment.teethExtraNotes,
          hasLabwork: appointment.hasLabwork,
          labName: appointment.labName,
          labworkNotes: appointment.labworkNotes,
        );
        final result = await PostOpNotes.processAudioBytes(
          bytes,
          mimeType,
          existingFields: existing,
        );
        if (result.postOpNotes.isNotEmpty) {
          appointment.postOpNotes = result.postOpNotes;
        }
        if (result.prescriptions.isNotEmpty) {
          appointment.prescriptions = result.prescriptions;
        }
        if (result.price != 0) appointment.price = result.price;
        if (result.paid != 0) appointment.paid = result.paid;
        if (result.teeth.isNotEmpty) appointment.teeth.addAll(result.teeth);
        if (result.teethExtraNotes.isNotEmpty) {
          appointment.teethExtraNotes.addAll(result.teethExtraNotes);
        }
        appointment.hasLabwork = result.hasLabwork;
        if (result.labName.isNotEmpty) appointment.labName = result.labName;
        if (result.labworkNotes.isNotEmpty) {
          appointment.labworkNotes = result.labworkNotes;
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

/// The visit's gallery and the visit cards beside it.
class AppointmentGalleryPane extends StatelessWidget {
  const AppointmentGalleryPane(
    this.appointment, {
    super.key,
    this.onProgress,
    this.onFieldsSaved,
    this.onOpenRecord,
  });

  final Appointment appointment;

  /// Reports a bulk upload/delete so the visit's session can show it as
  /// progress.
  final ValueChanged<bool>? onProgress;

  /// A write landed outside the visit's own Save, on these fields only, so the
  /// visit's draft is clean on them and still dirty on everything else.
  final void Function(Iterable<String> fields)? onFieldsSaved;

  /// The way back to the visit from one of its photos' own windows.
  final Future<void> Function()? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    // Other visits of the same patient that have pictures, below this visit's:
    // deduped by id, in the order the lists give them.
    final patient = appointment.patient;
    final otherImages = <Appointment>[];
    if (patient != null) {
      final seen = <String>{};
      for (final other in [
        ...patient.appointmentsWithImages,
        ...patient.appointmentsWithDcmImgs,
      ]) {
        if (other.id != appointment.id && seen.add(other.id)) {
          otherImages.add(other);
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        VisitGallery(
          appointment,
          key: ValueKey('visit-gallery-${appointment.id}'),
          // Whose photos these are: a photo window says it.
          owner: () => appointmentOwnerLine(appointment),
          onOpenRecord: onOpenRecord,
          onProgress: onProgress,
          onFieldsSaved: onFieldsSaved,
          uploads: true,
        ),
        if (otherImages.isNotEmpty)
          _OtherAppointmentsPhotos(otherImages: otherImages),
      ],
    );
  }
}

class _OtherAppointmentsPhotos extends StatelessWidget {
  const _OtherAppointmentsPhotos({required this.otherImages});

  final List<Appointment> otherImages;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 10),
        Txt(txt("otherPhotos"),
            style: FluentTheme.of(context)
                .typography
                .bodyStrong!
                .copyWith(fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        ...List.generate(otherImages.length, (index) {
          return VisitPhotosCard(otherImages[index], number: index + 1);
        })
      ],
    );
  }
}

/// The pre-op form as a **window**: when the visit is, who operates it, and what
/// is planned.
///
/// Beside a patient it is not used — the band carries this form, compact, and the
/// patient's name is the panel's own. A visit that stands on its own keeps the
/// window, the patient picker and all, because that is how an orphan gets a
/// patient at all.
class AppointmentDetailsForm extends StatefulWidget {
  const AppointmentDetailsForm(this.appointment, {super.key, this.onEdited});

  final Appointment appointment;

  /// Tells the visit's session that its draft changed (see
  /// [AppointmentOperativeForm.onEdited]).
  final VoidCallback? onEdited;

  @override
  State<AppointmentDetailsForm> createState() => _AppointmentDetailsFormState();
}

class _AppointmentDetailsFormState extends State<AppointmentDetailsForm> {
  final TextEditingController noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    noteController.text = widget.appointment.preOpNotes;
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          /// rebuild needed if a patient is selected/deselected
          key: Key(widget.appointment.patientID ?? ""),
          label: "${txt("patient")}:",
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: PatientPicker(
                    value: widget.appointment.patientID,
                    onChanged: (id) {
                      setState(() {
                        widget.appointment.patientID = id;
                        widget.onEdited?.call();
                      });
                    }),
              ),
              const SizedBox(width: 5),
              if (widget.appointment.patientID == null)
                Button(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: ButtonContent(
                          FluentIcons.add_friend, txt("newPatient")),
                    ),
                    onPressed: () async {
                      // The patient is stored by the sheet, so this visit can
                      // point at a real record without opening one.
                      final patient = await addPatient(context);
                      if (patient == null || !mounted) return;
                      setState(() {
                        widget.appointment.patientID = patient.id;
                        widget.onEdited?.call();
                      });
                    })
              else
                FilledButton(
                  child: ButtonContent(FluentIcons.go, txt("open")),
                  onPressed: () {
                    unawaited(openPatient(widget.appointment.patient!));
                  },
                )
            ],
          ),
        ),
        InfoLabel(
          label: "${txt("doctors")}:",
          child: OperatorsPicker(
              value: widget.appointment.operatorsIDs,
              onChanged: (s) {
                widget.appointment.operatorsIDs = s;
                widget.onEdited?.call();
              }),
        ),
        InfoLabel(
          label: "${txt("date")}:",
          child: DateTimePicker(
            key: WK.fieldAppointmentDate,
            initValue: widget.appointment.date,
            onChange: (d) {
              widget.appointment.date = DateTime(
                d.year,
                d.month,
                d.day,
                widget.appointment.date.hour,
                widget.appointment.date.minute,
              );
              widget.onEdited?.call();
            },
            buttonText: txt("changeDate"),
            buttonIcon: WindowsIcons.calendar,
          ),
        ),
        InfoLabel(
          label: "${txt("time")}:",
          child: DateTimePicker(
            key: WK.fieldAppointmentTime,
            initValue: widget.appointment.date,
            onChange: (d) {
              widget.appointment.date = DateTime(
                widget.appointment.date.year,
                widget.appointment.date.month,
                widget.appointment.date.day,
                d.hour,
                d.minute,
              );
              widget.onEdited?.call();
            },
            buttonText: txt("changeTime"),
            pickTime: true,
            buttonIcon: FluentIcons.clock,
          ),
        ),
        InfoLabel(
          label: "${txt("duration")}:",
          child: DurationPill(
            item: widget.appointment,
            color: Colors.blue,
            onSet: (d) {
              widget.appointment.duration = d;
              widget.onEdited?.call();
            },
            isCompact: false,
          ),
        ),
        InfoLabel(
          label: "${txt("preOperativeNotes")}:",
          child: LiveTranscribingTextField(
            key: WK.fieldAppointmentPreOpNotes,
            expands: false,
            maxLines: 3,
            controller: noteController,
            onChanged: (v) {
              setState(() => widget.appointment.preOpNotes = v);
              widget.onEdited?.call();
            },
            placeholder: "${txt("preOperativeNotes")}...",
          ),
        )
      ].map((e) => [e, const SizedBox(height: 10)]).expand((e) => e).toList(),
    );
  }
}

/// The post-op record, drawn **compact** — it lives at the foot of the visit's
/// chart, under the teeth it describes, not in a window of its own.
///
/// Every field the old operative window had is still here, laid out for the wide
/// chart footer: the notes take three lines, prescriptions and the money take one
/// each, and what is left (a payment difference, the dictation button) fits under
/// them. Typing in it still completes the visit, exactly as it always did — the
/// band says so at once (plan §8.1).
class AppointmentOperativeForm extends StatefulWidget {
  const AppointmentOperativeForm(this.appointment, {super.key, this.onEdited});

  final Appointment appointment;

  /// Tells the visit's session that its draft changed, so the window's Save and
  /// the band's unsaved mark light up while the user types.
  final VoidCallback? onEdited;

  @override
  State<AppointmentOperativeForm> createState() =>
      _AppointmentOperativeFormState();
}

class _AppointmentOperativeFormState extends State<AppointmentOperativeForm> {
  final TextEditingController postOpNotesController = TextEditingController();
  final MoneyEditingController priceController = MoneyEditingController();
  final MoneyEditingController paidController = MoneyEditingController();

  /// The two amounts are typed in one order — the price, then what was taken —
  /// so Tab walks them in that order whatever else is on screen. Focus traversal
  /// otherwise reads the whole scene, and the chart's neighbours (the list of
  /// visits, the windows beside it) put their own fields and buttons between
  /// these two.
  late final FocusNode priceFocus = FocusNode(
    debugLabel: 'appointmentPrice',
    onKeyEvent: (node, event) => _tab(event, withShift: false)
        ? _focusField(paidFocus)
        : KeyEventResult.ignored,
  );
  late final FocusNode paidFocus = FocusNode(
    debugLabel: 'appointmentPaid',
    onKeyEvent: (node, event) => _tab(event, withShift: true)
        ? _focusField(priceFocus)
        : KeyEventResult.ignored,
  );

  bool didNotEditPaidYet = true;

  /// Tab alone, or with nothing but Shift: the walk between the two amounts.
  /// Anything a shortcut or the window manager owns (Ctrl + Tab, Alt + Tab) is
  /// left alone.
  static bool _tab(KeyEvent event, {required bool withShift}) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.tab) return false;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) {
      return false;
    }
    return keys.isShiftPressed == withShift;
  }

  static KeyEventResult _focusField(FocusNode field) {
    field.requestFocus();
    return KeyEventResult.handled;
  }

  void _fillControllers() {
    postOpNotesController.text = widget.appointment.postOpNotes;
    priceController.text =
        moneyInputFormatter.formatDouble(widget.appointment.price);
    paidController.text =
        moneyInputFormatter.formatDouble(widget.appointment.paid);
  }

  @override
  void initState() {
    super.initState();
    _fillControllers();
    if (widget.appointment.paid != 0) didNotEditPaidYet = false;
    transcriptionEditCounter.observe(_updateWhenTranscriptionOccurs);
  }

  @override
  void didUpdateWidget(covariant AppointmentOperativeForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The footer sits under a chart whose scope the user can switch: a new visit
    // is a new post-op record, not the old one with a new chart above it.
    if (!identical(oldWidget.appointment, widget.appointment)) {
      _fillControllers();
      didNotEditPaidYet = widget.appointment.paid == 0;
    }
  }

  void _updateWhenTranscriptionOccurs(_) {
    if (mounted) setState(_fillControllers);
  }

  @override
  void dispose() {
    postOpNotesController.dispose();
    priceController.dispose();
    paidController.dispose();
    priceFocus.dispose();
    paidFocus.dispose();
    transcriptionEditCounter.unObserve(_updateWhenTranscriptionOccurs);
    super.dispose();
  }

  /// The money the patient owes across their finished visits, this one included.
  double get _paymentDifference {
    final patient = widget.appointment.patient;
    if (patient == null) return 0;
    final paymentsMade = patient.doneAppointments
        .where((a) => a.id != widget.appointment.id)
        .fold(0.0, (value, element) => value + element.paid);
    final pricesGiven = patient.doneAppointments
        .where((a) => a.id != widget.appointment.id)
        .fold(0.0, (value, element) => value + element.price);
    return pricesGiven +
        widget.appointment.price -
        paymentsMade -
        widget.appointment.paid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final appointment = widget.appointment;
    final difference = _paymentDifference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // One title row: the section's name, and the controls that act on the
        // record rather than edit one of its fields. On a phone the redundant
        // "is done" caption gives way so the checkbox and the print action can
        // stay; the title itself shrinks before anything overflows.
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(2, 2, 2, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final roomy = constraints.maxWidth >= 480;
              return Row(
                children: [
                  Icon(FluentIcons.medical_care,
                      size: 12, color: theme.inactiveColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Txt(
                      txt('operativeDetails'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.bodyStrong?.copyWith(
                        fontSize: 11,
                        color: theme.typography.body?.color,
                      ),
                    ),
                  ),
                  if (appointment.prescriptions.isNotEmpty)
                    Tooltip(
                      message: txt('printPrescription'),
                      child: IconButton(
                        icon: const Icon(FluentIcons.print, size: 13),
                        onPressed: () {
                          unawaited(printingPrescription(
                            context,
                            appointment.prescriptions,
                            appointment.patient?.title ?? "",
                            appointment.patient?.age.toString() ?? "",
                            appointment.patient?.link ?? "",
                          ));
                        },
                      ),
                    ),
                  Tooltip(
                    message: txt('completed'),
                    child: Checkbox(
                      checked: appointment.isDone,
                      style: CheckboxThemeData(
                        checkedDecoration: WidgetStatePropertyAll(BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(3),
                        )),
                        uncheckedDecoration:
                            WidgetStatePropertyAll(BoxDecoration(
                          border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(3),
                        )),
                      ),
                      onChanged: (checked) => setState(() {
                        appointment.isDone = checked == true;
                        widget.onEdited?.call();
                      }),
                    ),
                  ),
                  if (roomy)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Txt(txt('isDone'),
                          style:
                              theme.typography.caption?.copyWith(fontSize: 10)),
                    ),
                ],
              );
            },
          ),
        ),
        // The two free-text parts of the record — what was done and what was
        // prescribed — share one row when the chart has the room for both, and
        // each takes its own line on a phone. A 960-pixel chart wastes half its
        // width on two short stacked fields; a 390-pixel sheet would crush both
        // into one unreadable line.
        LayoutBuilder(
          builder: (context, constraints) {
            final notes = LiveTranscribingTextField(
              key: WK.fieldAppointmentPostOpNotes,
              controller: postOpNotesController,
              expands: false,
              maxLines: 3,
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
              placeholder: "${txt("postOperativeNotes")}...",
              onChanged: (v) => setState(() {
                appointment.postOpNotes = v;
                appointment.isDone = true;
                widget.onEdited?.call();
              }),
            );
            final prescriptions = TagInputWidget(
              key: WK.fieldAppointmentPrescriptions,
              suggestions: appointments.allPrescriptions
                  .map((p) => TagInputItem(value: p, label: p))
                  .toList(),
              onChanged: (s) => setState(() {
                appointment.prescriptions = s
                    .where((x) => x.value != null)
                    .map((x) => x.value!)
                    .toList();
                appointment.isDone = true;
                widget.onEdited?.call();
              }),
              initialValue: appointment.prescriptions
                  .map((p) => TagInputItem(value: p, label: p))
                  .toList(),
              strict: false,
              limit: 999,
              placeholder: "${txt("prescription")}...",
              multiline: true,
            );
            if (constraints.maxWidth < 620) {
              return Column(
                children: [
                  notes,
                  const SizedBox(height: 4),
                  prescriptions,
                  const SizedBox(height: 4),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: notes),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: prescriptions),
                ],
              ),
            );
          },
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final price = _moneyField(
              fieldKey: WK.fieldAppointmentPrice,
              focusNode: priceFocus,
              controller: priceController,
              label: txt('price'),
              placeholder: txt('price'),
              onChanged: (v) => setState(() {
                appointment.price = moneyInputFormatter.parse(v);
                if (didNotEditPaidYet) {
                  appointment.paid = appointment.price;
                  paidController.text =
                      moneyInputFormatter.formatDouble(appointment.paid);
                }
                appointment.isDone = true;
                widget.onEdited?.call();
              }),
            );
            final paid = _moneyField(
              fieldKey: WK.fieldAppointmentPayment,
              focusNode: paidFocus,
              controller: paidController,
              label: txt('paid'),
              placeholder: txt('paid'),
              onChanged: (v) => setState(() {
                didNotEditPaidYet = false;
                appointment.paid = moneyInputFormatter.parse(v);
                appointment.isDone = true;
                widget.onEdited?.call();
              }),
            );
            final showsDifference = difference != 0 &&
                (login.perm(Perm.revenue).read || appointment.userIsOperator);
            final differenceIndicator = !showsDifference
                ? null
                : Tooltip(
                    message: txt('includesOtherAppointments'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.warning,
                            size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Txt(
                          txt(difference > 0 ? 'underpaid' : 'overpaid'),
                          style: TextStyle(fontSize: 10, color: Colors.orange),
                        ),
                        const SizedBox(width: 4),
                        MoneyDisplay(
                          "${difference.abs().toStringAsFixed(2)} ${currency()}",
                        ),
                      ],
                    ),
                  );
            if (constraints.maxWidth < 480) {
              // A phone gives the two money fields their row and the payment
              // difference the line under it, instead of squeezing three things
              // into one.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: price),
                      const SizedBox(width: 6),
                      Expanded(child: paid),
                    ],
                  ),
                  if (differenceIndicator != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 4),
                      child: differenceIndicator,
                    ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: price),
                const SizedBox(width: 6),
                Expanded(child: paid),
                if (differenceIndicator != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: differenceIndicator,
                  ),
              ],
            );
          },
        ),
        // The record looks forward as well as back: the day the patient is
        // expected again is part of what this visit decided, so it is written
        // down beside the notes that decided it. It is the *patient's* promise —
        // the visit only sets it — and "in two weeks" counts from this visit.
        // A clinic that does not use follow-ups never sees the row.
        if ((appointment.patientID ?? '').isNotEmpty)
          MStreamBuilder<Object?>(
            streams: [globalSettings.observableMap.stream],
            builder: (context, _) {
              if (!followUpsEnabled) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: FollowUpField(
                  patientID: appointment.patientID!,
                  anchor: appointment.date,
                  onChanged: widget.onEdited,
                ),
              );
            },
          ),
        // Dictation is offered only while it can work: the setting is on and
        // there is a network to send the audio over. Both are live, so the
        // button leaves the moment either does.
        MStreamBuilder<Object?>(
          streams: [
            network.isOnline.stream,
            globalSettings.observableMap.stream,
          ],
          builder: (context, _) {
            final voice = operativeVoiceAction(appointment,
                onEdited: widget.onEdited);
            if (voice == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: voice,
            );
          },
        ),
      ],
    );
  }

  /// One money field: a small label inside the field, so two of them fit the
  /// width a 960-pixel chart has without a label line each.
  Widget _moneyField({
    required Key fieldKey,
    required FocusNode focusNode,
    required TextEditingController controller,
    required String label,
    required String placeholder,
    required ValueChanged<String> onChanged,
  }) {
    final theme = FluentTheme.of(context);
    return CupertinoTextField(
      key: fieldKey,
      focusNode: focusNode,
      controller: controller,
      onChanged: onChanged,
      placeholder: placeholder,
      prefix: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
        child: Txt(
          label,
          style: theme.typography.caption?.copyWith(
            color: theme.inactiveColor,
          ),
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [moneyInputFormatter],
    );
  }
}

/// The visit's appointment form, drawn **inside the band** the patient panel
/// gives it.
///
/// When, how long, whose and what was planned are the questions the old pre-op
/// window answered; they are four compact fields — when and how long on one
/// row, whose on the next — and a notes box, so the visit does not need a
/// window, a row slot, or a click to answer them. Every field's glyph lives
/// inside its own box, so the band's rows all start on one edge.
///
/// The patient is deliberately absent: the band sits inside the patient's own
/// panel, which names them two centimetres above. A visit that stands on its own
/// still gets the full form, patient picker and all (`AppointmentDetailsForm`).
class AppointmentBandDetails extends StatefulWidget {
  const AppointmentBandDetails(this.appointment, {super.key, this.onEdited});

  final Appointment appointment;

  /// Tells the visit's session that its draft changed (see
  /// [AppointmentOperativeForm.onEdited]).
  final VoidCallback? onEdited;

  @override
  State<AppointmentBandDetails> createState() => _AppointmentBandDetailsState();
}

class _AppointmentBandDetailsState extends State<AppointmentBandDetails> {
  late final TextEditingController _notes =
      TextEditingController(text: widget.appointment.preOpNotes);

  @override
  void initState() {
    super.initState();
    transcriptionEditCounter.observe(_readAgain);
  }

  @override
  void didUpdateWidget(covariant AppointmentBandDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different visit behind the same band is a different form, not the same
    // one with a new title. The note field is the one piece of state the band
    // owns, so it follows the appointment it is given.
    if (!identical(oldWidget.appointment, widget.appointment)) {
      _notes.text = widget.appointment.preOpNotes;
    }
  }

  @override
  void dispose() {
    transcriptionEditCounter.unObserve(_readAgain);
    _notes.dispose();
    super.dispose();
  }

  /// Dictation filled the draft: re-read what it wrote.
  void _readAgain(_) {
    if (mounted) setState(() => _notes.text = widget.appointment.preOpNotes);
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // When and how long, on one row at every width: the date, the time and
        // the duration keep their places instead of reflowing as the band
        // narrows. The date takes whatever the other two leave, so a date that
        // fits is never ellipsized for want of width the row has to spare.
        Row(
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: _field(
                  tooltip: txt('date'),
                  child: DateTimePicker(
                    key: WK.fieldAppointmentDate,
                    initValue: appointment.date,
                    showButton: false,
                    textAlignment: AlignmentDirectional.centerStart,
                    textStyle: const TextStyle(fontSize: 11),
                    onChange: (d) => setState(() {
                      appointment.date = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        appointment.date.hour,
                        appointment.date.minute,
                      );
                      widget.onEdited?.call();
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _field(
              tooltip: txt('time'),
              width: 78,
              child: DateTimePicker(
                key: WK.fieldAppointmentTime,
                initValue: appointment.date,
                showButton: false,
                pickTime: true,
                textAlignment: AlignmentDirectional.centerStart,
                textStyle: const TextStyle(fontSize: 11),
                onChange: (d) => setState(() {
                  appointment.date = DateTime(
                    appointment.date.year,
                    appointment.date.month,
                    appointment.date.day,
                    d.hour,
                    d.minute,
                  );
                  widget.onEdited?.call();
                }),
              ),
            ),
            const SizedBox(width: 6),
            _field(
              tooltip: txt('duration'),
              child: DurationPill(
                item: appointment,
                color: Colors.blue,
                isCompact: true,
                onSet: (duration) {
                  appointment.duration = duration;
                  widget.onEdited?.call();
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Whose: a line of its own at every width, so the row above never
        // changes shape with the panel.
        _field(
          tooltip: txt('doctors'),
          child: _CompactOperators(
            appointmentId: appointment.id,
            onChanged: () => setState(() {}),
          ),
        ),
        const SizedBox(height: 4),
        LiveTranscribingTextField(
          key: WK.fieldAppointmentPreOpNotes,
          controller: _notes,
          expands: false,
          maxLines: 3,
          // The band is already dense, and the visit keeps its dictation in the
          // chart's post-op record: no mic button under this box.
          micPlacement: MicPlacement.none,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
          style: const TextStyle(fontSize: 11),
          placeholder: "${txt("preOperativeNotes")}...",
          onChanged: (v) {
            setState(() => appointment.preOpNotes = v);
            widget.onEdited?.call();
          },
        ),
      ],
    );
  }

  /// A field with a tooltip: the band has no room for a label line above each
  /// control, so the control names itself and the tooltip says it again on
  /// hover. A [width] pins a field that shares its row; a field without one
  /// takes the width its row gives it.
  ///
  /// Every field's glyph lives **inside** its own box — the calendar and the
  /// clock `commonDate` and `time` already carry, the duration's timer, the
  /// operators' medical — so the boxes all start at the band's edge together.
  Widget _field({
    required String tooltip,
    required Widget child,
    double? width,
  }) {
    return Tooltip(
      message: tooltip,
      child: width == null ? child : SizedBox(width: width, child: child),
    );
  }
}

/// The visit's one tool as a dock **inside its band**: operative details.
///
/// The operative record is not a window of its own any more: it lives at the foot
/// of the visit's chart, and this button opens that chart, where the fields are.
/// The band is the visit's permanent surface, so it is the one control that can
/// promise the record is a click away whatever the row is showing (the design
/// brief).
///
/// The visit's other editors — its labwork order and its photos — are not tools
/// in this dock: they are **attachments**, drawn as a tray at the band's foot and
/// again on the post-op card inside the chart, exactly as a patient's photos hang
/// off the patient's panel (`PanelWindow.bandAttachment`).
class AppointmentBandDock extends StatelessWidget {
  const AppointmentBandDock({super.key, required this.session});

  final AppointmentSession session;

  /// The panel carrying this session, if one is. The band is only drawn by that
  /// panel, so this is the surface the button acts on.
  Panel? get _panel => PanelsManager.active()
      .where((panel) => identical(panel.attached, session))
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final panel = _panel;
    if (panel == null || !canViewPostOp(session.item)) {
      return const SizedBox.shrink();
    }
    return Padding(
      // No side inset of its own: the band already pads its content, and the
      // band's one button starts on the same edge as the fields above it.
      padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 0, 1),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: _BandWindowChip(
          key: WK.visitBandWindow(AppointmentWindow.operative.id),
          icon: AppointmentWindow.operative.icon,
          label: txt(AppointmentWindow.operative.titleKey),
          open: panel.workspace.isOpen(
            kDentalChartWindowId,
            slot: kAttachedSlot,
          ),
          onPressed: () =>
              panel.workspace.show(kDentalChartWindowId, slot: kAttachedSlot),
        ),
      ),
    );
  }
}

/// One tool in the band's dock: its glyph, its name, and whether its surface is
/// already on screen.
class _BandWindowChip extends StatelessWidget {
  const _BandWindowChip({
    super.key,
    required this.icon,
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12),
        const SizedBox(width: 5),
        // One chip is as wide as its word, never wider than the band: a
        // language that spells "operative details" at length must wrap the
        // tray, not overflow the bubble.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Txt(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return Tooltip(
      message: label,
      child: open
          ? FilledButton(onPressed: onPressed, child: content)
          : Button(onPressed: onPressed, child: content),
    );
  }
}

/// The operators of a visit as one compact chip: who is on it, and a flyout to
/// change that without unfolding a full tag editor in a 350-pixel band.
///
/// The flyout itself is the calendar's — [AppointmentOperatorsFlyout] — so an
/// operator is ticked the same way here and in the timeline.
///
/// The same permission rule as the full `OperatorsPicker`: an account that may
/// only see its own visits reads the names, and cannot re-cast them.
class _CompactOperators extends StatefulWidget {
  const _CompactOperators({required this.appointmentId, this.onChanged});

  final String appointmentId;

  /// Called after a tick, so the visit's own forms — the band's draft, its
  /// dirty state — can settle around the write that just landed.
  final VoidCallback? onChanged;

  @override
  State<_CompactOperators> createState() => _CompactOperatorsState();
}

class _CompactOperatorsState extends State<_CompactOperators> {
  final FlyoutController _flyout = FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  bool get _readOnly =>
      login.perm(Perm.appointments).exact(1) ||
      login.perm(Perm.patients).exact(1);

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // The live visit, not the copy this band was built with: a tick in the
    // flyout writes the draft and the store, and the chip has to name who is
    // on the visit the moment the box is ticked.
    final names = (liveAppointment(widget.appointmentId)?.operatorsIDs ??
            const <String>[])
        .map(accounts.nameOrEmailFromID)
        .toList();
    // The operators have a line of their own in the band, so they are named in
    // full: truncating a clinician to their first name is not a space saving, it
    // is a different person. Only a name wider than the line is ellipsized.
    final label = names.isEmpty ? txt('selectDoctors') : names.join(', ');
    return FlyoutTarget(
      controller: _flyout,
      child: HoverButton(
        key: WK.fieldOperators,
        onPressed: _readOnly
            ? null
            : () => unawaited(_flyout.showFlyout<void>(
                  builder: (context) => AppointmentOperatorsFlyout(
                    appointmentId: widget.appointmentId,
                    onChanged: () {
                      setState(() {});
                      widget.onChanged?.call();
                    },
                  ),
                )),
        builder: (context, states) => Container(
          // The band's width, not a clipped 150 pixels: the band has the room,
          // and a second operator must not become an ellipsis after the first.
          padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 2),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).menuColor,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(5),
          ),
          // As tall as the date and the time beside it — the pickers put a
          // 34-pixel content line in the same 2-pixel padding — so the band's
          // fields read as one set rather than as boxes of three heights.
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                // The glyph sits inside the box, where the date's calendar, the
                // time's clock and the duration's timer sit: a glyph outside
                // would push this box off the edge the others start at.
                Icon(FluentIcons.medical, size: 12, color: theme.inactiveColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Txt(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      fontSize: 11,
                      color: names.isEmpty ? theme.inactiveColor : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
