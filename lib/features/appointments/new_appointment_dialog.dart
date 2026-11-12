import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/duration_pill.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/common_widgets/operators_picker.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/new_patient_dialog.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Collects a visit's essentials before any record exists, so [onSave] receives a
/// storable visit and callers open it afterwards rather than a draft.
class NewAppointmentDialog extends StatefulWidget {
  const NewAppointmentDialog({
    super.key,
    required this.onSave,
    this.day,
    this.initialMoment,
    this.patientID,
    this.initialPreOpNotes = '',
  });

  final DateTime? day;

  /// An exact start instant that wins over [day], including exact midnight, which
  /// the bare-day path would otherwise replace with the current clock time.
  final DateTime? initialMoment;

  final String? patientID;

  /// The pre-op notes the sheet starts with, such as a follow-up's note.
  final String initialPreOpNotes;

  final void Function(Appointment appointment) onSave;

  @override
  State<NewAppointmentDialog> createState() => _NewAppointmentDialogState();
}

class _NewAppointmentDialogState extends State<NewAppointmentDialog> {
  late final Appointment _draft;
  final TextEditingController _notes = TextEditingController();

  /// Set once the crew picks operators themselves; a guess never overwrites it.
  bool _operatorsPicked = false;

  /// Accounts limited to their own visits start out assigned to themselves.
  bool get _assignsItself =>
      login.perm(Perm.patients).exact(1) ||
      login.perm(Perm.appointments).exact(1) ||
      login.currentLoginIsOperator;

  @override
  void initState() {
    super.initState();
    _draft = Appointment.fromJson({
      if (widget.patientID != null) "patientID": widget.patientID,
      if (_assignsItself) "operatorsIDs": [login.currentAccountID],
    });
    final from = widget.day;
    _draft.date = widget.initialMoment ??
        (from == null ? DateTime.now() : _atCurrentTime(from));
    _draft.preOpNotes = widget.initialPreOpNotes;
    _notes.text = _draft.preOpNotes;
    _guessOperators(widget.patientID);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// A zero hour and minute means a bare day, so it takes the current time of day.
  DateTime _atCurrentTime(DateTime day) {
    if (day.hour != 0 || day.minute != 0) return day;
    final now = DateTime.now();
    return DateTime(day.year, day.month, day.day, now.hour, now.minute);
  }

  void _pickDate(DateTime picked) {
    setState(() {
      final time = _draft.date;
      _draft.date =
          DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  void _pickTime(DateTime picked) {
    setState(() {
      _draft.date = DateTime(
        _draft.date.year,
        _draft.date.month,
        _draft.date.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _pickDuration(int duration) {
    setState(() => _draft.duration = duration);
  }

  /// A creator who does not operate books for whoever last saw the patient, so
  /// the sheet starts with that operator instead of nobody.
  void _guessOperators(String? patientID) {
    if (_assignsItself || _operatorsPicked) return;
    _draft.operatorsIDs = patientID == null || patientID.isEmpty
        ? const []
        : appointments.lastOperatorsFor(patientID, before: _draft.date);
  }

  void _pickPatient(String? id) {
    setState(() {
      _draft.patientID = id;
      _guessOperators(id);
    });
  }

  Future<void> _addPatient() async {
    final patient = await addPatient(context);
    if (patient == null || !mounted) return;
    _pickPatient(patient.id);
  }

  void _save() {
    // A copy: what the caller stores must not be the sheet's own draft.
    widget.onSave(Appointment.fromJson(_draft.toJson()));
    Navigator.of(context).pop();
  }

  Widget _datePicker() => KeyedSubtree(
        key: WK.fieldNewAppointmentDate,
        child: DateTimePicker(
          initValue: _draft.date,
          onChange: _pickDate,
          buttonText: txt("changeDate"),
          buttonIcon: WindowsIcons.calendar,
        ),
      );

  Widget _timePicker() => KeyedSubtree(
        key: WK.fieldNewAppointmentTime,
        child: DateTimePicker(
          initValue: _draft.date,
          onChange: _pickTime,
          pickTime: true,
          buttonText: txt("changeTime"),
          buttonIcon: FluentIcons.clock,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return KeyboardAwareView(
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 460),
        style: dialogStyling(context, false, true),
        title: Row(children: [
          const Icon(WindowsIcons.calendar),
          const SizedBox(width: 5),
          Txt(txt("newAppointment")),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                InfoLabel(
                  label: "${txt("patient")}:",
                  child: Row(children: [
                    Expanded(
                      child: PatientPicker(
                        fieldKey: WK.fieldNewAppointmentPatient,
                        tapOpensRecord: false,
                        value: _draft.patientID,
                        onChanged: _pickPatient,
                      ),
                    ),
                    if (_draft.patientID == null) ...[
                      const SizedBox(width: 5),
                      Button(
                        onPressed: _addPatient,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: ButtonContent(
                              FluentIcons.add_friend, txt("newPatient")),
                        ),
                      ),
                    ],
                  ]),
                ),
                InfoLabel(
                  label: "${txt("date")}:",
                  child: _datePicker(),
                ),
                InfoLabel(
                  label: "${txt("time")}:",
                  child: _timePicker(),
                ),
                InfoLabel(
                  label: "${txt("duration")}:",
                  child: DurationPill(
                    item: _draft,
                    color: Colors.blue,
                    onSet: _pickDuration,
                    isCompact: false,
                  ),
                ),
                InfoLabel(
                  label: "${txt("doctors")}:",
                  child: OperatorsPicker(
                    value: _draft.operatorsIDs,
                    onChanged: (ids) {
                      _operatorsPicked = true;
                      _draft.operatorsIDs = ids;
                    },
                  ),
                ),
                InfoLabel(
                  label: "${txt("preOperativeNotes")}:",
                  child: SizedBox(
                    height: 80,
                    child: LiveTranscribingTextField(
                      key: WK.fieldNewAppointmentNotes,
                      controller: _notes,
                      expands: true,
                      maxLines: null,
                      placeholder: "${txt("preOperativeNotes")}...",
                      onChanged: (value) => _draft.preOpNotes = value,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: WK.btnCreateAppointment,
            onPressed: _draft.patientID == null ? null : _save,
            child: ButtonContent(FluentIcons.add, txt("save")),
          ),
          const CloseButtonInDialog(),
        ],
      ),
    );
  }
}

/// Asks for a visit's essentials, stores it and returns it (null when dismissed).
/// Callers open the stored visit, so nothing they do can leave a draft behind.
Future<Appointment?> addAppointment(
  BuildContext context, {
  DateTime? day,
  DateTime? initialMoment,
  String? patientID,
  String initialPreOpNotes = '',
}) async {
  Appointment? collected;
  await showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (_) => NewAppointmentDialog(
      day: day,
      initialMoment: initialMoment,
      patientID: patientID,
      initialPreOpNotes: initialPreOpNotes,
      onSave: (appointment) => collected = appointment,
    ),
  );
  final created = collected;
  if (created == null) return null;
  appointments.set(created);
  // Follow-up promises are applied here because every creation path stores through
  // this point, before any caller opens the visit.
  applyFollowUpsForNewVisit(created.id);
  return appointments.get(created.id) ?? created;
}
