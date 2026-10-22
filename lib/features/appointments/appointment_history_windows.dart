part of 'open_appointment_panel.dart';

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
            unawaited(otherAppointmentsFlyout.showFlyout(
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
                              // Both sides are intrinsic-width: a long patient
                              // name plus the heading measured wider than the
                              // flyout's 340px cap and reported "A RenderFlex
                              // overflowed by 18 pixels on the right". Flexible
                              // on both, and each labels itself with an ellipsis
                              // rather than pushing the row apart.
                              Flexible(
                                child: Row(
                                  spacing: 5,
                                  children: [
                                    Icon(WindowsIcons.history,
                                        size: 16,
                                        color: FluentTheme.of(context)
                                            .typography
                                            .bodyStrong!
                                            .color),
                                    Flexible(
                                      child: Txt(
                                          "${txt("otherAppointments")} (${widget.patient.allAppointments.length - 1})",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: FluentTheme.of(context)
                                              .typography
                                              .bodyStrong),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.patient.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 11),
                                ),
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
                                    unawaited(openPatient(widget.patient,
                                        PatientWindow.appointments));
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
            ));
          },
        ),
      ),
    );
  }
}

/// A visit's labwork, wherever it is shown: the panel's own body and the labwork
/// window draw the same thing, so neither can drift from the other.
///
/// Two states, because a visit either has an order or has not started one: the
/// way to start one, and the order itself with the way to take it away.
class AppointmentLabworkSection extends StatefulWidget {
  const AppointmentLabworkSection({super.key, required this.appointment});

  final Appointment appointment;

  @override
  State<AppointmentLabworkSection> createState() =>
      _AppointmentLabworkSectionState();
}

class _AppointmentLabworkSectionState extends State<AppointmentLabworkSection> {
  void _setHasLabwork(bool hasLabwork) => setState(
        () => widget.appointment.hasLabwork = hasLabwork,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.appointment.hasLabwork) {
      return LabWorkEditor(
        appointment: widget.appointment,
        onDelete: () => _setHasLabwork(false),
      );
    }
    return HyperlinkButton(
      key: WK.btnAddLabwork,
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          FluentTheme.of(context).typography.caption,
        ),
      ),
      onPressed: () => _setHasLabwork(true),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(FluentIcons.manufacturing),
          const SizedBox(width: 15),
          SizedBox(width: 200, child: Txt(txt("addLabwork"), softWrap: true)),
        ],
      ),
    );
  }
}

class LabWorkEditor extends StatefulWidget {
  const LabWorkEditor({super.key, required this.appointment, this.onDelete});
  final Appointment appointment;
  final VoidCallback? onDelete;
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
                    if (reason == TextChangedReason.userInput) {
                      widget.appointment.labName = text;
                    }
                  },
                  onSelected: (item) {
                    widget.appointment.labName = item.value ?? item.label;
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
                  // The order-notes box, not the lab-name one: it carried
                  // `fieldLabworkLabName` as well, so that key matched *two*
                  // widgets and this field could not be addressed at all.
                  key: WK.fieldLabworkOrderNotes,
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
            key: WK.fieldLabworkReceived,
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
