import 'dart:async';

import 'package:apexo/app/panels/delegated_panel.dart';
import 'package:apexo/app/panels/panel_tab.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
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
import 'package:apexo/app/panels/panels_manager.dart';

final _isEditing = ObservableState(false);
final _selectedPatientID = ObservableState<String>("");
final _selectedAppointmentID = ObservableState<String>("");
final _hasEdited = ObservableState(false);

String _panelIdentifier(String appointmentId) => "$appointmentId-labwork";

void closeLabworksPanels() {
  final List<String> toClose = [];
  for (var panel in PanelsManager.active()) {
    final identifier = panel.identifier;
    if (identifier.endsWith("-labwork")) {
      toClose.add(identifier);
    }
  }
  for (final identifier in toClose) {
    PanelsManager.close(identifier);
  }
}

Future<String?> openLabworkPanel(
    Appointment? initiallySelectedAppointment) async {
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

  final panel = DelegatedPanel(
    // A synthetic id keyed on the appointment the panel starts from: this
    // panel edits whichever appointment the user picks, so it has no single
    // stored record behind it.
    itemId: _panelIdentifier(initiallySelectedAppointment?.id ?? ""),
    showTitles: true,
    showBottomControls: false,
    inherentlyScrollable: false,
    singularName: "labwork",
    unicodeSymbol: "🔬",
    selectedTabIndex: 0,
    icon: FluentIcons.manufacturing,
    // The header names the appointment's patient, and falls back to the
    // "new labwork" label when the panel opens with nothing selected.
    newTitle: "newLabwork",
    recordTitle: () async => initiallySelectedAppointment == null
        ? txt("newLabwork")
        : "${initiallySelectedAppointment.patient?.title ?? ""} ${txt("labwork")}",
    // The panel owns no record and keeps no snapshot of one, and its bodies
    // write each labwork row themselves — there is no Save button
    // (`showBottomControls: false`), so there is nothing for it to report.
    checkUnsavedChanges: () => false,
    onSave: () async => <String>[],
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
  await panel.readTitle();
  final shown = PanelsManager.open(panel);
  // The panel is done when the user saves it or closes it without saving.
  await shown.result;
  return shown.savedId;
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
    final Patient? selectedPatient = _selectedPatientID().isEmpty
        ? null
        : patients.get(_selectedPatientID());

    final Appointment? selectedAppointment = _selectedAppointmentID().isEmpty
        ? null
        : appointments.get(_selectedAppointmentID());

    final bool validPatientWithAppointments = () {
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
          final Appointment? selectedAppointment =
              _selectedAppointmentID().isEmpty
                  ? null
                  : appointments.get(_selectedAppointmentID());
          return Row(
            spacing: 10,
            children: [
              if (selectedAppointment != null &&
                  selectedAppointment.hasLabwork == true)
                FlyoutTarget(
                  controller: confirmDeleteFlyoutController,
                  child: IconButton(
                    style: filledButtonStyle(Colors.errorPrimaryColor),
                    onPressed: () async {
                      await flyoutFocusFix(context);
                      unawaited(confirmDeleteFlyoutController.showFlyout(
                          builder: (ctx) {
                        return ConfirmDeleteFlyout(
                          preview: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 5,
                            children: [
                              const Icon(FluentIcons.manufacturing),
                              Txt("${txt("labwork")}:"),
                              Txt(selectedAppointment.patient?.title ?? "")
                            ],
                          ),
                          restorable: false,
                          onConfirm: () {
                            selectedAppointment.hasLabwork = false;
                            appointments.set(selectedAppointment);
                            closeLabworksPanels();
                          },
                          controller: confirmDeleteFlyoutController,
                        );
                      }));
                    },
                    icon: ButtonContent(
                      WindowsIcons.delete,
                      "${txt("delete")} ${txt("labwork")}",
                      size: 13,
                    ),
                  ),
                ),
              if (selectedAppointment != null)
                IconButton(
                  style: filledButtonStyle(
                      _hasEdited() ? Colors.blue : Colors.grey.withAlpha(100)),
                  icon: ButtonContent(
                    WindowsIcons.save,
                    txt("save"),
                    size: 13,
                  ),
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
