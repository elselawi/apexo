@Tags(['serial'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/core_firebase_messaging.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late String originalURL;
  late String originalServer;
  late String originalPatientID;
  late String originalRelayKey;
  late String originalToken;
  late http.Client originalClient;
  late String? Function() originalResolver;
  late FirebaseMessagingService? originalFirebase;

  late List<http.Request> requests;

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  void signInPatient() {
    patientSide.server = 'https://clinic.test';
    patientSide.patientID = 'patient-1';
    patientSide.relayKey = 'clinic-key';
    login.pushNotificationsToken = 'device-token';
  }

  setUp(() {
    originalURL = login.url;
    originalServer = patientSide.server;
    originalPatientID = patientSide.patientID;
    originalRelayKey = patientSide.relayKey;
    originalToken = login.pushNotificationsToken;
    originalClient = PushRelay.client;
    originalResolver = PushPlatform.resolve;
    originalFirebase = Messaging.firebase;

    // The patient side needs no PocketBase session, so a registration here
    // never reaches a real server.
    login.url = '';
    login.email = '';
    signInPatient();
    PushRelay.deviceIsPut = false;

    requests = [];
    PushRelay.client = MockClient((request) async {
      requests.add(request);
      return http.Response('ok', 200);
    });

    PushPlatform.resolve = PushPlatform.detect;
    Messaging.firebase = null;
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() {
    login.url = originalURL;
    patientSide.server = originalServer;
    patientSide.patientID = originalPatientID;
    patientSide.relayKey = originalRelayKey;
    login.pushNotificationsToken = originalToken;
    PushRelay.client = originalClient;
    PushPlatform.resolve = originalResolver;
    Messaging.firebase = originalFirebase;
    PushRelay.deviceIsPut = false;
    debugDefaultTargetPlatformOverride = null;
  });

  group('putDevice platform', () {
    test('defaults to fcm for a caller that does not name a platform',
        () async {
      await PushRelay.putDevice(isPatient: true);

      expect(bodyOf(requests.single)['platform'], 'fcm');
    });

    test('omits the field entirely when the platform is unknown', () async {
      await PushRelay.putDevice(isPatient: true, platform: null);

      expect(bodyOf(requests.single).containsKey('platform'), isFalse,
          reason: 'a null platform must not be sent as null');
    });

    test('passes the platform through', () async {
      await PushRelay.putDevice(isPatient: true, platform: PushPlatform.wns);

      expect(bodyOf(requests.single)['platform'], 'wns');
      expect(bodyOf(requests.single)['deviceToken'], 'device-token');
    });
  });

  group('putDevice outcome', () {
    test('reports true only when the relay stored the device', () async {
      final accepted = await PushRelay.putDevice(isPatient: true);

      expect(accepted, isTrue);
      expect(PushRelay.deviceIsPut, isTrue);
    });

    test('reports false when the relay rejects the registration', () async {
      PushRelay.client = MockClient((request) async {
        requests.add(request);
        return http.Response('clinic key does not match', 400);
      });

      final accepted = await PushRelay.putDevice(isPatient: true);

      expect(accepted, isFalse);
      expect(PushRelay.deviceIsPut, isFalse,
          reason: 'a rejected device is not registered');
    });

    test('reports false when the relay answers 200 with something else',
        () async {
      PushRelay.client = MockClient((request) async {
        requests.add(request);
        return http.Response('ok but not really', 200);
      });

      expect(await PushRelay.putDevice(isPatient: true), isFalse);
    });

    test('reports false when there is nothing to register', () async {
      patientSide.patientID = '';

      expect(await PushRelay.putDevice(isPatient: true), isFalse);
      expect(requests, isEmpty);
    });
  });

  group('registerDeviceSnapshot', () {
    test('uses only the captured tuple and does not mutate global state',
        () async {
      final accepted = await PushRelay.registerDeviceSnapshot(
        clinicServer: 'https://captured.test',
        clinicKey: 'captured-key',
        deviceToken: 'captured-token',
        accountId: 'captured-account',
        platform: 'wns',
      );

      expect(accepted, isTrue);
      final body = bodyOf(requests.single);
      expect(body['clinicServer'], 'https://captured.test');
      expect(body['clinicKey'], 'captured-key');
      expect(body['deviceToken'], 'captured-token');
      expect(body['accountId'], 'captured-account');
      expect(body['platform'], 'wns');
      expect(PushRelay.deviceIsPut, isFalse,
          reason: 'the low-level helper leaves session state to its caller');
    });

    test('a hung request is bounded by the registration timeout', () async {
      final originalTimeout = PushRelay.registrationRequestTimeout;
      PushRelay.registrationRequestTimeout = const Duration(milliseconds: 20);
      addTearDown(() {
        PushRelay.registrationRequestTimeout = originalTimeout;
      });
      PushRelay.client = MockClient((request) async {
        requests.add(request);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('ok', 200);
      });

      await expectLater(
        PushRelay.registerDeviceSnapshot(
          clinicServer: 'https://captured.test',
          clinicKey: 'captured-key',
          deviceToken: 'captured-token',
          accountId: 'captured-account',
          platform: 'wns',
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('an incomplete tuple is not sent', () async {
      final accepted = await PushRelay.registerDeviceSnapshot(
        clinicServer: 'https://captured.test',
        clinicKey: '',
        deviceToken: 'captured-token',
        accountId: 'captured-account',
        platform: 'wns',
      );

      expect(accepted, isFalse);
      expect(requests, isEmpty);
    });
  });

  group('replaceToken', () {
    test('is unchanged: it replaces the token and sends no platform', () async {
      await PushRelay.replaceToken('old-token', 'new-token');

      final body = bodyOf(requests.single);
      expect(body['oldToken'], 'old-token');
      expect(body['newToken'], 'new-token');
      expect(body.containsKey('platform'), isFalse);
    });

    test('a missing old token registers this device with its platform',
        () async {
      PushPlatform.resolve = () => PushPlatform.android;

      await PushRelay.replaceToken('', 'new-token');

      expect(bodyOf(requests.single)['platform'], 'android');
    });
  });

  group('identifyDevice platform', () {
    void authorizeFcm() {
      Messaging.firebase = FirebaseMessagingService.instance()
        ..authStatus = AuthorizationStatus.authorized;
    }

    test('iOS sends "ios"', () async {
      authorizeFcm();
      PushPlatform.resolve = () => PushPlatform.ios;

      await Messaging.identifyDevice(isPatient: true);

      expect(bodyOf(requests.single)['platform'], 'ios');
    });

    test('macOS sends "macos"', () async {
      authorizeFcm();
      PushPlatform.resolve = () => PushPlatform.macos;

      await Messaging.identifyDevice(isPatient: true);

      expect(bodyOf(requests.single)['platform'], 'macos');
    });

    test('Android sends "android"', () async {
      authorizeFcm();
      PushPlatform.resolve = () => PushPlatform.android;

      await Messaging.identifyDevice(isPatient: true);

      expect(bodyOf(requests.single)['platform'], 'android');
    });

    test('an unknown platform omits the field instead of guessing', () async {
      authorizeFcm();
      PushPlatform.resolve = () => null;

      await Messaging.identifyDevice(isPatient: true);

      expect(bodyOf(requests.single).containsKey('platform'), isFalse);
    });

    test('web registers through the JS client, not through Dart', () async {
      authorizeFcm();
      PushPlatform.resolve = () => PushPlatform.web;

      await Messaging.identifyDevice(isPatient: true);

      expect(requests, isEmpty,
          reason: 'fcm.js posts /put-device with platform "web" itself');
    });

    test('Windows does not register an FCM token', () async {
      authorizeFcm();
      PushPlatform.resolve = () => PushPlatform.wns;

      await Messaging.identifyDevice(isPatient: true);

      expect(requests, isEmpty,
          reason: 'WNS registration is owned by the Windows push service');
    });

    test('a denied permission registers nothing', () async {
      Messaging.firebase = FirebaseMessagingService.instance()
        ..authStatus = AuthorizationStatus.denied;
      PushPlatform.resolve = () => PushPlatform.ios;

      await Messaging.identifyDevice(isPatient: true);

      expect(requests, isEmpty);
    });
  });

  group('Platform detection', () {
    test('each target platform maps to the relay value it must send', () {
      for (final entry in <TargetPlatform, String?>{
        TargetPlatform.android: PushPlatform.android,
        TargetPlatform.iOS: PushPlatform.ios,
        TargetPlatform.macOS: PushPlatform.macos,
        TargetPlatform.windows: PushPlatform.wns,
        TargetPlatform.linux: null,
        TargetPlatform.fuchsia: null,
      }.entries) {
        debugDefaultTargetPlatformOverride = entry.key;
        expect(PushPlatform.detect(), entry.value,
            reason: 'wrong relay platform for ${entry.key}');
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
