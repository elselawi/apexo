import 'dart:convert';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/extra_notes_expander.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/features/labwork/open_labwork_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/ai_services/post_op_notes.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
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
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/utils/uuid.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

void closeAppointmentsPanels() {
  List<String> toClose = [];
  for (var panel in routes.panels()) {
    final identifier = panel.identifier;
    if (identifier.contains("appointments") ||
        appointments.get(identifier) != null) {
      toClose.add(identifier);
    }
  }
  for (final identifier in toClose) {
    routes.closePanel(identifier);
  }
}

final transcriptionEditCounter = ObservableState(0);

void openAppointment([Appointment? appointment, int? selectedTabIndex]) {
  closeLabworksPanels();

  final canViewPostOp = login.perm(Perm.postOp).exact(2) ||
      (login.perm(Perm.postOp).exact(1) &&
          appointment?.operatorsIDs.contains(login.currentAccountID) == true);

  if (appointment != null &&
      appointment.isDone &&
      selectedTabIndex == 0 &&
      canViewPostOp) {
    selectedTabIndex = 1;
  }

  final editingCopy = Appointment.fromJson(appointment?.toJson() ?? {});
  final panel = Panel(
    singularName: "appointment",
    unicodeSymbol: "📅",
    selectedTabIndex: selectedTabIndex,
    item: editingCopy,
    store: appointments,
    icon: WindowsIcons.calendar,
    title: appointments.get(editingCopy.id) == null
        ? txt("addAppointment")
        : editingCopy.title,
    tabs: [],
  );
  final tabs = [
    PanelTab(
      title: txt("appointment"),
      icon: WindowsIcons.calendar,
      body: _AppointmentDetails(editingCopy),
    ),
    if (canViewPostOp)
      PanelTab(
        title: txt("operativeDetails"),
        icon: FluentIcons.medical_care,
        body: _OperativeDetails(editingCopy),
        footer: (network.isOnline() && globalSettings.aiServicesEnabled)
            ? AudioRecorderButton(
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
                    if (result.teeth.isNotEmpty) {
                      editingCopy.teeth.addAll(result.teeth);
                    }
                    if (result.teethExtraNotes.isNotEmpty) {
                      editingCopy.teethExtraNotes
                          .addAll(result.teethExtraNotes);
                    }
                    editingCopy.hasLabwork = result.hasLabwork;
                    if (result.labName.isNotEmpty) {
                      editingCopy.labName = result.labName;
                    }
                    if (result.labworkNotes.isNotEmpty) {
                      editingCopy.labworkNotes = result.labworkNotes;
                    }

                    transcriptionEditCounter(transcriptionEditCounter() + 1);
                  } catch (e, s) {
                    showErrorMessage(e, "processingPostOpNotes");
                    logger("Error processing post-op notes audio: $e", s);
                  }
                },
              )
            : null,
      ),
    PanelTab(
      title: txt("gallery"),
      icon: FluentIcons.camera,
      body: _AppointmentGallery(panel),
      onlyIfSaved: true,
      padding: 0,
    ),
  ];
  panel.tabs.addAll(tabs);
  routes.openPanel(panel);
}

class _AppointmentGallery extends StatefulWidget {
  final Panel<Appointment> panel;
  const _AppointmentGallery(this.panel);

  @override
  State<_AppointmentGallery> createState() => _AppointmentGalleryState();
}

class _AppointmentGalleryState extends State<_AppointmentGallery> {
  @override
  Widget build(BuildContext context) {
    // Other appointments surfaced below the current one's gallery: include
    // any appointment that has photos OR DCM X-rays (deduped by id).
    final patient = widget.panel.item.patient;
    final otherImages = <Appointment>[];
    if (patient != null) {
      final seen = <String>{};
      for (final a in [
        ...patient.appointmentsWithImages,
        ...patient.appointmentsWithDcmImgs,
      ]) {
        if (a.id != widget.panel.item.id && seen.add(a.id)) {
          otherImages.add(a);
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildCurrentAppointmentPhotos(),
        if (otherImages.isNotEmpty)
          _OtherAppointmentsPhotos(otherImages: otherImages),
      ],
    );
  }

  StreamBuilder<int> _buildCurrentAppointmentPhotos() {
    return StreamBuilder(
        stream: widget.panel.selectedTab.stream,
        builder: (context, _) {
          return StreamBuilder(
              stream: widget.panel.inProgress.stream,
              builder: (context, snapshot) {
                return GridGallery(
                  onProgress: (inProgress) {
                    setState(() {
                      widget.panel.inProgress(inProgress);
                    });
                  },
                  canDelete: login.perm(Perm.photos).exact(1),
                  rowId: widget.panel.item.id,
                  imgs: widget.panel.item.imgs,
                  dcmImgs: widget.panel.item.dcmImgs,
                  slideshowEnabled: true,
                  drawings: widget.panel.item.drawings,
                  onSaveDrawing: (img, drawing) {
                    widget.panel.item.drawings[img] = drawing;
                    appointments.set(widget.panel.item);
                    widget.panel.savedJson =
                        jsonEncode(widget.panel.item.toJson());
                  },
                  onPressDelete: (img) async {
                    widget.panel.inProgress(true);
                    try {
                      await appointments.deleteImg(widget.panel.item.id, img);
                      widget.panel.item.imgs.remove(img);
                      widget.panel.item.drawings.remove(img);
                      appointments.set(widget.panel.item);
                      widget.panel.savedJson =
                          jsonEncode(widget.panel.item.toJson());
                    } catch (e, s) {
                      showErrorMessage(e, "deletingPatientImageFromServer");
                      login.askForLoginAgain(e);
                      logger("Error during deleting image: $e", s);
                    }
                    widget.panel.inProgress(false);
                    widget.panel.selectedTab(widget.panel.selectedTab());
                  },
                  onPressDeleteDcm: (dcmName) async {
                    widget.panel.inProgress(true);
                    try {
                      await appointments.deleteDcmImg(
                          widget.panel.item.id, dcmName);
                      widget.panel.item.dcmImgs.remove(dcmName);
                      appointments.set(widget.panel.item);
                      widget.panel.savedJson =
                          jsonEncode(widget.panel.item.toJson());
                    } catch (e, s) {
                      showErrorMessage(e, "deletingPatientImageFromServer");
                      login.askForLoginAgain(e);
                      logger("Error during deleting DCM image: $e", s);
                    }
                    widget.panel.inProgress(false);
                    widget.panel.selectedTab(widget.panel.selectedTab());
                  },
                  uploadConfig: GalleryUploadConfig(
                    store: appointments,
                    canUpload: login.perm(Perm.photos).exact(1),
                    modelPersistence: (names) async {
                      widget.panel.item.imgs.addAll(names);
                      widget.panel.item.imgs =
                          widget.panel.item.imgs.toSet().toList();
                      appointments.set(widget.panel.item);
                      widget.panel.savedJson =
                          jsonEncode(widget.panel.item.toJson());
                      if (mounted) {
                        widget.panel.selectedTab(widget.panel.selectedTab());
                      }
                    },
                  ),
                );
              });
        });
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
          return AppointmentCard(
            appointment: otherImages[index],
            number: index + 1,
            readOnly: true,
            showLeftBorder: false,
            showSectionTitle: false,
            photosClipCount: 999,
            openButtonColor: Colors.grey,
            hide: const [
              AppointmentSections.dentalNotes,
              AppointmentSections.doctors,
              AppointmentSections.labworks,
              AppointmentSections.patient,
              AppointmentSections.pay,
              AppointmentSections.postNotes,
              AppointmentSections.preNotes,
              AppointmentSections.prescriptions,
              AppointmentSections.appointmentNumber,
            ],
          );
        })
      ],
    );
  }
}

class _AppointmentDetails extends StatefulWidget {
  final Appointment appointment;
  const _AppointmentDetails(this.appointment);

  @override
  State<_AppointmentDetails> createState() => _AppointmentDetailsState();
}

class _AppointmentDetailsState extends State<_AppointmentDetails> {
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
                        final newPatientId = uuid();
                        final newPatient = await openPatient(
                            Patient.fromJson({"id": newPatientId}));
                        routes.closePanel(newPatientId);
                        widget.appointment.patientID = newPatient.id;
                      })
                else
                  FilledButton(
                    child: ButtonContent(FluentIcons.go, txt("open")),
                    onPressed: () {
                      openPatient(widget.appointment.patient!);
                    },
                  )
              ]),
        ),
        InfoLabel(
          label: "${txt("doctors")}:",
          child: OperatorsPicker(
              value: widget.appointment.operatorsIDs,
              onChanged: (s) {
                widget.appointment.operatorsIDs = s;
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
            onChange: (d) => {
              widget.appointment.date = DateTime(
                widget.appointment.date.year,
                widget.appointment.date.month,
                widget.appointment.date.day,
                d.hour,
                d.minute,
              )
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
            onSet: (d) => widget.appointment.duration = d,
            isCompact: false,
          ),
        ),
        InfoLabel(
          label: "${txt("preOperativeNotes")}:",
          child: LiveTranscribingTextField(
            key: WK.fieldAppointmentPreOpNotes,
            expands: true,
            maxLines: null,
            controller: noteController,
            onChanged: (v) => setState(() => widget.appointment.preOpNotes = v),
            placeholder: "${txt("preOperativeNotes")}...",
          ),
        )
      ].map((e) => [e, const SizedBox(height: 10)]).expand((e) => e).toList(),
    );
  }
}

class _OperativeDetails extends StatefulWidget {
  final Appointment appointment;
  const _OperativeDetails(this.appointment);

  @override
  State<_OperativeDetails> createState() => _OperativeDetailsState();
}

class _OperativeDetailsState extends State<_OperativeDetails> {
  final TextEditingController postOpNotesController = TextEditingController();
  final MoneyEditingController priceController = MoneyEditingController();
  final MoneyEditingController paidController = MoneyEditingController();
  bool didNotEditPaidYet = true;

  void setToDone() {
    setState(() {
      widget.appointment.isDone = true;
    });
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

  void _updateWhenTranscriptionOccurs(_) {
    if (mounted) {
      setState(_fillControllers);
    }
  }

  @override
  void dispose() {
    postOpNotesController.dispose();
    priceController.dispose();
    paidController.dispose();
    transcriptionEditCounter.unObserve(_updateWhenTranscriptionOccurs);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double paymentDifference = 0;
    Patient? patient = widget.appointment.patient;
    if (patient != null) {
      final paymentsMade = patient.doneAppointments
          .where((a) => a.id != widget.appointment.id)
          .fold(0.0, (value, element) => value + element.paid);

      final pricesGiven = patient.doneAppointments
          .where((a) => a.id != widget.appointment.id)
          .fold(0.0, (value, element) => value + element.price);

      paymentDifference = pricesGiven +
          widget.appointment.price -
          paymentsMade -
          widget.appointment.paid;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.appointment.patient != null)
          InfoLabel(
            label: "${txt("dentalNotes")}:",
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: FluentTheme.of(context).shadowColor.withAlpha(50)),
                color: FluentTheme.of(context).menuColor,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                spacing: 10,
                children: [
                  TeethSelector(
                    key: ValueKey(jsonEncode({
                      ...widget.appointment.teeth,
                      ...widget.appointment.teethExtraNotes
                    })),
                    type: StateType.treatment,
                    onNote: (x, y) {
                      if (y != null) {
                        widget.appointment.teeth[x] = y;
                      } else {
                        widget.appointment.teeth.remove(x);
                        widget.appointment.teethExtraNotes.remove(x);
                      }
                    },
                    onExtraNote: (x, extra) {
                      widget.appointment.teethExtraNotes[x] = extra;
                    },
                    extraNotes: widget.appointment.teethExtraNotes,
                    notation: (isoString) => isoToTextualNotation(isoString),
                    rightString: txt("right"),
                    leftString: txt("left"),
                    currentNotes: widget.appointment.teeth,
                    oldNotes: (widget
                            .appointment.patient?.allAppointmentsDentalNotes ??
                        {})
                      ..removeWhere((key, val) =>
                          widget.appointment.teeth.containsKey(key)),
                    showPrimary: (widget.appointment.patient?.age ?? 18) < 14,
                  ),
                  if (widget.appointment.patient?.allAppointmentsDentalNotes
                          .isNotEmpty ==
                      true) ...[
                    AppointmentExtraNotes(
                      patient: widget.appointment.patient!,
                      initiallyExpanded: false,
                      excludedAppointment: widget.appointment,
                      title: txt("otherAppointmentsNotes"),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Column(
          spacing: 5,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InfoLabel(
              label: "${txt("postOperativeNotes")}:",
              child: LiveTranscribingTextField(
                key: WK.fieldAppointmentPostOpNotes,
                controller: postOpNotesController,
                placeholder: "${txt("postOperativeNotes")}...",
                onChanged: (v) {
                  setState(() {
                    widget.appointment.postOpNotes = v;
                    widget.appointment.isDone = true;
                  });
                },
              ),
            ),
            if ((widget.appointment.patient?.allAppointments.length ?? 0) > 1)
              _buildOtherAppointmentsFlyout(context),
          ],
        ),
        InfoLabel(
          label: "${txt("prescription")}:",
          child: TagInputWidget(
            key: WK.fieldAppointmentPrescriptions,
            suggestions: appointments.allPrescriptions
                .map((p) => TagInputItem(value: p, label: p))
                .toList(),
            onChanged: (s) {
              setState(() {
                widget.appointment.prescriptions = s
                    .where((x) => x.value != null)
                    .map((x) => x.value!)
                    .toList();
                widget.appointment.isDone = true;
              });
            },
            initialValue: widget.appointment.prescriptions
                .map((p) => TagInputItem(value: p, label: p))
                .toList(),
            strict: false,
            limit: 999,
            placeholder: "${txt("prescription")}...",
            multiline: true,
          ),
        ),
        if (widget.appointment.prescriptions.isNotEmpty)
          FilledButton(
              style: filledButtonStyle(Colors.grey),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.print),
                  const SizedBox(width: 10),
                  Txt(txt("printPrescription"))
                ],
              ),
              onPressed: () {
                printingPrescription(
                  context,
                  widget.appointment.prescriptions,
                  widget.appointment.patient?.title ?? "",
                  widget.appointment.patient?.age.toString() ?? "",
                  widget.appointment.patient?.link ?? "",
                );
              }),
        const Divider(direction: Axis.horizontal),
        Row(
          children: [
            Expanded(
              child: InfoLabel(
                label: "${txt("priceIn")} ${currency()}",
                child: CupertinoTextField(
                  key: WK.fieldAppointmentPrice,
                  controller: priceController,
                  onChanged: (v) {
                    setState(() {
                      widget.appointment.price = moneyInputFormatter.parse(v);
                      if (didNotEditPaidYet) {
                        widget.appointment.paid = widget.appointment.price;
                        paidController.text = moneyInputFormatter
                            .formatDouble(widget.appointment.paid);
                      }
                      widget.appointment.isDone = true;
                    });
                  },
                  placeholder: txt("price"),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [moneyInputFormatter],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InfoLabel(
                label: "${txt("paidIn")} ${currency()}",
                child: CupertinoTextField(
                  key: WK.fieldAppointmentPayment,
                  controller: paidController,
                  onChanged: (v) {
                    setState(() {
                      didNotEditPaidYet = false;
                      widget.appointment.paid = moneyInputFormatter.parse(v);
                      widget.appointment.isDone = true;
                    });
                  },
                  placeholder: txt("paid"),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [moneyInputFormatter],
                ),
              ),
            ),
          ],
        ),
        if (paymentDifference != 0 &&
            (login.perm(Perm.revenue).read ||
                widget.appointment.userIsOperator))
          InfoBar(
            title: Row(
              spacing: 5,
              children: [
                Txt(txt(paymentDifference > 0
                    ? txt("underpaid")
                    : txt("overpaid"))),
                MoneyDisplay(
                    "${paymentDifference.abs().toStringAsFixed(2)} ${currency()}"),
              ],
            ),
            content: Txt(txt("includesOtherAppointments")),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        const Divider(direction: Axis.horizontal),
        Checkbox(
          checked: widget.appointment.isDone,
          onChanged: (checked) {
            setState(() {
              widget.appointment.isDone = checked == true;
            });
          },
          content: Txt(txt("isDone")),
        ),
        widget.appointment.hasLabwork
            ? _buildLabworkSection()
            : HyperlinkButton(
                style: ButtonStyle(
                    textStyle: WidgetStatePropertyAll(
                        FluentTheme.of(context).typography.caption)),
                onPressed: () {
                  setState(() {
                    widget.appointment.hasLabwork = true;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(FluentIcons.manufacturing),
                    const SizedBox(width: 15),
                    SizedBox(
                        width: 200,
                        child: Txt(txt("addLabwork"), softWrap: true))
                  ],
                ),
              ),
      ].map((e) => [e, const SizedBox(height: 10)]).expand((e) => e).toList(),
    );
  }

  Widget _buildOtherAppointmentsFlyout(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: AppointmentsHistoryFlyout(
        title: txt("otherAppointments"),
        exclude: widget.appointment,
        patient: widget.appointment.patient!,
      ),
    );
  }

  Widget _buildLabworkSection() {
    return LabWorkEditor(
        appointment: widget.appointment,
        onDelete: () {
          setState(() {
            widget.appointment.hasLabwork = false;
          });
        });
  }
}

class AppointmentsHistoryFlyout extends StatefulWidget {
  const AppointmentsHistoryFlyout(
      {super.key, required this.patient, required this.exclude, this.title});

  final Patient patient;
  final Appointment exclude;
  final String? title;

  @override
  State<AppointmentsHistoryFlyout> createState() =>
      _AppointmentsHistoryFlyoutState();
}

class _AppointmentsHistoryFlyoutState extends State<AppointmentsHistoryFlyout> {
  final otherAppointmentsFlyout = FlyoutController();

  @override
  void dispose() {
    otherAppointmentsFlyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: otherAppointmentsFlyout,
      child: Tooltip(
        message: txt("otherAppointments"),
        child: IconButton(
          style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
            FluentTheme.of(context).inactiveColor.withAlpha(30),
          )),
          icon: Row(
            spacing: 10,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(WindowsIcons.history),
              if (widget.title != null) Txt(widget.title!),
            ],
          ),
          onPressed: () async {
            await flyoutFocusFix(context);
            otherAppointmentsFlyout.showFlyout(
              barrierDismissible: true,
              dismissWithEsc: true,
              builder: (context) {
                return FlyoutContent(
                    useAcrylic: false,
                    elevation: 15,
                    padding: EdgeInsetsGeometry.zero,
                    constraints:
                        const BoxConstraints(maxHeight: 300, maxWidth: 340),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                spacing: 5,
                                children: [
                                  Icon(WindowsIcons.history,
                                      size: 16,
                                      color: FluentTheme.of(context)
                                          .typography
                                          .bodyStrong!
                                          .color),
                                  Txt("${txt("otherAppointments")} (${widget.patient.allAppointments.length - 1})",
                                      style: FluentTheme.of(context)
                                          .typography
                                          .bodyStrong),
                                ],
                              ),
                              Text(
                                widget.patient.title,
                                style: const TextStyle(fontSize: 11),
                              )
                            ],
                          ),
                        ),
                        const Divider(),
                        Flexible(
                          child: SingleChildScrollView(
                            child: PatientAppointments(widget.patient,
                                readOnly: true,
                                excludedAppointment: widget.exclude,
                                hide: const [
                                  AppointmentSections.doctors,
                                  AppointmentSections.appointmentNumber,
                                  AppointmentSections.patient,
                                  AppointmentSections.pay,
                                  AppointmentSections.timeDifference,
                                  AppointmentSections.openAppointmentButton,
                                  AppointmentSections.paymentSummary,
                                ]),
                          ),
                        ),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            spacing: 5,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FilledButton(
                                style: filledButtonStyle(Colors.blue),
                                onPressed: () {
                                  Navigator.pop(context);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    openPatient(widget.patient, 2);
                                  });
                                },
                                child: ButtonContent(
                                  WindowsIcons.calendar,
                                  txt("viewAllAppointments"),
                                  size: 13,
                                ),
                              ),
                              FilledButton(
                                style: filledButtonStyle(Colors.grey),
                                onPressed: () => Navigator.pop(context),
                                child: ButtonContent(
                                  WindowsIcons.cancel,
                                  txt("close"),
                                  size: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ));
              },
            );
          },
        ),
      ),
    );
  }
}

class LabWorkEditor extends StatefulWidget {
  final Appointment appointment;
  final VoidCallback? onDelete;
  const LabWorkEditor({super.key, required this.appointment, this.onDelete});
  @override
  State<LabWorkEditor> createState() => _LabWorkEditorState();
}

class _LabWorkEditorState extends State<LabWorkEditor> {
  final labNameController = TextEditingController();
  final labOrderNotesController = TextEditingController();

  @override
  void dispose() {
    labNameController.dispose();
    labOrderNotesController.dispose();
    transcriptionEditCounter.unObserve(_updateWhenTranscriptionOccurs);
    super.dispose();
  }

  void _fillControllers() {
    labNameController.text = widget.appointment.labName;
    labOrderNotesController.text = widget.appointment.labworkNotes;
  }

  void _updateWhenTranscriptionOccurs(_) {
    if (mounted) {
      setState(_fillControllers);
    }
  }

  @override
  void initState() {
    super.initState();
    _fillControllers();
    transcriptionEditCounter.observe(_updateWhenTranscriptionOccurs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final color = widget.appointment.labworkReceived
        ? theme.accentColor
        : Colors.warningPrimaryColor;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: 4),
          bottom: BorderSide(color: color),
          left: BorderSide(color: color),
          right: BorderSide(color: color),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Txt(
                txt("labworks"),
                style: theme.typography.bodyStrong,
              ),
              if (widget.onDelete != null)
                Tooltip(
                  message: txt("delete"),
                  child: IconButton(
                    icon: const Icon(WindowsIcons.delete),
                    onPressed: () {
                      widget.onDelete!();
                    },
                  ),
                )
            ],
          ),
          const SizedBox(height: 5),
          const Divider(),
          const SizedBox(height: 5),
          Row(
            children: [
              Row(
                children: [
                  const Icon(FluentIcons.manufacturing, size: 20),
                  const SizedBox(width: 5),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    child: Txt(
                      txt("laboratory"),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 5),
              Expanded(
                child: AutoSuggestBox<String>(
                  key: WK.fieldLabworkLabName,
                  decoration: WidgetStatePropertyAll(BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.transparent))),
                  clearButtonEnabled: false,
                  placeholder: "${txt("laboratory")}...",
                  noResultsFoundBuilder: (context) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Txt(txt("noSuggestions")),
                  ),
                  onChanged: (text, reason) {
                    widget.appointment.labName = text;
                  },
                  controller: labNameController,
                  items: appointments.labs
                      .map((name) =>
                          AutoSuggestBoxItem<String>(value: name, label: name))
                      .toList(),
                ),
              )
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormBox(
                  prefix: const Icon(WindowsIcons.quick_note),
                  key: WK.fieldLabworkLabName,
                  decoration: WidgetStatePropertyAll(BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.transparent))),
                  placeholder: "${txt("orderNotes")}...",
                  maxLines: null,
                  controller: labOrderNotesController,
                  onChanged: (value) {
                    widget.appointment.labworkNotes = value;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Checkbox(
            checked: widget.appointment.labworkReceived,
            onChanged: (v) =>
                setState(() => widget.appointment.labworkReceived = v ?? false),
            content: Txt(txt("received")),
          ),
        ],
      ),
    );
  }
}
