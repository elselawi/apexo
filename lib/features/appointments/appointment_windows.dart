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
enum AppointmentWindow {
  /// The pre-op form: when the visit is, who operates it, and what is planned.
  details('details', "appointment", WindowsIcons.calendar),

  dentalChart(kDentalChartWindowId, kTreatmentsTitleKey, FluentIcons.teeth),
  operative('operative', "operativeDetails", FluentIcons.medical_care),
  labwork('labwork', "labwork", FluentIcons.manufacturing),
  gallery('gallery', "gallery", FluentIcons.camera);

  const AppointmentWindow(this.id, this.titleKey, this.icon);

  /// The window's [PanelWindow.id], for panels and openers to name it by.
  final String id;

  /// The window's title key: several visits can be open at once, so a side
  /// window must say which one it is.
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

/// The window an opener means by "the visit", as opposed to one of its tools.
String get appointmentRecordWindowId => AppointmentWindow.details.id;

/// The windows of [session]'s visit, built once and owned by the session.
/// `attached` windows are drawn beside the patient and must not change patient
/// on save (that would re-host a live draft); standalone windows keep the picker.
List<PanelWindow> appointmentSessionWindows(
  AppointmentSession session, {
  Future<void> Function()? onOpenRecord,
  bool attached = true,
}) {
  final appointment = session.item;
  if (attached) {
    return <PanelWindow>[
      _chartWindow(session, attached: true),
      // Photos and labwork are band attachments: the band outlives the chart and
      // is the frame that can offer them.
      _labworkWindow(session, attachedTo: PanelWindow.bandAttachment),
      _galleryWindow(
        session,
        onOpenRecord: onOpenRecord,
        attachedTo: PanelWindow.bandAttachment,
      ),
    ];
  }
  // Standalone (patient hidden or gone) every part keeps a window: no band to
  // hold the appointment and no chart to hang the rest off.
  return <PanelWindow>[
    for (final entry in appointmentWindows(appointment))
      switch (entry) {
        AppointmentWindow.details => PanelWindow(
            id: entry.id,
            title: entry.titleKey,
            icon: entry.icon,
            subtitle: entry.ownerFor(appointment),
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
              followUpDraft: session.followUpDraft,
              onEdited: session.refreshDirty,
            ),
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
PanelWindow _chartWindow(
  AppointmentSession session, {
  required bool attached,
}) {
  final appointment = session.item;
  final patient = appointment.patient;
  return dentalChartWindow(
    session.chart,
    saveLabel: 'saveVisit',
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
            PatientVisitsButton(
              onPressed: () => unawaited(showPatientVisits(patient.id)),
            ),
          ]
        : const <Widget>[],
    footerActions: [
      _DeleteVisitButton(key: WK.chartDeleteVisit, session: session),
    ],
  );
}

PanelWindow _labworkWindow(AppointmentSession session, {String? attachedTo}) {
  // Shared by the body and footer: either end must see the other's order state.
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
    chipPreview: () => VisitLabworkChipBadge.of(session.item),
  );
}

/// The visit's delete, carried by whichever window shows its operative record —
/// beside the patient the chart, standalone the operative window.
class _DeleteVisitButton extends StatelessWidget {
  const _DeleteVisitButton({super.key, required this.session});

  final AppointmentSession session;

  @override
  Widget build(BuildContext context) {
    // Archiving takes the visit's clinical record with it, so it needs full
    // visits access — same rule as the band's delete.
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

/// The labwork window's remove, shown only while there is an order to remove.
class _RemoveLabworkButton extends StatelessWidget {
  const _RemoveLabworkButton({
    required this.appointment,
    required this.hasOrder,
  });

  final Appointment appointment;

  /// The window body's order state, shared so both ends redraw together.
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
          // The body owns the change; this only flips the shared order state.
          onConfirm: () => hasOrder.value = false,
          style: _footerDeleteStyle,
          child: ButtonContent(WindowsIcons.delete, txt('removeLabwork')),
        );
      },
    );
  }
}

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
      minHeight: 460,
      maxHeight: 680,
      chipPreview: () => VisitGalleryChipPreviews.of(session.item),
    );

/// Archives the visit and closes its panels and windows: deleted from one of its
/// own windows, the draft it drew has nothing left to show.
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

const double kAppointmentDetailsWindowWidth = 560.0;

/// Says once that a visit is gone. Nothing opens: an editor for a missing record
/// would write a new one under an id nobody chose.
Future<void> showAppointmentUnavailable() async {
  final BuildContext? context;
  try {
    // bContext is set only once the app's content is built; tests that exercise
    // an opener have none.
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

/// Post-op dictation button; what is dictated is merged into [appointment].
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

  /// Reports a bulk upload/delete so the session can show it as progress.
  final ValueChanged<bool>? onProgress;

  /// A write landed outside the visit's Save on these fields only, so the draft
  /// is clean on them and still dirty elsewhere.
  final void Function(Iterable<String> fields)? onFieldsSaved;

  /// The way back to the visit from one of its photos' own windows.
  final Future<void> Function()? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    // Other visits of this patient with pictures, deduped by id in list order.
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

/// The pre-op form as a standalone window, patient picker included: beside a
/// patient the band carries the form, so this is how an orphan gets one.
class AppointmentDetailsForm extends StatefulWidget {
  const AppointmentDetailsForm(this.appointment, {super.key, this.onEdited});

  final Appointment appointment;

  /// Tells the session its draft changed (see [AppointmentOperativeForm.onEdited]).
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
                      // The sheet stores the patient, so this visit can point at
                      // it without opening a window.
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

/// The post-op record, drawn compact at the foot of the visit's chart.
class AppointmentOperativeForm extends StatefulWidget {
  const AppointmentOperativeForm(
    this.appointment, {
    super.key,
    this.followUpDraft,
    this.onEdited,
  });

  final Appointment appointment;

  /// The visit session's patient-owned follow-up draft.
  final FollowUpDraft? followUpDraft;

  /// Tells the session its draft changed, so Save and the band's unsaved mark
  /// update while the user types.
  final VoidCallback? onEdited;

  @override
  State<AppointmentOperativeForm> createState() =>
      _AppointmentOperativeFormState();
}

class _AppointmentOperativeFormState extends State<AppointmentOperativeForm> {
  final TextEditingController postOpNotesController = TextEditingController();
  final MoneyEditingController priceController = MoneyEditingController();
  final MoneyEditingController paidController = MoneyEditingController();

  /// Tab walks price → paid whatever else is on screen: default focus traversal
  /// reads the whole scene, and the chart's neighbours sit between the two.
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

  /// Tab alone or with Shift only: Ctrl/Alt/Meta + Tab belong to shortcuts and
  /// the window manager.
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
    // A new visit behind the same footer is a new post-op record, not the old one.
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
        // The follow-up is the patient's promise, not the visit's: the visit only
        // sets it, and "in two weeks" counts from this visit's date.
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
                  draft: widget.followUpDraft,
                  onChanged: widget.onEdited,
                ),
              );
            },
          ),
        // Dictation needs both the AI setting and a network, and both are live.
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

/// The pre-op form drawn inside the band. The patient is absent on purpose: the
/// band already sits in the patient's own panel.
class AppointmentBandDetails extends StatefulWidget {
  const AppointmentBandDetails(this.appointment, {super.key, this.onEdited});

  final Appointment appointment;

  /// Tells the session its draft changed (see [AppointmentOperativeForm.onEdited]).
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
    // A different visit behind the same band is a different form: the note field
    // follows the appointment it is given.
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
          // Dictation lives in the chart's post-op record, so no mic here.
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

/// The band's operative-details button. The record lives at the foot of the
/// visit's chart, so this opens the chart rather than a window of its own.
class AppointmentBandDock extends StatelessWidget {
  const AppointmentBandDock({super.key, required this.session});

  final AppointmentSession session;

  /// The panel carrying this session; the band is only drawn by that panel.
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
        // Capped so a long translation ellipsizes instead of overflowing the band.
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

/// The visit's operators as one chip, using the calendar's flyout. Same
/// permission rule as `OperatorsPicker`: an account that may only see its own
/// visits reads the names but cannot re-cast them.
class _CompactOperators extends StatefulWidget {
  const _CompactOperators({required this.appointmentId, this.onChanged});

  final String appointmentId;

  /// Called after a tick so the band's draft and dirty state follow the write.
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
    // The live visit, not the copy the band was built with: a tick in the flyout
    // writes both draft and store, so the chip must read the live record.
    final names = (liveAppointment(widget.appointmentId)?.operatorsIDs ??
            const <String>[])
        .map(accounts.nameOrEmailFromID)
        .toList();
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
          padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 2),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).menuColor,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(5),
          ),
          // 34px matches the date/time pickers' content line beside it, so the
          // band's fields read as one set.
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
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
