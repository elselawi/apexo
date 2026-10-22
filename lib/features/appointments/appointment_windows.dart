part of 'open_appointment_panel.dart';

class _AppointmentGallery extends StatefulWidget {
  const _AppointmentGallery(
    this.appointment, {
    this.onProgress,
    this.onSaved,
  });

  final Appointment appointment;

  /// Reports a bulk upload/delete so a panel can show it as progress.
  final ValueChanged<bool>? onProgress;

  /// A write landed outside the panel's own Save, so its draft is clean.
  final VoidCallback? onSaved;

  @override
  State<_AppointmentGallery> createState() => _AppointmentGalleryState();
}

class _AppointmentGalleryState extends State<_AppointmentGallery> {
  @override
  Widget build(BuildContext context) {
    // Other appointments surfaced below the current one's gallery: include
    // any appointment that has photos OR DCM X-rays (deduped by id).
    final patient = widget.appointment.patient;
    final otherImages = <Appointment>[];
    if (patient != null) {
      final seen = <String>{};
      for (final a in [
        ...patient.appointmentsWithImages,
        ...patient.appointmentsWithDcmImgs,
      ]) {
        if (a.id != widget.appointment.id && seen.add(a.id)) {
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

  Widget _buildCurrentAppointmentPhotos() {
    return GridGallery(
      onProgress: (inProgress) {
        // The gallery lives in a window that outlives the panel, so it may
        // still be reporting progress after this row is gone.
        if (!mounted) return;
        setState(() {
          widget.onProgress?.call(inProgress);
        });
      },
      canDelete: login.perm(Perm.photos).exact(1),
      rowId: widget.appointment.id,
      // Whose photos these are: a photo window says it.
      owner: () => appointmentOwnerLine(widget.appointment),
      onOpenRecord: () async => openAppointment(widget.appointment),
      imgs: widget.appointment.imgs,
      dcmImgs: widget.appointment.dcmImgs,
      onTapDcm: (context, rowId, name) => openDicomViewerWindow(rowId, name),
      slideshowEnabled: true,
      drawings: widget.appointment.drawings,
      onSaveDrawing: (img, drawing) {
        widget.appointment.drawings[img] = drawing;
        appointments.set(widget.appointment);
        widget.onSaved?.call();
      },
      onPressDelete: (img) async {
        widget.onProgress?.call(true);
        try {
          await appointments.deleteImg(widget.appointment.id, img);
          widget.appointment.imgs.remove(img);
          widget.appointment.drawings.remove(img);
          appointments.set(widget.appointment);
          widget.onSaved?.call();
        } catch (e, s) {
          showErrorMessage(e, "deletingPatientImageFromServer");
          login.askForLoginAgain(e);
          logger("Error during deleting image: $e", s);
        }
        widget.onProgress?.call(false);
        if (mounted) setState(() {});
      },
      onPressDeleteDcm: (dcmName) async {
        widget.onProgress?.call(true);
        try {
          await appointments.deleteDcmImg(widget.appointment.id, dcmName);
          widget.appointment.dcmImgs.remove(dcmName);
          appointments.set(widget.appointment);
          widget.onSaved?.call();
        } catch (e, s) {
          showErrorMessage(e, "deletingPatientImageFromServer");
          login.askForLoginAgain(e);
          logger("Error during deleting DCM image: $e", s);
        }
        widget.onProgress?.call(false);
        if (mounted) setState(() {});
      },
      uploadConfig: GalleryUploadConfig(
        store: appointments,
        canUpload: login.perm(Perm.photos).exact(1),
        modelPersistence: (names) async {
          widget.appointment.imgs.addAll(names);
          widget.appointment.imgs = widget.appointment.imgs.toSet().toList();
          appointments.set(widget.appointment);
          widget.onSaved?.call();
          if (mounted) setState(() {});
        },
      ),
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
          return AppointmentCard(
            appointment: otherImages[index],
            number: index + 1,
            onTapDcm: (context, rowId, name) =>
                openDicomViewerWindow(rowId, name),
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
  const _AppointmentDetails(this.appointment);
  final Appointment appointment;

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
                        // The panel is seeded with the id we want, so a save
                        // writes that id and a cancel leaves it unused — the
                        // appointment points at it either way.
                        final savedPatientId = await openPatient(
                            Patient.fromJson({"id": newPatientId}));
                        PanelsManager.close(newPatientId);
                        widget.appointment.patientID =
                            savedPatientId ?? newPatientId;
                      })
                else
                  FilledButton(
                    child: ButtonContent(FluentIcons.go, txt("open")),
                    onPressed: () {
                      unawaited(openPatient(widget.appointment.patient!));
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
  const _OperativeDetails(this.appointment);
  final Appointment appointment;

  @override
  State<_OperativeDetails> createState() => _OperativeDetailsState();
}

class _OperativeDetailsState extends State<_OperativeDetails> {
  final TextEditingController postOpNotesController = TextEditingController();
  final MoneyEditingController priceController = MoneyEditingController();
  final MoneyEditingController paidController = MoneyEditingController();
  bool didNotEditPaidYet = true;

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
    final Patient? patient = widget.appointment.patient;
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                unawaited(printingPrescription(
                  context,
                  widget.appointment.prescriptions,
                  widget.appointment.patient?.title ?? "",
                  widget.appointment.patient?.age.toString() ?? "",
                  widget.appointment.patient?.link ?? "",
                ));
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
}
