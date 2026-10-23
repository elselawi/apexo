@Tags(['serial'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/services/notifications/windows_push.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const MethodChannel _methodChannel =
    MethodChannel(WindowsPushService.methodChannelName);
const EventChannel _eventChannel =
    EventChannel(WindowsPushService.eventChannelName);
const MethodChannel _lifecycleChannel =
    MethodChannel(WindowsPushService.lifecycleChannelName);

const String _channelA = 'https://a.notify.windows.com/chan-a';
const String _channelB = 'https://b.notify.windows.com/chan-b';

/// The envelope a transport hands to the app: `{"payload": "<PushData JSON>"}`.
String envelopeFor({String id = 'appt-1'}) {
  final data = PushData.fromJson({
    'store': 'appointments',
    'id': id,
    'readableIdentifier': 'Ada Lovelace',
    'isCreation': false,
    'isUpdate': true,
    'updatedFields': ['date'],
    'oldVals': [100],
    'newVals': [200],
    'targetIDs': ['op1'],
  });
  return jsonEncode({'payload': jsonEncode(data.toJson())});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationSessionCoordinator sessions;
  late String originalToken;
  late http.Client originalClient;
  late Duration originalRegistrationTimeout;

  late List<http.Request> requests;
  late List<PushData> handled;
  late List<bool> opened;
  late List<String> lifecycleMethods;
  late List<MethodCall> methodCalls;
  late int listens;
  MockStreamHandlerEventSink? sink;
  String? launchPayload;
  Future<String?> Function()? launchAnswer;
  String? channelUri;
  Future<String?> Function(int call)? channelHandler;
  int channelCalls = 0;
  bool supported = true;
  bool methodChannelPresent = true;

  WindowsPushService newService({
    Future<void> Function(Duration)? sleep,
    Duration periodicRefreshInterval = const Duration(hours: 6),
    Future<void> Function(
      PushData data, {
      required bool openedFromNotification,
    })? handler,
  }) =>
      WindowsPushService(
        sessions: sessions,
        // Backoff is exercised in the retry group; everywhere else it must not
        // slow a test down.
        sleep: sleep ?? ((_) async {}),
        periodicRefreshInterval: periodicRefreshInterval,
        sessionWaitTimeout: const Duration(milliseconds: 500),
        onPushData: handler ??
            (data, {required openedFromNotification}) async {
              handled.add(data);
              opened.add(openedFromNotification);
            },
      );

  Future<void> settle({int turns = 60}) async {
    for (var index = 0; index < turns; index++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> waitFor(
    bool Function() condition, {
    int turns = 300,
    Duration step = const Duration(milliseconds: 5),
  }) async {
    for (var index = 0; index < turns; index++) {
      if (condition()) return;
      await Future<void>.delayed(step);
    }
    fail('condition was not met within the test bound');
  }

  void signInPatient({String id = 'patient-1'}) {
    sessions.publishPatient(
      server: 'https://clinic.test',
      accountId: id,
      clinicKey: 'clinic-key',
    );
  }

  void mockNative() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _methodChannel,
      methodChannelPresent
          ? (call) async {
              methodCalls.add(call);
              switch (call.method) {
                case 'isSupported':
                  return supported;
                case 'getChannelUri':
                  channelCalls++;
                  final handler = channelHandler;
                  if (handler != null) return handler(channelCalls);
                  return channelUri;
                case 'getLaunchPayload':
                  final answer = launchAnswer;
                  return answer != null ? await answer() : launchPayload;
                default:
                  return null;
              }
            }
          : null,
    );
  }

  void mockLifecycle({bool present = true}) {
    lifecycleMethods = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _lifecycleChannel,
      present
          ? (call) async {
              lifecycleMethods.add(call.method);
              return true;
            }
          : null,
    );
  }

  void mockEvents({bool present = true}) {
    listens = 0;
    sink = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      _eventChannel,
      present
          ? MockStreamHandler.inline(
              onListen: (arguments, events) {
                listens++;
                sink = events;
              },
            )
          : null,
    );
  }

  setUp(() {
    originalToken = login.pushNotificationsToken;
    originalClient = PushRelay.client;
    originalRegistrationTimeout = PushRelay.registrationRequestTimeout;

    login.pushNotificationsToken = '';
    PushRelay.deviceIsPut = false;
    sessions = NotificationSessionCoordinator(
      waitTimeout: const Duration(milliseconds: 500),
    );

    requests = [];
    handled = [];
    opened = [];
    lifecycleMethods = [];
    methodCalls = [];
    channelCalls = 0;
    PushRelay.client = MockClient((request) async {
      requests.add(request);
      return http.Response('ok', 200);
    });
    PushRelay.registrationRequestTimeout = const Duration(milliseconds: 250);

    supported = true;
    methodChannelPresent = true;
    channelUri = _channelA;
    channelHandler = null;
    launchPayload = null;
    launchAnswer = null;
    mockNative();
    mockEvents();
    mockLifecycle();
  });

  tearDown(() {
    login.pushNotificationsToken = originalToken;
    PushRelay.client = originalClient;
    PushRelay.registrationRequestTimeout = originalRegistrationTimeout;
    PushRelay.deviceIsPut = false;
    sessions.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_eventChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_lifecycleChannel, null);
  });

  group('receiving and dispatch', () {
    test('an unsupported build receives nothing', () async {
      supported = false;
      final service = newService();
      addTearDown(service.resetForTesting);

      await service.startReceiving();

      expect(listens, 0);
      expect(requests, isEmpty);
    });

    test('a stream push dispatches as a display event, never a click',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);
      await waitFor(() => lifecycleMethods.contains('exitAfterPush'));
      lifecycleMethods.clear();

      sink!.success(envelopeFor());
      await waitFor(() => handled.isNotEmpty);

      expect(handled.single.id, 'appt-1');
      expect(opened.single, isFalse);
      expect(lifecycleMethods, isEmpty,
          reason: 'a foreground push must not end the process');
    });

    test('a raw launch payload displays a toast instead of navigating',
        () async {
      launchPayload = envelopeFor(id: 'appt-launch');
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);

      await waitFor(() => handled.isNotEmpty);
      await waitFor(() => lifecycleMethods.contains('exitAfterPush'));

      expect(handled.single.id, 'appt-launch');
      expect(opened.single, isFalse,
          reason: 'raw WNS delivery is not a user click');
    });

    test('a launch echoed on the stream is handled once', () async {
      final raw = envelopeFor(id: 'appt-launch');
      launchPayload = raw;
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => handled.isNotEmpty);

      sink!.success(raw);
      await settle();

      expect(handled, hasLength(1));
      expect(opened.single, isFalse);
    });

    test('a stream event that wins the launch race is not repeated', () async {
      final raw = envelopeFor(id: 'appt-race');
      final answer = Completer<String?>();
      launchAnswer = () => answer.future;
      final service = newService();
      addTearDown(service.resetForTesting);

      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      sink!.success(raw);
      await waitFor(() => handled.isNotEmpty);

      answer.complete(raw);
      await waitFor(() => lifecycleMethods.contains('exitAfterPush'));

      expect(handled, hasLength(1),
          reason: 'one activation must not become two notifications');
      expect(opened.single, isFalse);
    });

    test('two identical stream-only pushes are both dispatched', () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);
      final raw = envelopeFor(id: 'appt-repeat');

      sink!.success(raw);
      await settle();
      sink!.success(raw);
      await waitFor(() => handled.length == 2);

      expect(handled, hasLength(2),
          reason: 'identical content is not proof of a duplicate event');
    });

    test('a push waits for the session boundary instead of being dropped',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      sink!.success(envelopeFor());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handled, isEmpty);

      signInPatient();
      await waitFor(() => handled.isNotEmpty);
      expect(opened.single, isFalse);
    });

    test('an absent session drops the push without hanging', () async {
      sessions.markAbsent();
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      sink!.success(envelopeFor());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handled, isEmpty);
    });

    test('a stream error does not stop later pushes', () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);
      await waitFor(() => lifecycleMethods.contains('exitAfterPush'));
      lifecycleMethods.clear();

      sink!.error(code: 'channel', message: 'boom');
      await settle();
      sink!.success(envelopeFor());
      await waitFor(() => handled.isNotEmpty);

      expect(handled, hasLength(1));
    });

    test('malformed and non-string events are ignored', () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);

      sink!.success('not-json');
      sink!.success('[]');
      sink!.success(jsonEncode({'payload': 'nope'}));
      sink!.success(42);
      await settle();

      expect(handled, isEmpty);
    });
  });

  group('completion before acknowledgement', () {
    test('the launch exit waits for the display work and consumes one echo',
        () async {
      final raw = envelopeFor(id: 'appt-slow');
      final display = Completer<void>();
      final service =
          newService(handler: (data, {required openedFromNotification}) async {
        handled.add(data);
        opened.add(openedFromNotification);
        await display.future;
      });
      addTearDown(service.resetForTesting);
      launchPayload = raw;

      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => handled.isNotEmpty);

      // The stream counterpart arrives while the launch's display is pending.
      sink!.success(raw);
      await settle();
      expect(lifecycleMethods, isEmpty,
          reason: 'exit must not be acknowledged before display completes');

      display.complete();
      await waitFor(() => lifecycleMethods.contains('exitAfterPush'));
      expect(handled, hasLength(1));

      // The one mirrored stream event was consumed; a later identical push is
      // a new event and must still display.
      sink!.success(raw);
      await waitFor(() => handled.length == 2);
    });

    test('the stream-first path also waits for its paired processing',
        () async {
      final raw = envelopeFor(id: 'appt-slow-stream');
      final answer = Completer<String?>();
      final display = Completer<void>();
      launchAnswer = () => answer.future;
      final service =
          newService(handler: (data, {required openedFromNotification}) async {
        handled.add(data);
        opened.add(openedFromNotification);
        await display.future;
      });
      addTearDown(service.resetForTesting);

      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      sink!.success(raw);
      await waitFor(() => handled.isNotEmpty);

      answer.complete(raw);
      await settle();
      expect(lifecycleMethods, isEmpty);

      display.complete();
      await waitFor(() => lifecycleMethods.contains('exitAfterPush'));
      expect(handled, hasLength(1));
    });
  });

  group('registration', () {
    test('a signed-in patient registers one WNS device in the background',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);

      await waitFor(() => requests.isNotEmpty);

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['platform'], 'wns');
      expect(body['deviceToken'], _channelA);
      expect(body['accountId'], 'patient-1');
      expect(body['clinicServer'], 'https://clinic.test');
      expect(login.pushNotificationsToken, _channelA);
      expect(PushRelay.deviceIsPut, isTrue);
    });

    test('the initial channel read asks for a lookup, not a forced refresh',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);

      final call =
          methodCalls.lastWhere((call) => call.method == 'getChannelUri');
      expect(call.arguments, {'refresh': false});
    });

    test('an unchanged registration is not sent twice', () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);

      service.requestRegistration(isPatient: true);
      await settle();

      expect(requests, hasLength(1));
    });

    test('a resume asks WNS for a fresh channel and registers the replacement',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);
      methodCalls.clear();

      channelUri = _channelB;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await waitFor(() => requests.length == 2);

      final call =
          methodCalls.lastWhere((call) => call.method == 'getChannelUri');
      expect(call.arguments, {'refresh': true});
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['deviceToken'], _channelB);
      expect(login.pushNotificationsToken, _channelB);
    });

    test('a forced refresh that returns the same URI does not re-register',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await waitFor(
        () =>
            methodCalls
                .where((call) => call.method == 'getChannelUri')
                .length >=
            2,
      );
      await settle();

      expect(requests, hasLength(1),
          reason: 'the same URI and context need no relay POST');
    });

    test('the periodic check also performs a real forced refresh', () async {
      final service = newService(
        periodicRefreshInterval: const Duration(milliseconds: 30),
      );
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => requests.isNotEmpty);
      methodCalls.clear();

      channelUri = _channelB;
      await waitFor(() => requests.length == 2);

      final call =
          methodCalls.lastWhere((call) => call.method == 'getChannelUri');
      expect(call.arguments, {'refresh': true});
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['deviceToken'], _channelB);
    });

    test('a channel that is not ready is retried', () async {
      final gate = Completer<void>();
      Future<void> sleep(Duration _) => gate.future;
      channelUri = null;
      final service = newService(sleep: sleep);
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => channelCalls >= 1);
      expect(requests, isEmpty);

      channelUri = _channelA;
      gate.complete();
      await waitFor(() => requests.isNotEmpty);
      expect(login.pushNotificationsToken, _channelA);
    });

    test(
        'a session switch during a held channel read cannot register session A',
        () async {
      final first = Completer<String?>();
      final second = Completer<String?>();
      channelHandler = (call) => call == 1 ? first.future : second.future;
      final service = newService();
      addTearDown(service.resetForTesting);

      await service.startReceiving();
      signInPatient(id: 'patient-a');
      service.requestRegistration(isPatient: true);
      await waitFor(() => channelCalls == 1);

      // Account switch while the first native read is still pending.
      sessions.invalidate();
      signInPatient(id: 'patient-b');
      service.requestRegistration(isPatient: true);

      first.complete(_channelA);
      await settle();
      expect(requests, isEmpty,
          reason: 'the stale session must not register its channel');

      second.complete(_channelB);
      await waitFor(() => requests.isNotEmpty);
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['accountId'], 'patient-b');
      expect(body['deviceToken'], _channelB);
      expect(login.pushNotificationsToken, _channelB);
    });

    test('logging out during a retry sleep cancels the retry', () async {
      final gate = Completer<void>();
      Future<void> sleep(Duration _) => gate.future;
      channelUri = null;
      final service = newService(sleep: sleep);
      addTearDown(service.resetForTesting);
      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);
      await waitFor(() => channelCalls >= 1);

      sessions.invalidate();
      channelUri = _channelA;
      gate.complete();
      await settle();

      expect(requests, isEmpty);
    });
  });

  group('lifecycle', () {
    test('promoting a hidden instance calls the native lifecycle method',
        () async {
      final service = newService();
      addTearDown(service.resetForTesting);

      await service.promoteToInteractive();

      expect(lifecycleMethods, ['promoteToInteractive']);
    });

    test('a missing lifecycle channel does not break a launch payload',
        () async {
      mockLifecycle(present: false);
      launchPayload = envelopeFor(id: 'appt-launch');
      final service = newService();
      addTearDown(service.resetForTesting);

      await service.startReceiving();
      signInPatient();
      service.requestRegistration(isPatient: true);

      await waitFor(() => handled.isNotEmpty);
      expect(handled.single.id, 'appt-launch');
    });
  });
}
