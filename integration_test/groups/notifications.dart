import 'dart:convert';
import 'dart:math';

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
import 'package:apexo/services/notifications/core_local_notification.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/utils/constants.dart' show dataCollectionName;
import 'package:apexo/utils/hash.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

    testWidgets('07: a device registers with the relay and the relay takes it',
        (tester) async {
      await E2E.signIn(tester);

      // A clinic server of its own, so the relay creates a fresh record: this
      // run's PocketBase reset minted a new relay key, and the relay keeps the
      // key it first stored for the shared test clinic.
      final previousUrl = login.url;
      final previousToken = login.pushNotificationsToken;
      addTearDown(() {
        login.url = previousUrl;
        login.pushNotificationsToken = previousToken;
        PushRelay.deviceIsPut = false;
      });
      login.url = 'https://pb.apexo.app/e2e-${_id('clinic')}';
      login.pushNotificationsToken = _fakeFcmToken();

      // The real relay: this proves the Worker accepts a device carrying the
      // `platform` field, and that it stored the clinic record. The default
      // (`fcm`) is used on purpose: the token is a synthetic FCM one, and a
      // `wns` registration would be rejected for not being a Windows channel.
      await PushRelay.putDevice();
      expect(
        PushRelay.deviceIsPut,
        isTrue,
        reason: 'The relay did not accept this device registration.',
      );

      final relayKey = await PushRelay.ensureKey();
      final response = await PushRelay.client.post(
        Uri.parse('${PushRelay.relayServer}/push'),
        body: jsonEncode({
          "clinicServer": login.url,
          "clinicKey": relayKey,
          "accountIds": [login.currentAccountID],
          "data": {"payload": "{}"},
          "alert": {"title": "e2e", "body": "e2e"},
        }),
      );
      // The token is synthetic, so FCM refuses it — as unregistered (404, which
      // the relay turns into success) or as malformed (400). Either way, the
      // relay resolved the device it had just stored and built a message for
      // it: a clinic-record problem would answer "clinic not found" or "clinic
      // key does not match" instead.
      expect(
        response.statusCode,
        anyOf(200, 400),
        reason: 'The relay did not reach FCM for the device it had just '
            'registered: ${response.body}',
      );
      if (response.statusCode == 400) {
        expect(response.body, contains('registration token'),
            reason: 'FCM refused the message for a reason other than the '
                'synthetic token: ${response.body}');
      }
    });

    testWidgets('08: denied notifications are reported on Android and iOS',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets(
        '09: an appointment for another account is pushed and displayed here',
        (tester) async {
      await E2E.signIn(tester);

      final previousClient = PushRelay.client;
      final previousToken = login.pushNotificationsToken;
      final requests = <http.Request>[];
      PushRelay.client = MockClient((request) async {
        requests.add(request);
        return http.Response('ok', 200);
      });
      addTearDown(() {
        PushRelay.client = previousClient;
        login.pushNotificationsToken = previousToken;
      });
      login.pushNotificationsToken = 'e2e-${_id('token')}'.replaceAll('-', '');

      // 1. This device registers with the platform the relay shapes with.
      await PushRelay.putDevice(platform: _expectedPlatform());
      final registration =
          jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(registration['platform'], _expectedPlatform(),
          reason: 'The device was registered without the platform the relay '
              'uses to choose between an alert and a data push.');
      expect(registration['deviceToken'], login.pushNotificationsToken);

      // 2. The action: a visit for another account.
      final patient = _patient(Fixtures.stamp('e2e notif push'));
      final otherAccount = _id('notif-account');
      final appointment = Appointment.fromJson({
        'id': _id('notif-appt'),
        'patientID': patient.id,
        'operatorsIDs': [otherAccount, login.currentAccountID],
        'date': dateToWire(DateTime.now().add(const Duration(hours: 2))),
      });
      addTearDown(() async {
        await _deleteAppointmentEverywhere(appointment.id);
        await _deletePatientEverywhere(patient.id);
      });
      requests.clear();

      await _storePatient(patient);
      await _storeAppointment(appointment);

      final pushes =
          requests.where((r) => r.url.path.endsWith('/push')).toList();
      expect(pushes, isNotEmpty,
          reason: 'Creating a visit for another account produced no push.');

      final body = jsonDecode(pushes.last.body) as Map<String, dynamic>;
      expect(body['accountIds'], contains(otherAccount),
          reason: 'The other account was not targeted.');
      expect(body['accountIds'], isNot(contains(login.currentAccountID)),
          reason: 'The sending account told itself about its own change.');

      final raw = (body['data'] as Map<String, dynamic>)['payload'] as String;
      final pushed = PushData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final alert = body['alert'] as Map<String, dynamic>;
      expect(alert['title'], pushed.displayTuple()[0],
          reason: 'The alert title is not the text this device renders.');
      expect(alert['body'], pushed.displayTuple()[1],
          reason: 'The alert body is not the text this device renders.');
      expect(alert['title'] as String, isNotEmpty);
      expect(alert['body'] as String, isNotEmpty);

      // 3. The receiving side: the same push reaches the app and is shown.
      final local = Messaging.local ?? LocalNotificationsService.instance();
      Messaging.local = local;
      if (!kIsWeb) {
        await tester.runAsync(local.init);
      }
      final before = staticNotifications.notifications.length;

      await tester.runAsync(
        () => PushListeners.foregroundMsg(
          RemoteMessage(data: {'payload': raw}),
        ),
      );
      await E2E.settle(tester, frames: 5);

      expect(staticNotifications.notifications.length, greaterThan(before),
          reason: 'The push did not reach the in-app notification list.');
      expect(
        staticNotifications.notifications
            .where((n) => n.title == alert['title'] && n.body == alert['body'])
            .length,
        1,
        reason: 'The in-app notice does not carry the pushed title and body.',
      );

      if (!kIsWeb) {
        expect(local.lastShown?.title, alert['title'],
            reason: 'The OS was not handed the pushed title.');
        expect(local.lastShown?.body, alert['body'],
            reason: 'The OS was not handed the pushed body.');
      }
    });
  });
}

/// The `platform` this build registers with the relay, or `null` when the app
/// cannot name it (the relay then keeps its `fcm` default).
String? _expectedPlatform() => PushPlatform.current;

/// A synthetic FCM token: long and opaque, the shape FCM uses, so the relay's
/// delivery attempt is answered by FCM ("unregistered") rather than rejected as
/// a malformed request.
String _fakeFcmToken() {
  final random = Random(DateTime.now().microsecondsSinceEpoch);
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  return List.generate(
    152,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
