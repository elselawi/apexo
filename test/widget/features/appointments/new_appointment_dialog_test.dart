@Tags(['serial'])
library;

import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/duration_pill.dart';
import 'package:apexo/common_widgets/operators_picker.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

/// Asserts the sheet starts at the clock's hour and minute on [day]; the minute
/// may tick over while it opens and saves, so both ends of the wait are allowed.
void expectStartsAt(
  DateTime actual,
  DateTime day,
  DateTime opened,
  DateTime closed,
) {
  expect(
    [actual.year, actual.month, actual.day],
    [day.year, day.month, day.day],
  );
  expect(
    {
      opened.hour * 60 + opened.minute,
      closed.hour * 60 + closed.minute,
    },
    contains(actual.hour * 60 + actual.minute),
  );
}

void main() {
  late List<Appointment> previousAppointments;
  late List<Patient> previousPatients;
  late Patient patient;

  final day = DateTime.now().add(const Duration(days: 7));
  final bareDay = DateTime(day.year, day.month, day.day);

  setUp(() {
    previousAppointments = appointments.docs.values.toList();
    previousPatients = patients.docs.values.toList();
    appointments.observableMap.clear();
    patients.observableMap.clear();
    patient = testPatient(id: 'sheet-patient', name: 'Ada Lovelace');
    patients.set(patient);
  });

  tearDown(() {
    appointments.observableMap.clear();
    appointments.setAll(previousAppointments);
    patients.observableMap.clear();
    patients.setAll(previousPatients);
  });

  Future<void> openSheet(
    WidgetTester tester, {
    required void Function(Appointment) onSave,
    String? patientID,
    String initialPreOpNotes = '',
  }) async {
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          key: const Key('openAppointmentSheet'),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => NewAppointmentDialog(
              onSave: onSave,
              day: bareDay,
              patientID: patientID,
              initialPreOpNotes: initialPreOpNotes,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openAppointmentSheet')));
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(WK.btnCreateAppointment));

  testWidgets('a visit cannot be created without a patient', (tester) async {
    await openSheet(tester, onSave: (_) {});

    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('a known patient lets the visit be created', (tester) async {
    await openSheet(tester, onSave: (_) {}, patientID: patient.id);

    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('the sheet hands over the current time of day and what was typed',
      (tester) async {
    Appointment? created;
    final opened = DateTime.now();
    await openSheet(
      tester,
      patientID: patient.id,
      onSave: (appointment) => created = appointment,
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(WK.fieldNewAppointmentNotes),
        matching: find.byType(EditableText),
      ),
      'Crown preparation',
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(WK.fieldNewAppointmentNotes)).height,
        greaterThan(40));
    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();
    final closed = DateTime.now();

    expect(created, isNotNull);
    expect(created!.patientID, patient.id);
    expectStartsAt(created!.date, bareDay, opened, closed);
    expect(created!.preOpNotes, 'Crown preparation');
    expect(find.byKey(WK.fieldNewAppointmentPatient), findsNothing);
  });

  testWidgets('initial pre-op notes appear in the field and are saved',
      (tester) async {
    Appointment? created;
    await openSheet(
      tester,
      patientID: patient.id,
      initialPreOpNotes: 'Crown preparation',
      onSave: (appointment) => created = appointment,
    );

    final notes = tester.widget<EditableText>(find.descendant(
      of: find.byKey(WK.fieldNewAppointmentNotes),
      matching: find.byType(EditableText),
    ));
    expect(notes.controller.text, 'Crown preparation');

    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();

    expect(created!.preOpNotes, 'Crown preparation');
  });

  testWidgets('a visit already booked that day does not move the start',
      (tester) async {
    appointments.set(testAppointment(
      id: 'booked',
      patientID: patient.id,
      date: DateTime(bareDay.year, bareDay.month, bareDay.day, 9),
      duration: 30,
    ));

    Appointment? created;
    final opened = DateTime.now();
    await openSheet(
      tester,
      patientID: patient.id,
      onSave: (appointment) => created = appointment,
    );

    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();
    final closed = DateTime.now();

    expectStartsAt(created!.date, bareDay, opened, closed);
  });

  testWidgets('a timeline time survives changing duration and day',
      (tester) async {
    Appointment? created;
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => NewAppointmentDialog(
              day: DateTime(day.year, day.month, day.day, 14, 30),
              patientID: patient.id,
              onSave: (visit) => created = visit,
            ),
          ),
          child: const Text('open timed sheet'),
        ),
      ),
    );
    await tester.tap(find.text('open timed sheet'));
    await tester.pumpAndSettle();
    tester.widget<DurationPill>(find.byType(DurationPill)).onSet(30);
    await tester.pump();
    final tomorrow = DateTime(day.year, day.month, day.day + 1);
    tester
        .widget<DateTimePicker>(find.descendant(
          of: find.byKey(WK.fieldNewAppointmentDate),
          matching: find.byType(DateTimePicker),
        ))
        .onChange(tomorrow);
    await tester.pump();
    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();

    expect(created!.date,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 30));
    expect(created!.duration, 30);
  });

  testWidgets('addAppointment stores the visit before returning it',
      (tester) async {
    late Future<Appointment?> pending;
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          key: const Key('openAppointmentSheet'),
          onPressed: () => pending =
              addAppointment(context, day: bareDay, patientID: patient.id),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openAppointmentSheet')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();

    final created = await pending;
    expect(created, isNotNull);
    expect(appointments.get(created!.id)?.patientID, patient.id);
    expect(appointments.get(created.id)?.archived, isNot(true));
  });

  testWidgets('dismissing the sheet stores nothing', (tester) async {
    Appointment? created;
    await openSheet(
      tester,
      patientID: patient.id,
      onSave: (appointment) => created = appointment,
    );

    await tester.tap(find.byIcon(WindowsIcons.cancel));
    await tester.pumpAndSettle();

    expect(created, isNull);
    expect(appointments.docs, isEmpty);
  });

  testWidgets(
      'picking the patient from the dropdown and creating the visit '
      'leaves no torn-down field behind', (tester) async {
    // Regression: tearing the patient box down with a suggestion highlighted
    // rebuilt a locked tree ("setState() … called when widget tree was locked").
    Appointment? created;
    await openSheet(tester, onSave: (appointment) => created = appointment);

    await tester.enterText(
      find.descendant(
        of: find.byKey(WK.fieldNewAppointmentPatient),
        matching: find.byType(EditableText),
      ),
      'Ada',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ada Lovelace').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.patientID, patient.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picked patient is shown by name, not folded to a count',
      (tester) async {
    await openSheet(tester, onSave: (_) {});

    await tester.enterText(
      find.descendant(
        of: find.byKey(WK.fieldNewAppointmentPatient),
        matching: find.byType(EditableText),
      ),
      'Ada',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ada Lovelace').last);
    await tester.pumpAndSettle();

    // A picked patient shows as one chip; the sheet used to fold it to "+1",
    // hiding who the visit is for.
    expect(find.text('+1'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(WK.fieldNewAppointmentPatient),
        matching: find.text('Ada Lovelace'),
      ),
      findsWidgets,
    );
  });

  group('operator guess for a creator who does not operate', () {
    late List<int> previousPermissions;

    setUp(() {
      previousPermissions = login.savedPermissions;
      login.savedPermissions = Perm.zeroes;
    });

    tearDown(() => login.savedPermissions = previousPermissions);

    /// A finished visit of [patient] operated by [operatorID].
    void previousVisit(String operatorID) {
      appointments.set(testAppointment(
        id: 'previous-visit',
        patientID: patient.id,
        operatorsIDs: [operatorID],
        date: DateTime.now().subtract(const Duration(days: 10)),
        isDone: true,
      ));
    }

    testWidgets('the sheet starts with the last visit\'s operator',
        (tester) async {
      previousVisit('op-previous');

      Appointment? created;
      await openSheet(
        tester,
        patientID: patient.id,
        onSave: (appointment) => created = appointment,
      );

      await tester.tap(find.byKey(WK.btnCreateAppointment));
      await tester.pumpAndSettle();

      expect(created!.operatorsIDs, ['op-previous']);
    });

    testWidgets('picking the patient guesses their last visit\'s operator',
        (tester) async {
      previousVisit('op-previous');

      Appointment? created;
      await openSheet(tester, onSave: (appointment) => created = appointment);

      tester
          .widget<PatientPicker>(find.byType(PatientPicker))
          .onChanged(patient.id);
      await tester.pump();

      await tester.tap(find.byKey(WK.btnCreateAppointment));
      await tester.pumpAndSettle();

      expect(created!.operatorsIDs, ['op-previous']);
    });

    testWidgets('a patient with no earlier visit leaves the operators empty',
        (tester) async {
      Appointment? created;
      await openSheet(
        tester,
        patientID: patient.id,
        onSave: (appointment) => created = appointment,
      );

      await tester.tap(find.byKey(WK.btnCreateAppointment));
      await tester.pumpAndSettle();

      expect(created!.operatorsIDs, isEmpty);
    });

    testWidgets('an operator picked by hand survives a patient change',
        (tester) async {
      previousVisit('op-previous');

      Appointment? created;
      await openSheet(tester, onSave: (appointment) => created = appointment);

      tester
          .widget<OperatorsPicker>(find.byType(OperatorsPicker))
          .onChanged(['op-handpicked']);
      await tester.pump();

      tester
          .widget<PatientPicker>(find.byType(PatientPicker))
          .onChanged(patient.id);
      await tester.pump();

      await tester.tap(find.byKey(WK.btnCreateAppointment));
      await tester.pumpAndSettle();

      expect(created!.operatorsIDs, ['op-handpicked']);
    });
  });
}
