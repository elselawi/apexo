import 'dart:convert';

import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

/// A push about a record this device changed, for [targets].
PushData pushFor(List<String> targets, {String id = 'appointment_01'}) =>
    PushData(
      store: 'appointments',
      id: id,
      readableIdentifier: 'Ada Lovelace',
      isCreation: false,
      isUpdate: true,
      updatedFields: const ['date'],
      oldVals: const [100],
      newVals: const [200],
      targetIDs: targets,
    );

void main() {
  late String originalEmail;
  late List<RecordModel> originalAccounts;

  /// Signs this device in as [accountId] — which is the account the relay must
  /// never be asked to notify about this device's own write.
  void signInAs(String accountId) {
    login.email = '$accountId@clinic.test';
    accounts.list([
      RecordModel({
        'id': accountId,
        'email': '$accountId@clinic.test',
        'name': accountId,
        'type': 'user',
      }),
    ]);
    expect(login.currentAccountID, accountId);
  }

  setUp(() {
    originalEmail = login.email;
    originalAccounts = accounts.list();
    login.url = 'https://clinic.test';
  });

  tearDown(() {
    PushRelay.client = http.Client();
    login.url = '';
    login.email = originalEmail;
    accounts.list(originalAccounts);
  });

  group('PushRelay constants', () {
    test('relayServer is set', () {
      expect(PushRelay.relayServer, isNotEmpty);
      expect(PushRelay.relayServer, contains('workers.dev'));
    });

    test('relayKeyIDInCollection is set', () {
      expect(PushRelay.relayKeyIDInCollection, isNotEmpty);
      expect(PushRelay.relayKeyIDInCollection, 'notifications_k');
    });
  });

  group('PushRelay device flag', () {
    test('deviceIsPut defaults to false', () {
      expect(PushRelay.deviceIsPut, isFalse);
    });

    test('deviceIsPut can be toggled', () {
      PushRelay.deviceIsPut = true;
      expect(PushRelay.deviceIsPut, isTrue);
      PushRelay.deviceIsPut = false;
      expect(PushRelay.deviceIsPut, isFalse);
    });
  });

  group('sendPush — what the relay answered', () {
    late List<http.Request> requests;

    setUp(() {
      requests = [];
      signInAs('me');
    });

    /// Answers every push with [status], recording the requests.
    void relaySays(int status) {
      PushRelay.client = MockClient((request) async {
        requests.add(request);
        return http.Response('attempted', status);
      });
    }

    test('a push the relay took is sent, without the sending account',
        () async {
      relaySays(200);

      await PushRelay.sendPushWithKey('clinic-key', [
        pushFor(['me', 'other']),
      ]);

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['clinicKey'], 'clinic-key');
      expect(body['accountIds'], ['other'],
          reason: 'the device that made the change told itself');
    });

    test('a push carries the rendered title and body for the iOS alert',
        () async {
      relaySays(200);
      final data = pushFor(['other']);

      await PushRelay.sendPushWithKey('clinic-key', [data]);

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final alert = body['alert'] as Map<String, dynamic>;
      expect(alert['title'], data.displayTuple()[0]);
      expect(alert['body'], data.displayTuple()[1]);
      expect(alert['title'], isNotEmpty);
      expect(alert['body'], isNotEmpty);
    });

    test('the caller\'s targets survive the send', () async {
      // The queue keeps the datum after a failure, so the relay's own filtering
      // must not be done in place on what the caller still holds.
      relaySays(200);
      final data = pushFor(['me', 'other']);

      await PushRelay.sendPushWithKey('clinic-key', [data]);

      expect(data.targetIDs, ['me', 'other']);
    });

    test('a push for nobody is no request at all', () async {
      relaySays(200);

      await PushRelay.sendPushWithKey('clinic-key', [
        pushFor(['me'])
      ]);

      expect(requests, isEmpty);
    });

    test('a 5xx is retryable', () async {
      relaySays(503);

      await expectLater(
        PushRelay.sendPushWithKey('clinic-key', [
          pushFor(['other'])
        ]),
        throwsA(isA<PushRelayException>()),
      );
    });

    test('a 4xx is permanent: the push is dropped, not retried forever',
        () async {
      relaySays(400);

      await PushRelay.sendPushWithKey('clinic-key', [
        pushFor(['other'])
      ]);
    });

    test('a dead connection is retryable', () async {
      PushRelay.client = MockClient(
        (_) async => throw http.ClientException('connection closed'),
      );

      await expectLater(
        PushRelay.sendPushWithKey('clinic-key', [
          pushFor(['other'])
        ]),
        throwsA(isA<PushRelayException>()),
      );
    });

    test('one refused push does not stop the others', () async {
      // A throw inside the batch would cancel the requests that were still in
      // flight, so every push must be attempted before anything is reported.
      PushRelay.client = MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return (body['accountIds'] as List).contains('flaky')
            ? http.Response('down', 500)
            : http.Response('ok', 200);
      });

      await expectLater(
        PushRelay.sendPushWithKey('clinic-key', [
          pushFor(['first'], id: 'appointment_01'),
          pushFor(['flaky'], id: 'appointment_02'),
          pushFor(['third'], id: 'appointment_03'),
        ]),
        throwsA(isA<PushRelayException>()),
      );

      expect(requests.length, 3);
    });
  });
}
