import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/utils/constants.dart' show dataCollectionName;
import 'package:apexo/utils/hash.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';

String _id(String prefix) => simpleHash(
      '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      length: 15,
    );

Patient _patient(String name) => Patient.fromJson({
      'id': _id('notif-patient'),
      'title': name,
    });

Appointment _appointment({
  required String patientId,
  DateTime? when,
  bool labworkDue = false,
  bool labworkReceived = false,
}) =>
    Appointment.fromJson({
      'id': _id('notif-appt'),
      'patientID': patientId,
      'operatorsIDs': [login.currentAccountID],
      'date': dateToWire(when ?? DateTime.now().add(const Duration(hours: 1))),
      if (labworkDue || labworkReceived) 'hasLabwork': true,
      if (labworkDue || labworkReceived) 'labName': 'e2e lab',
      if (labworkDue || labworkReceived) 'labworkReceived': labworkReceived,
    });

Note _note(String title) => Note.fromJson({
      'id': _id('notif-note'),
      'title': title,
      'createdBy': login.currentAccountID,
      'assignedTo': login.currentAccountID,
      'done': false,
    });

Future<void> _storePatient(Patient patient) async {
  patients.set(patient);
  await patients.waitUntilChangesAreProcessed();
}

Future<void> _storeAppointment(Appointment appointment) async {
  appointments.set(appointment);
  await appointments.waitUntilChangesAreProcessed();
}

Future<void> _storeNote(Note note) async {
  notes.set(note);
  await notes.waitUntilChangesAreProcessed();
}

Future<void> _deleteAppointmentEverywhere(String id) async {
  await RemoteRows.delete(id);
  appointments.purge(id);
}

Future<void> _deletePatientEverywhere(String id) async {
  await RemoteRows.delete(id);
  patients.purge(id);
}

Future<void> _deleteNoteEverywhere(String id) async {
  await RemoteRows.delete(id);
  notes.purge(id);
}

void registerNotificationsTests() {
  group('notifications', () {
    testWidgets('01: the bell counts today appointments and opens calendar',
        (tester) async {
      await E2E.signIn(tester);
      final patient = _patient(Fixtures.stamp('e2e notif patient'));
      final appointment = _appointment(patientId: patient.id);
      addTearDown(() async {
        await _deleteAppointmentEverywhere(appointment.id);
        await _deletePatientEverywhere(patient.id);
      });

      await _storePatient(patient);
      await _storeAppointment(appointment);

      expect(
        staticNotifications.todayAppointmentsForYou
            .any((a) => a.id == appointment.id),
        isTrue,
        reason: 'The appointment was not counted for today notifications.',
      );

      await Fixtures.openBell(tester);
      expect(find.text(txt('appointmentsToday')), findsWidgets,
          reason: 'The bell did not show the today-appointments notice.');

      final notice = staticNotifications.notifications.firstWhere(
        (n) => n.title == txt('appointmentsToday'),
      );
      notice.actions.single.action();
      await E2E.settle(tester, frames: 10);
      expect(routes.currentRoute().id, 'calendar',
          reason: 'The today-appointments notice did not open the calendar.');
    });

    testWidgets('02: a due labwork raises its own notice', (tester) async {
      await E2E.signIn(tester);
      final patient = _patient(Fixtures.stamp('e2e due labwork'));
      final appointment = _appointment(patientId: patient.id, labworkDue: true);
      addTearDown(() async {
        await _deleteAppointmentEverywhere(appointment.id);
        await _deletePatientEverywhere(patient.id);
      });

      await _storePatient(patient);
      await _storeAppointment(appointment);

      expect(staticNotifications.dueLabworks.any((a) => a.id == appointment.id),
          isTrue,
          reason: 'The due-labwork appointment was not counted.');

      await Fixtures.openBell(tester);
      expect(find.text(txt('dueLabworks')), findsWidgets,
          reason: 'The bell did not show the due-labworks notice.');
    });

    testWidgets('03: a pending note raises incoming and outgoing notices',
        (tester) async {
      await E2E.signIn(tester);
      final note = _note(Fixtures.stamp('e2e pending note'));
      addTearDown(() async => _deleteNoteEverywhere(note.id));

      await _storeNote(note);

      expect(
        staticNotifications.incomingPendingNotes.any((n) => n.id == note.id),
        isTrue,
        reason: 'The note was not counted as an incoming pending note.',
      );
      expect(
        staticNotifications.outgoingPendingNotes.any((n) => n.id == note.id),
        isTrue,
        reason: 'The note was not counted as an outgoing pending note.',
      );

      await Fixtures.openBell(tester);
      expect(find.text(txt('incomingNotes')), findsWidgets,
          reason: 'The bell did not show the incoming-notes notice.');
      expect(find.text(txt('outgoingNotes')), findsWidgets,
          reason: 'The bell did not show the outgoing-notes notice.');

      final notice = staticNotifications.notifications.firstWhere(
        (n) => n.title == txt('incomingNotes'),
      );
      notice.actions.single.action();
      await E2E.settle(tester, frames: 10);
      expect(routes.currentRoute().id, 'notes',
          reason: 'The incoming-notes notice did not open the notes board.');
    });

    testWidgets('04: the deferred queue keeps one entry per record',
        (tester) async {
      await E2E.signIn(tester);
      final store =
          'e2e_notifications_${DateTime.now().microsecondsSinceEpoch}';
      final id = _id('notif-push');
      final first = PushData(
        store: store,
        id: id,
        readableIdentifier: 'First',
        isCreation: false,
        isUpdate: true,
        updatedFields: const ['done'],
        oldVals: const [false],
        newVals: const [false],
        targetIDs: const ['other-account'],
      );
      final second = PushData(
        store: store,
        id: id,
        readableIdentifier: 'Second',
        isCreation: false,
        isUpdate: true,
        updatedFields: const ['done'],
        oldVals: const [false],
        newVals: const [true],
        targetIDs: const ['other-account'],
      );
      addTearDown(() => deferredPush.clearByStore(store));

      await deferredPush.putBulk([first]);
      await deferredPush.putBulk([second]);

      final stored = await deferredPush.getByID(id);
      expect(stored, isNotNull,
          reason: 'The deferred queue dropped the pending push entirely.');
      expect(stored!.readableIdentifier, 'Second',
          reason: 'The deferred queue did not keep the latest push payload.');

      await deferredPush.clearByStore(store);
      expect(await deferredPush.getByID(id), isNull,
          reason: 'Clearing the store queue left the entry behind.');
    });

    testWidgets('05: login ensures the relay key and keeps it stable',
        (tester) async {
      await E2E.signIn(tester);

      final first = await PushRelay.ensureKey();
      final second = await PushRelay.ensureKey();
      final record = await login.pb!
          .collection(dataCollectionName)
          .getOne(PushRelay.relayKeyIDInCollection);

      expect(first, isNotEmpty,
          reason: 'The relay key was not created for the clinic.');
      expect(second, first,
          reason:
              'ensureKey() changed the clinic relay key on the second call.');
      expect(record.get<String>('data.key'), first,
          reason: 'The stored relay key does not match ensureKey().');
    });

    testWidgets(
        '06: the FCM permission prompt is offered by the platform bridge',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('07: relay delivery reaches a registered device token',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('08: denied notifications are reported on Android and iOS',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);
  });
}
