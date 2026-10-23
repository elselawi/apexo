@Tags(['serial'])
library;

import 'dart:convert';

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/services/perm.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// A push about an appointment, the same change a store announces.
PushData appointmentPush({String id = 'appt-1'}) => PushData.fromChange(
      store: 'appointments',
      id: id,
      readableIdentifier: 'Ada Lovelace',
      isCreation: false,
      changed: const ['date'],
      before: const {'date': 100},
      after: const {'date': 200},
      targets: const ['op1'],
    );

PushData notePush({String id = 'note-1'}) => PushData.fromChange(
      store: 'notes',
      id: id,
      readableIdentifier: 'Ada Lovelace',
      isCreation: true,
      changed: const ['title'],
      before: null,
      after: const {'title': 'Call back'},
      targets: const ['op1'],
    );

RemoteMessage messageFor(PushData data) => RemoteMessage(
      data: {'payload': jsonEncode(data.toJson())},
    );

void main() {
  late String originalToken;
  late List<int> originalPermissions;
  late bool originalOnline;
  late String originalPatientID;
  late Future<void> Function(String?, String?, String?) originalSink;
  late Future<void> Function()? originalPromote;
  late bool promoted;
  late List<String?> shown;

  setUp(() {
    originalToken = login.token;
    originalPermissions = login.savedPermissions;
    originalOnline = network.isOnline();
    originalPatientID = patientSide.patientID;
    originalSink = PushListeners.showLocalNotification;
    originalPromote = PushListeners.promoteWindowsInstanceIfApplicable;

    // A signed-in session, and every route reachable: navigation is what these
    // tests are about, and a route the session cannot open is a different
    // behaviour.
    login.token = 'test-token';
    login.savedPermissions = Perm.full;
    network.isOnline(false);
    patientSide.patientID = '';
    routes.reset();
    staticNotifications.clear();
    resetStaticNotificationDedupe();
    notificationSessions.invalidate();

    promoted = false;
    PushListeners.promoteWindowsInstanceIfApplicable = () async {
      promoted = true;
    };
    shown = [];
    PushListeners.showLocalNotification = (title, body, payload) async {
      shown.add(payload);
    };
  });

  tearDown(() {
    login.token = originalToken;
    login.savedPermissions = originalPermissions;
    network.isOnline(originalOnline);
    patientSide.patientID = originalPatientID;
    PushListeners.showLocalNotification = originalSink;
    PushListeners.promoteWindowsInstanceIfApplicable = originalPromote;
    notificationSessions.invalidate();
    routes.reset();
    staticNotifications.clear();
    resetStaticNotificationDedupe();
  });

  group('handlePushData', () {
    test('a foreground push syncs its store, adds a notice and shows it',
        () async {
      appointments.lastRes = null;

      await PushListeners.handlePushData(appointmentPush());

      expect(appointments.lastRes, isNotNull,
          reason: 'the store behind the notice was not synchronized');
      expect(shown, hasLength(1),
          reason: 'a foreground push must also be shown by the OS');
      final payload = jsonDecode(shown.single!) as Map<String, dynamic>;
      expect(payload['store'], 'appointments');
      expect(payload['id'], 'appt-1');
      expect(staticNotifications.notifications, hasLength(1));
      expect(routes.currentRoute(), AppRoute.dashboard,
          reason: 'a foreground push does not move the app');
    });

    test('a notes push syncs the notes store', () async {
      notes.lastRes = null;

      await PushListeners.handlePushData(notePush());

      expect(notes.lastRes, isNotNull);
    });

    test('a notification-open navigates and does not show a second notice',
        () async {
      await PushListeners.handlePushData(notePush(),
          openedFromNotification: true);

      expect(shown, isEmpty,
          reason: 'the OS notification the user tapped is the notice');
      expect(staticNotifications.notifications, hasLength(1));
      expect(routes.currentRoute(), AppRoute.notes);
    });

    test('an appointment open lands on the calendar', () async {
      await PushListeners.handlePushData(
        appointmentPush(),
        openedFromNotification: true,
      );

      expect(routes.currentRoute(), AppRoute.calendar);
    });

    test('a store with no screen does not navigate', () async {
      final push = PushData.fromChange(
        store: 'patients',
        id: 'patient-1',
        readableIdentifier: 'Ada Lovelace',
        isCreation: false,
        changed: const ['name'],
        before: const {'name': 'Ada'},
        after: const {'name': 'Ada Lovelace'},
        targets: const ['op1'],
      );

      await PushListeners.handlePushData(push, openedFromNotification: true);

      expect(routes.currentRoute(), AppRoute.dashboard);
    });

    test('a push with no session is ignored', () async {
      login.token = '';
      patientSide.patientID = '';

      await PushListeners.handlePushData(appointmentPush());

      expect(staticNotifications.notifications, isEmpty);
      expect(shown, isEmpty);
      expect(routes.currentRoute(), AppRoute.dashboard);
    });
  });

  group('transport entry points', () {
    test('foregroundMsg delegates to the foreground behaviour', () async {
      await PushListeners.foregroundMsg(messageFor(appointmentPush()));

      expect(shown, hasLength(1));
      expect(routes.currentRoute(), AppRoute.dashboard);
    });

    test('causedTheAppToOpen delegates to the notification-open behaviour',
        () async {
      await PushListeners.causedTheAppToOpen(messageFor(notePush()));

      expect(shown, isEmpty);
      expect(routes.currentRoute(), AppRoute.notes);
    });

    test('a malformed message is ignored by both entry points', () async {
      await PushListeners.foregroundMsg(
        const RemoteMessage(data: {'payload': '{bad'}),
      );
      await PushListeners.causedTheAppToOpen(const RemoteMessage());

      expect(staticNotifications.notifications, isEmpty);
      expect(shown, isEmpty);
    });
  });

  group('transport-neutral payload parsing', () {
    test('pushPayloadOfData reads the data map the relay sends', () {
      final data = appointmentPush();
      final raw = jsonEncode(data.toJson());

      final parsed = pushPayloadOfData({'payload': raw});

      expect(parsed, isNotNull);
      expect(parsed!.raw, raw);
      expect(parsed.data.store, 'appointments');
      expect(parsed.data.id, 'appt-1');
    });

    test('pushPayloadOfData rejects missing, empty and non-string payloads',
        () {
      expect(pushPayloadOfData(null), isNull);
      expect(pushPayloadOfData(const {}), isNull);
      expect(pushPayloadOfData(const {'payload': ''}), isNull);
      expect(pushPayloadOfData(const {'payload': 42}), isNull);
      expect(pushPayloadOfData(const {'payload': '{bad'}), isNull);
      expect(pushPayloadOfData(const {'payload': '[]'}), isNull);
    });

    test('tryParsePushEnvelope reads the string envelope of a transport', () {
      final raw = jsonEncode(appointmentPush().toJson());
      final envelope = jsonEncode({'payload': raw});

      final parsed = tryParsePushEnvelope(envelope);

      expect(parsed, isNotNull);
      expect(parsed!.raw, raw);
      expect(parsed.data.id, 'appt-1');
    });

    test('tryParsePushEnvelope rejects malformed envelopes', () {
      expect(tryParsePushEnvelope(null), isNull);
      expect(tryParsePushEnvelope(''), isNull);
      expect(tryParsePushEnvelope('not-json'), isNull);
      expect(tryParsePushEnvelope('[]'), isNull);
      expect(tryParsePushEnvelope('{}'), isNull);
      expect(tryParsePushEnvelope(jsonEncode({'payload': ''})), isNull);
      expect(tryParsePushEnvelope(jsonEncode({'payload': 'nope'})), isNull);
    });
  });

  group('local toast clicks', () {
    NotificationResponse responseFor(PushData data) => NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: jsonEncode(data.toJson()),
        );

    void publishStaffSession() {
      notificationSessions.publishStaff(
        server: 'https://clinic.test',
        accountId: 'account-1',
        pocketBase: null,
        authToken: 'test-token',
        email: 'test@example.com',
      );
    }

    test('a click promotes the window, waits for the session and navigates',
        () async {
      publishStaffSession();

      await PushListeners.handleLocalNotificationClick(
        responseFor(notePush()),
      );

      expect(promoted, isTrue);
      expect(shown, isEmpty,
          reason: 'the tapped toast is the notice; do not post another');
      expect(routes.currentRoute(), AppRoute.notes);
    });

    test('a cold click is retained until the session becomes usable', () async {
      login.token = '';
      notificationSessions.beginRestoring();
      final click = PushListeners.handleLocalNotificationClick(
        responseFor(appointmentPush()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(routes.currentRoute(), AppRoute.dashboard,
          reason: 'no store work may run before the session is ready');

      login.token = 'test-token';
      publishStaffSession();
      await click;

      expect(promoted, isTrue);
      expect(routes.currentRoute(), AppRoute.calendar);
    });

    test('a malformed local payload is ignored', () async {
      publishStaffSession();

      await PushListeners.handleLocalNotificationClick(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{bad',
        ),
      );

      expect(promoted, isTrue,
          reason: 'the window is promoted even when the payload is unusable');
      expect(routes.currentRoute(), AppRoute.dashboard);
    });
  });
}
