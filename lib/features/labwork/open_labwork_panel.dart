import 'dart:async';

import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart' hide TextBox;

final _isEditing = ObservableState(false);
final _selectedPatientID = ObservableState<String>("");
final _selectedAppointmentID = ObservableState<String>("");
final _hasEdited = ObservableState(false);

_panelIdentifier(String appointmentId) => "$appointmentId-labwork";

closeLabworksPanels() {
  List<String> toClose = [];
  for (var panel in routes.panels()) {
    final identifier = panel.identifier;
    if (identifier.endsWith("-labwork")) {
      toClose.add(identifier);
    }
  }
  for (final identifier in toClose) {
    routes.closePanel(identifier);
  }
}

openLabworkPanel(Appointment? initiallySelectedAppointment) {
  closeLabworksPanels();
  closeAppointmentsPanels();
  _hasEdited(false);

  if (initiallySelectedAppointment != null) {
    _isEditing(true);
    _selectedPatientID(initiallySelectedAppointment.patientID);
    _selectedAppointmentID(initiallySelectedAppointment.id);
  } else {
    _isEditing(false);
    _selectedPatientID("");
    _selectedAppointmentID("");
  }

  final panel = Panel<Appointment>(
    showTitles: true,
    showBottomControls: false,
    inherentlyScrollable: false,
    singularName: "labwork",
    unicodeSymbol: "🔬",
    selectedTabIndex: 0,
    item: Appointment.fromJson(
        {"id": _panelIdentifier(initiallySelectedAppointment?.id ?? "")}),
    store: appointments,
    icon: FluentIcons.manufacturing,
    title: initiallySelectedAppointment == null
        ? txt("newLabwork")
        : ("${initiallySelectedAppointment.patient?.title ?? ""} ${txt("labwork")}"),
    canNotBeNew: true,
    additionalControls: _LabeWorkPanelActions(),
    tabs: [
      PanelTab(
        title: txt("labwork"),
        icon: FluentIcons.manufacturing,
        body: const Padding(
          padding: EdgeInsets.all(8.0),
          child: _SingleLabworkPanelBody(),
        ),
        padding: 0,
      ),
    ],
  );
  routes.openPanel(panel);
  return panel.result.future;
}

class _SingleLabworkPanelBody extends StatefulWidget {
  const _SingleLabworkPanelBody();

  @override
  State<_SingleLabworkPanelBody> createState() =>
      _SingleLabworkPanelBodyState();
}

class _SingleLabworkPanelBodyState extends State<_SingleLabworkPanelBody> {
  String labworkStamp = "";
  Timer? timer;
  @override
  void initState() {
    super.initState();
    labworkStamp =
        labworkStampFromAppointment(appointments.get(_selectedAppointmentID()));
    timer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (labworkStampFromAppointment(
              appointments.get(_selectedAppointmentID())) !=
          labworkStamp) {
        _hasEdited(true);
      } else {
        _hasEdited(false);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String labworkStampFromAppointment(Appointment? appointment) {
    if (appointment == null) return "";
    return "${appointment.labName}${appointment.labworkNotes}${appointment.labworkReceived}";
  }

  Widget formatAppointmentDate(DateTime date) {
    return Txt("${txt("appointment")}: ${DF.allNumbers(date)}");
  }

  @override
  Widget build(BuildContext context) {
    Patient? selectedPatient = _selectedPatientID().isEmpty
        ? null
        : patients.get(_selectedPatientID());

    Appointment? selectedAppointment = _selectedAppointmentID().isEmpty
        ? null
        : appointments.get(_selectedAppointmentID());

    bool validPatientWithAppointments = () {
      if (selectedPatient == null) return false;
      if (selectedPatient.allAppointments.isEmpty) return false;
      return true;
    }();

    return MStreamBuilder(
        streams: [
          _isEditing.stream,
          _selectedPatientID.stream,
          _selectedAppointmentID.stream,
        ],
        builder: (context, asyncSnapshot) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              if (!_isEditing())
                PatientPicker(
                  onChanged: (patientID) {
                    setState(() {
                      _selectedPatientID(patientID ?? "");
                      _selectedAppointmentID("");
                    });
                  },
                  value: _selectedPatientID().isEmpty
                      ? null
                      : _selectedPatientID(),
                ),
              if (selectedPatient == null && !_isEditing())
                InfoBar(title: Txt(txt("selectPatientFirst")))
              else if ((!validPatientWithAppointments) && !_isEditing())
                InfoBar(title: Txt(txt("patientHasNoAppointments")))
              else if (_isEditing())
                Button(
                  child: Row(spacing: 5, children: [
                    const Icon(WindowsIcons.calendar, size: 18),
                    formatAppointmentDate(selectedAppointment!.date),
                    Txt(
                      selectedPatient!.title,
                      style: FluentTheme.of(context).typography.bodyStrong,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                  onPressed: () {
                    openAppointment(selectedAppointment);
                    closeLabworksPanels();
                  },
                )
              else
                ComboBox<String>(
                  items: (selectedPatient!.allAppointments.toList()
                        ..sort((a, b) => a.date.compareTo(b.date)))
                      .map((e) => ComboBoxItem(
                          value: e.id, child: formatAppointmentDate(e.date)))
                      .toList(),
                  icon: const Icon(WindowsIcons.calendar, size: 18),
                  placeholder: Txt(txt("selectAppointment")),
                  onChanged: _isEditing()
                      ? null
                      : (id) {
                          setState(() {
                            _selectedAppointmentID(id!);
                          });
                        },
                  value: _selectedAppointmentID(),
                ),
              if (selectedAppointment != null)
                LabWorkEditor(
                  appointment: selectedAppointment,
                )
            ],
          );
        });
  }
}

class _LabeWorkPanelActions extends StatefulWidget {
  @override
  State<_LabeWorkPanelActions> createState() => _LabeWorkPanelActionsState();
}

class _LabeWorkPanelActionsState extends State<_LabeWorkPanelActions> {
  final FlyoutController confirmDeleteFlyoutController = FlyoutController();

  @override
  void dispose() {
    confirmDeleteFlyoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [_selectedAppointmentID.stream, _hasEdited.stream],
        builder: (context, asyncSnapshot) {
          Appointment? selectedAppointment = _selectedAppointmentID().isEmpty
              ? null
              : appointments.get(_selectedAppointmentID());
          return Row(
            spacing: 10,
            children: [
              if (selectedAppointment != null &&
                  selectedAppointment.hasLabwork == true)
                FlyoutTarget(
                  controller: confirmDeleteFlyoutController,
                  child: FilledButton(
                    style: filledButtonStyle(Colors.errorPrimaryColor),
                    onPressed: () async {
                      await flyoutFocusFix(context);
                      confirmDeleteFlyoutController.showFlyout(builder: (ctx) {
                        return ConfirmDeleteFlyout(
                          onConfirm: () {
                            selectedAppointment.hasLabwork = false;
                            appointments.set(selectedAppointment);
                            closeLabworksPanels();
                          },
                          controller: confirmDeleteFlyoutController,
                        );
                      });
                    },
                    child: ButtonContent(WindowsIcons.delete,
                        "${txt("delete")} ${txt("labwork")}"),
                  ),
                ),
              if (selectedAppointment != null)
                FilledButton(
                  style: filledButtonStyle(
                      _hasEdited() ? Colors.blue : Colors.grey.withAlpha(100)),
                  child: ButtonContent(WindowsIcons.save, txt("save")),
                  onPressed: () {
                    if (!_hasEdited()) {
                      return;
                    }
                    selectedAppointment.hasLabwork = true;
                    appointments.set(selectedAppointment);
                    closeLabworksPanels();
                  },
                ),
            ],
          );
        });
  }
}
