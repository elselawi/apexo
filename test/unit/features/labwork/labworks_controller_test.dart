@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  final injectedApptIds = <String>{};
  final injectedPatientIds = <String>{};
  late List<int> originalPerms;

  void cleanUp() {
    for (final id in injectedApptIds) {
      if (appointments.has(id)) appointments.archive(id);
    }
    for (final id in injectedPatientIds) {
      if (patients.has(id)) patients.archive(id);
    }
    injectedApptIds.clear();
    injectedPatientIds.clear();
  }

  setUpAll(() {
    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });

  setUp(() {
    // Force cache invalidation before each test (lazy rebuild on next access).
    appointments.nullifyAppointmentsCache(null);
    login.savedPermissions = Perm.full;
  });

  tearDown(cleanUp);
  tearDownAll(() {
    login.savedPermissions = originalPerms;
  });

  // ObservableBase.notifyObservers dispatches via a broadcast StreamController
  // (async microtask). Draining pending microtasks lets the labworks controller's
  // observer fire before we assert on the cached getters.
  Future<void> flushObservers() => Future.microtask(() {});

  group('Labworks controller — singleton', () {
    test('labworks singleton exists', () {
      expect(labworks, isNotNull);
    });

    test('appointmentsWithLabworks returns a list', () async {
      await flushObservers();
      expect(labworks.appointmentsWithLabworks, isA<List<Appointment>>());
    });

    test('due returns a list', () async {
      await flushObservers();
      expect(labworks.due, isA<List<Appointment>>());
    });

    test('notDelivered returns a list', () async {
      await flushObservers();
      expect(labworks.notDelivered, isA<List<Appointment>>());
    });

    test('notDeliveredPatients returns a list', () async {
      await flushObservers();
      expect(labworks.notDeliveredPatients, isA<List<Patient>>());
    });
  });

  group('Labworks controller — appointmentsWithLabworks', () {
    test('includes only appointments with hasLabwork=true', () async {
      final p = testPatient(id: 'lab-pt-1');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final withLab = testAppointment(
        id: 'lab-1',
        patientID: p.id,
        date: DateTime.now(),
        hasLabwork: true,
        labName: 'Lab A',
      );
      final withoutLab = testAppointment(
        id: 'lab-2',
        patientID: p.id,
        date: DateTime.now(),
        hasLabwork: false,
      );
      appointments.set(withLab);
      appointments.set(withoutLab);
      injectedApptIds.addAll([withLab.id, withoutLab.id]);

      await flushObservers();
      final res = labworks.appointmentsWithLabworks;
      expect(res.any((a) => a.id == withLab.id), isTrue);
      expect(res.any((a) => a.id == withoutLab.id), isFalse);
    });

    test('includes received and unreceived labwork regardless of lab name',
        () async {
      final p = testPatient(id: 'lab-pt-all-states');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final received = testAppointment(
        id: 'lab-all-received',
        patientID: p.id,
        date: DateTime(2025, 1, 1),
        hasLabwork: true,
        labName: '',
        labworkReceived: true,
      );
      final waiting = testAppointment(
        id: 'lab-all-waiting',
        patientID: p.id,
        date: DateTime(2025, 1, 2),
        hasLabwork: true,
        labName: 'Named lab',
        labworkReceived: false,
      );
      appointments.setAll([received, waiting]);
      injectedApptIds.addAll([received.id, waiting.id]);

      await flushObservers();
      final ids = labworks.appointmentsWithLabworks.map((a) => a.id).toSet();
      expect(ids, containsAll([received.id, waiting.id]));
    });

    test('does not require an appointment to belong to a patient', () async {
      final standalone = testAppointment(
        id: 'lab-standalone',
        date: DateTime(2025, 1, 1),
        hasLabwork: true,
      );
      appointments.set(standalone);
      injectedApptIds.add(standalone.id);

      await flushObservers();

      expect(
        labworks.appointmentsWithLabworks.map((a) => a.id),
        contains(standalone.id),
      );
    });
  });

  group('Labworks controller — due', () {
    test('includes only labwork not yet received', () async {
      final p = testPatient(id: 'lab-pt-due');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final dueAppt = testAppointment(
        id: 'lab-due',
        patientID: p.id,
        date: DateTime.now(),
        hasLabwork: true,
        labName: 'Lab B',
        labworkReceived: false,
      );
      final receivedAppt = testAppointment(
        id: 'lab-received',
        patientID: p.id,
        date: DateTime.now(),
        hasLabwork: true,
        labName: 'Lab B',
        labworkReceived: true,
      );
      appointments.set(dueAppt);
      appointments.set(receivedAppt);
      injectedApptIds.addAll([dueAppt.id, receivedAppt.id]);

      await flushObservers();
      final res = labworks.due;
      expect(res.any((a) => a.id == dueAppt.id), isTrue);
      expect(res.any((a) => a.id == receivedAppt.id), isFalse);
    });

    test('includes labwork awaiting receipt even when lab name is empty',
        () async {
      final p = testPatient(id: 'lab-pt-no-lab-name');
      patients.set(p);
      injectedPatientIds.add(p.id);
      final appt = testAppointment(
        id: 'lab-empty-name-due',
        patientID: p.id,
        date: DateTime(2025, 1, 1),
        hasLabwork: true,
        labName: '',
        labworkReceived: false,
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      await flushObservers();

      expect(labworks.due.map((a) => a.id), contains(appt.id));
    });

    test('excludes non-labwork appointments even when not received', () async {
      final appt = testAppointment(
        id: 'non-lab-not-received',
        date: DateTime(2025, 1, 1),
        hasLabwork: false,
        labworkReceived: false,
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      await flushObservers();

      expect(labworks.due.map((a) => a.id), isNot(contains(appt.id)));
    });
  });

  group('Labworks controller — not delivered', () {
    test('includes a patient whose latest appointment is received labwork',
        () async {
      final p = testPatient(id: 'lab-pt-undelivered');
      patients.set(p);
      injectedPatientIds.add(p.id);
      final received = testAppointment(
        id: 'lab-undelivered-latest',
        patientID: p.id,
        date: DateTime(2025, 2, 2),
        hasLabwork: true,
        labworkReceived: true,
      );
      appointments.set(received);
      injectedApptIds.add(received.id);

      await flushObservers();
      await flushObservers();

      expect(labworks.notDeliveredPatients.map((patient) => patient.id),
          contains(p.id));
      expect(labworks.notDelivered.map((appointment) => appointment.id),
          contains(received.id));
    });

    test('uses the latest appointment by date when deciding delivery',
        () async {
      final p = testPatient(id: 'lab-pt-latest-controls');
      patients.set(p);
      injectedPatientIds.add(p.id);
      final olderReceivedLabwork = testAppointment(
        id: 'lab-older-received',
        patientID: p.id,
        date: DateTime(2025, 1, 1),
        hasLabwork: true,
        labworkReceived: true,
      );
      final latestNonLabwork = testAppointment(
        id: 'lab-latest-non-lab',
        patientID: p.id,
        date: DateTime(2025, 2, 1),
        hasLabwork: false,
      );
      appointments.setAll([olderReceivedLabwork, latestNonLabwork]);
      injectedApptIds.addAll([olderReceivedLabwork.id, latestNonLabwork.id]);

      await flushObservers();
      await flushObservers();

      expect(labworks.notDeliveredPatients.map((patient) => patient.id),
          isNot(contains(p.id)));
      expect(labworks.notDelivered.map((appointment) => appointment.id),
          isNot(contains(olderReceivedLabwork.id)));
    });

    test('excludes a latest labwork appointment that is not received',
        () async {
      final p = testPatient(id: 'lab-pt-awaiting');
      patients.set(p);
      injectedPatientIds.add(p.id);
      final waiting = testAppointment(
        id: 'lab-latest-waiting',
        patientID: p.id,
        date: DateTime(2025, 3, 1),
        hasLabwork: true,
        labworkReceived: false,
      );
      appointments.set(waiting);
      injectedApptIds.add(waiting.id);

      await flushObservers();
      await flushObservers();

      expect(labworks.notDeliveredPatients.map((patient) => patient.id),
          isNot(contains(p.id)));
      expect(labworks.notDelivered.map((appointment) => appointment.id),
          isNot(contains(waiting.id)));
    });

    test('archived labwork is excluded from due and appointment lists',
        () async {
      final archived = testAppointment(
        id: 'lab-archived',
        hasLabwork: true,
        labworkReceived: false,
        archived: true,
      );
      appointments.set(archived);
      injectedApptIds.add(archived.id);

      await flushObservers();
      expect(labworks.appointmentsWithLabworks.map((a) => a.id),
          isNot(contains(archived.id)));
      expect(labworks.due.map((a) => a.id), isNot(contains(archived.id)));
    });

    test('maps each not-delivered patient to that patient’s latest appointment',
        () async {
      final p = testPatient(id: 'lab-pt-map-latest');
      patients.set(p);
      injectedPatientIds.add(p.id);
      final first = testAppointment(
        id: 'lab-map-first',
        patientID: p.id,
        date: DateTime(2025, 1, 1),
        hasLabwork: true,
        labworkReceived: true,
      );
      final latest = testAppointment(
        id: 'lab-map-latest',
        patientID: p.id,
        date: DateTime(2025, 2, 1),
        hasLabwork: true,
        labworkReceived: true,
      );
      appointments.setAll([first, latest]);
      injectedApptIds.addAll([first.id, latest.id]);

      await flushObservers();
      await flushObservers();

      expect(labworks.notDelivered.map((appointment) => appointment.id),
          contains(latest.id));
      expect(labworks.notDelivered.map((appointment) => appointment.id),
          isNot(contains(first.id)));
    });
  });

  group('Labworks controller — empty state', () {
    test('all caches return empty collections when no labwork present',
        () async {
      await flushObservers();
      // No labwork appointments exist (we don't inject any)
      expect(labworks.appointmentsWithLabworks, isA<List<Appointment>>());
      expect(labworks.due, isA<List<Appointment>>());
      expect(labworks.notDelivered, isA<List<Appointment>>());
      expect(labworks.notDeliveredPatients, isA<List<Patient>>());
    });
  });

  group('Labworks controller — cache invalidation on store change', () {
    test('cache rebuilds when appointments observableMap notifies', () async {
      final p = testPatient(id: 'lab-pt-cache');
      patients.set(p);
      injectedPatientIds.add(p.id);

      // Access cache first (populates _appointmentsWithLabworksCached)
      await flushObservers();
      final initial = labworks.appointmentsWithLabworks;
      final initialCount = initial.length;

      // Inject a new labwork appointment
      final appt = testAppointment(
        id: 'lab-cache-1',
        patientID: p.id,
        date: DateTime.now(),
        hasLabwork: true,
        labName: 'Lab C',
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      // Draining microtasks lets the observer (registered in labworks
      // constructor) refresh its caches.
      await flushObservers();
      await flushObservers(); // double-drain to be safe

      final after = labworks.appointmentsWithLabworks;
      expect(after.length, initialCount + 1);
      expect(after.any((a) => a.id == appt.id), isTrue);
    });
  });
}
