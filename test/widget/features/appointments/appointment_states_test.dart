@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

/// The states a visit can be in when it is opened (plan §4.7, §0.1).
///
/// The one that must never regress is the locked patient: a visit of a record
/// this account may not see opens on its own, and the patient's record is never
/// put on screen.
void main() {
  late List<int> permissions;
  late List<Patient> originalPatients;
  late List<Appointment> originalAppointments;

  setUp(() {
    permissions = List.of(login.savedPermissions);
    originalPatients = patients.docs.values.toList();
    originalAppointments = appointments.docs.values.toList();
    patients.observableMap.clear();
    appointments.observableMap.clear();
    appointmentSessions.clear();
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    appointmentSessions.clear();
    patients.observableMap.clear();
    appointments.observableMap.clear();
    patients.setAll(originalPatients);
    appointments.setAll(originalAppointments);
    login.savedPermissions = permissions;
  });

  testWidgets('switching visits refreshes the labwork editor fields',
      (tester) async {
    final first = testAppointment(id: 'first-lab')
      ..hasLabwork = true
      ..labName = 'First laboratory'
      ..labworkNotes = 'First order';
    final second = testAppointment(id: 'second-lab')
      ..hasLabwork = true
      ..labName = 'Second laboratory'
      ..labworkNotes = 'Second order';
    await pumpApexoApp(tester, AppointmentLabworkSection(appointment: first));
    expect(
        tester
            .widget<AutoSuggestBox<String>>(find.byKey(WK.fieldLabworkLabName))
            .controller!
            .text,
        first.labName);

    await pumpApexoApp(tester, AppointmentLabworkSection(appointment: second));

    expect(
        tester
            .widget<AutoSuggestBox<String>>(find.byKey(WK.fieldLabworkLabName))
            .controller!
            .text,
        second.labName);
    expect(find.text('Second order'), findsOneWidget);
    expect(find.text('First order'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a locked patient\'s visit opens stand-alone, never the record',
      (tester) async {
    // The visit is somebody else's, and this account may only see its own
    // patients: exactly what `Patient.locked` exists for.
    login.savedPermissions = List.of(Perm.full)..[Perm.patients] = 1;
    final patient = testPatient(id: 'locked-patient', name: 'Locked Patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'locked-visit',
      patientID: patient.id,
      date: DateTime(2026, 6, 7),
    );
    appointments.set(visit);
    expect(patient.locked, isTrue, reason: 'the fixture is a locked patient');

    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty,
        reason: 'the patient record is not opened for an account it is locked '
            'from');
    final floating = WindowsManager.open().single;
    expect(floating.window.id, AppointmentWindow.details.id);
    expect(floating.scope, 'appointment:locked-visit');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visit with no patient opens stand-alone from the same session',
      (tester) async {
    // Legacy/demo records only — the creation dialog refuses to make one — but a
    // visit that exists must still open, and must not invent a patient panel.
    final visit =
        testAppointment(id: 'orphan-visit', date: DateTime(2026, 6, 8));
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open().single.scope, 'appointment:orphan-visit');
    expect(appointmentSessions.get('orphan-visit'), isNotNull,
        reason: 'the record still has its one session');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visit id that no longer exists opens nothing', (tester) async {
    await pumpApexoApp(tester, const SizedBox.shrink());

    await selectVisit('gone-patient', 'gone-visit');
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visit with a visible patient opens beside it', (tester) async {
    final patient = testPatient(id: 'visible-patient', name: 'Visible Patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'visible-visit',
      patientID: patient.id,
      date: DateTime(2026, 6, 9),
    );
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit);
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id);
    expect(panel.attached!.itemId, visit.id);
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('a visit opens on its chart, where its post-op record sits', () async {
    login.savedPermissions = Perm.full;
    final patient = testPatient(id: 'done-patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'done-visit',
      patientID: patient.id,
      isDone: true,
      postOpNotes: 'done',
    );
    appointments.set(visit);

    await openAppointment(visit);

    final panel = PanelsManager.active().single;
    // The appointment form is the band; the post-op record is the chart's foot.
    // So "the visit" is the chart, finished or not (the design brief).
    expect(panel.attachedFocus, AppointmentWindow.dentalChart.id,
        reason:
            'the visit opens on its workspace, which carries what was done');
  });

  test('restoring an archived visit writes that field only', () {
    final patient = testPatient(id: 'archive-patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'archive-visit',
      patientID: patient.id,
      archived: true,
    );
    appointments.set(visit);
    final session = appointmentSessions.getOrCreate(visit);
    session.item.preOpNotes = 'typed before restoring';

    return session.setArchived(false).then((_) {
      expect(session.isArchived, isFalse);
      expect(appointments.get('archive-visit')!.archived, isFalse,
          reason: 'the restore is written at once');
      expect(session.hasPendingEdits, isTrue,
          reason: 'the note typed before the restore is still unsaved');
    });
  });

  test('opening a visit never unarchives it', () async {
    final patient = testPatient(id: 'archived-open-patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'archived-open-visit',
      patientID: patient.id,
      archived: true,
    );
    appointments.set(visit);
    final session = appointmentSessions.getOrCreate(visit);

    await session.save();

    expect(appointments.get('archived-open-visit')!.archived, isTrue,
        reason: 'a save is not an unarchive (plan §4.7)');
    expect(session.isArchived, isTrue);
  });

  test('the session is the chart\'s owner, and one save writes both', () async {
    final patient = testPatient(id: 'chart-owner-patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'chart-owner-visit',
      patientID: patient.id,
    );
    appointments.set(visit);
    final session = appointmentSessions.getOrCreate(visit);

    session.chart.teeth['11'] = 'filling';
    session.chart.changed();
    await session.save();

    expect(appointments.get('chart-owner-visit')!.teeth, {'11': 'filling'});
    expect(session.chart.hasChanges, isFalse);
  });

  test('opening the same visit twice returns one session', () {
    final patient = testPatient(id: 'one-session-patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'one-session-visit',
      patientID: patient.id,
    );
    appointments.set(visit);

    final first = appointmentSessions.getOrCreate(visit);
    final second = appointmentSessions.getOrCreate(
      Appointment.fromJson(visit.toJson()),
    );

    expect(identical(first, second), isTrue);
  });

  test('a stale patient selection cannot host another patient\'s visit',
      () async {
    final oldPatient = testPatient(id: 'old-selection-patient');
    final actualPatient = testPatient(id: 'actual-visit-patient');
    patients.set(oldPatient);
    patients.set(actualPatient);
    final visit = testAppointment(
      id: 'moved-visit',
      patientID: actualPatient.id,
    );
    appointments.set(visit);

    await selectVisit(oldPatient.id, visit.id);

    final panel = PanelsManager.active().single;
    expect(panel.itemId, actualPatient.id);
    expect(panel.attached!.itemId, visit.id);
  });

  test('openAppointment with no visit opens nothing at all', () {
    // Intentional API change (plan §8.3): there is no "new visit" path here —
    // the dialog that creates one stores it first.
    unawaited(openAppointment());

    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open(), isEmpty);
  });
}
