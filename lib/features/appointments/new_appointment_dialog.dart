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

/// The sheet a visit is created from.
///
/// Creation starts here rather than in an empty panel: the visit's own
/// essentials — whose it is, when it is, for how long, with whom, and what was
/// written down for it — are asked for before there is a record, so [onSave]
/// receives a visit that can be stored as it is. Nothing is opened as a draft.
///
/// The fields the sheet does not invent come from the caller: [day] says which
/// day the caller came from, and a bare day starts at the time of day it is
/// now.
class NewAppointmentDialog extends StatefulWidget {
  const NewAppointmentDialog({
    super.key,
    required this.onSave,
    this.day,
    this.patientID,
  });

  /// The day — or, when the caller has one, the exact moment — to start from.
  /// A moment is kept, a bare day takes the current time of day.
  final DateTime? day;

  /// The patient the sheet starts with: a list opened for one patient already
  /// knows whose visit it is.
  final String? patientID;

  final void Function(Appointment appointment) onSave;

  @override
  State<NewAppointmentDialog> createState() => _NewAppointmentDialogState();
}

class _NewAppointmentDialogState extends State<NewAppointmentDialog> {
  late final Appointment _draft;
  final TextEditingController _notes = TextEditingController();

  /// The visit's initial operator, for the accounts that may only own the
  /// visits they are on.
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
    _draft.date = from == null ? DateTime.now() : _atCurrentTime(from);
    _notes.text = _draft.preOpNotes;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// [day] as the sheet starts it: a caller that clicked 10:00 meant 10:00; one
  /// that named a day meant that day at the time of day it is now.
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

  Future<void> _addPatient() async {
    final patient = await addPatient(context);
    if (patient == null || !mounted) return;
    setState(() => _draft.patientID = patient.id);
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
                        onChanged: (id) =>
                            setState(() => _draft.patientID = id),
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
                    onChanged: (ids) => _draft.operatorsIDs = ids,
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

/// Asks for a new visit's essentials and stores what the sheet says.
///
/// Returns the stored visit, or null when the sheet was dismissed. Callers open
/// the visit afterwards: it already exists, so nothing they do can leave a
/// draft behind.
Future<Appointment?> addAppointment(
  BuildContext context, {
  DateTime? day,
  String? patientID,
}) async {
  Appointment? collected;
  await showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (_) => NewAppointmentDialog(
      day: day,
      patientID: patientID,
      onSave: (appointment) => collected = appointment,
    ),
  );
  final created = collected;
  if (created == null) return null;
  appointments.set(created);
  // A new visit can keep — or inherit — the promise a follow-up made: storing it
  // here, before any caller opens it, is the one place every way of creating a
  // visit passes through (see `follow_up_scheduling.dart`).
  applyFollowUpsForNewVisit(created.id);
  return appointments.get(created.id) ?? created;
}
