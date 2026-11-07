import 'dart:convert';

import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

class PushRelay {
  static bool deviceIsPut = false;

  @visibleForTesting
  static http.Client client = http.Client();

  static const relayServer =
      "https://apexo-notifications-relay.alisaleem.workers.dev";
  static const relayKeyIDInCollection = "notifications_k";

  /// Bounds a background registration; the server may still finish an accepted
  /// request, and the next bounded refresh reconciles it.
  @visibleForTesting
  static Duration registrationRequestTimeout = const Duration(seconds: 20);

  static Future<String?> _getRelayKey() async {
    final pb = login.pb;
    if (pb == null) return null;
    return _getRelayKeyFrom(pb);
  }

  static Future<String?> _getRelayKeyFrom(PocketBase pb) async {
    try {
      final keyRecord = await pb
          .collection(dataCollectionName)
          .getOne(relayKeyIDInCollection)
          .timeout(registrationRequestTimeout);
      return keyRecord.get<String>("data.key");
    } catch (e) {
      return null;
    }
  }

  static Future<String> ensureKey() async {
    final pb = login.pb;
    if (pb == null) {
      throw StateError(
          'No PocketBase connection is available for the relay key.');
    }
    final key = await _getRelayKeyFrom(pb);
    if (key != null && key.isNotEmpty) return key;
    return _createRelayKey(
      pb: pb,
      server: login.url,
      authToken: login.token,
      email: login.email,
    );
  }

  /// Uses only [snapshot] values: `ensureKey` reads mutable `login` globals,
  /// which may already describe the next account on a resumed registration.
  static Future<String?> ensureKeyForSnapshot(
    NotificationSessionSnapshot snapshot,
  ) async {
    if (snapshot.isPatient) {
      final key = snapshot.clinicKey;
      return key == null || key.isEmpty ? null : key;
    }
    final pb = snapshot.pocketBase;
    if (pb == null || snapshot.authToken.isEmpty) return null;
    final existing = await _getRelayKeyFrom(pb);
    if (existing != null && existing.isNotEmpty) return existing;
    return _createRelayKey(
      pb: pb,
      server: snapshot.server,
      authToken: snapshot.authToken,
      email: snapshot.email,
    );
  }

  static Future<String> _createRelayKey({
    required PocketBase pb,
    required String server,
    required String authToken,
    required String email,
  }) async {
    final String newKey = secureHash(
        "$server $authToken $email ${DateTime.now().millisecondsSinceEpoch.toString()}");
    try {
      await pb.collection(dataCollectionName).create(body: {
        "id": relayKeyIDInCollection,
        "data": jsonEncode({"key": newKey}),
      }).timeout(registrationRequestTimeout);
      return newKey;
    } catch (_) {
      // Another attempt may have created it between read and create; re-read
      // once instead of replacing a key that already exists.
      final raced = await _getRelayKeyFrom(pb);
      if (raced != null && raced.isNotEmpty) return raced;
      rethrow;
    }
  }

  /// [platform] defaults to [PushPlatform.fcm]; `null` or empty omits the field.
  /// Returns false unless the relay answers `200 ok`; network failures throw.
  static Future<bool> putDevice({
    bool isPatient = false,
    String? platform = PushPlatform.fcm,
  }) async {
    final relayKey = isPatient ? patientSide.relayKey : await _getRelayKey();
    final server = isPatient ? patientSide.server : login.url;
    final accountId =
        isPatient ? patientSide.patientID : login.currentAccountID;
    final token = login.pushNotificationsToken;
    final accepted = await registerDeviceSnapshot(
      clinicServer: server,
      clinicKey: relayKey ?? '',
      deviceToken: token,
      accountId: accountId,
      platform: platform,
    );
    if (accepted) deviceIsPut = true;
    return accepted;
  }

  /// Never reads mutable login/patient globals or sets [deviceIsPut]; the caller
  /// re-checks its snapshot so a stale request cannot mutate current state.
  static Future<bool> registerDeviceSnapshot({
    required String clinicServer,
    required String clinicKey,
    required String deviceToken,
    required String accountId,
    required String? platform,
  }) async {
    if ([clinicServer, clinicKey, deviceToken, accountId]
        .any((value) => value.isEmpty)) {
      return false;
    }
    final response = await client
        .post(
          Uri.parse('$relayServer/put-device'),
          body: jsonEncode({
            "clinicServer": clinicServer,
            "clinicKey": clinicKey,
            "deviceToken": deviceToken,
            "accountId": accountId,
            if (platform != null && platform.isNotEmpty) "platform": platform,
          }),
        )
        .timeout(registrationRequestTimeout);
    return response.statusCode == 200 && response.body == "ok";
  }

  static Future<void> replaceToken(String oldToken, String newToken) async {
    if (newToken.isEmpty || oldToken == newToken) return;
    final isPatient = login.url.isEmpty && patientSide.server.isNotEmpty;
    final relayKey = isPatient ? patientSide.relayKey : await _getRelayKey();
    final server = isPatient ? patientSide.server : login.url;
    if (relayKey == null || relayKey.isEmpty || server.isEmpty) return;
    if (oldToken.isEmpty) {
      // First registration: record the OS, which the relay uses to shape this
      // device's push.
      await putDevice(isPatient: isPatient, platform: PushPlatform.current);
      return;
    }

    await client.post(
      Uri.parse('$relayServer/replace-token'),
      body: jsonEncode({
        "clinicServer": server,
        "clinicKey": relayKey,
        "oldToken": oldToken,
        "newToken": newToken,
      }),
    );
  }

  /// Throws [PushRelayException] for retryable failures (missing key, 5xx,
  /// connection death) so the caller keeps the datum queued; a 4xx is dropped.
  static Future<void> sendPush(List<PushData> bulkData) async {
    if (bulkData.isEmpty) return;

    final relayKey = await _getRelayKey();
    if (relayKey == null) {
      // The key is minted at login, so a missing one is retryable, not a reason
      // to drop the push.
      throw PushRelayException('the clinic has no relay key yet');
    }
    await sendPushWithKey(relayKey, bulkData);
  }

  /// [sendPush] with the key already in hand: the seam a test drives.
  @visibleForTesting
  static Future<void> sendPushWithKey(
    String relayKey,
    List<PushData> bulkData,
  ) async {
    if (bulkData.isEmpty) return;

    final rejected = <String>[];

    await Future.wait([
      for (final data in bulkData)
        () async {
          final targets = [
            for (final id in data.targetIDs)
              if (id != login.currentAccountID) id,
          ];
          if (targets.isEmpty) return;

          // Rendered here in this device's language: the relay has no text and
          // attaches this alert to the iOS push.
          final List<String> alert;
          final http.Response res;
          try {
            alert = data.displayTuple();
            res = await client.post(
              Uri.parse('$relayServer/push'),
              body: jsonEncode({
                "clinicServer": login.url,
                "clinicKey": relayKey,
                "accountIds": targets,
                "data": {"payload": jsonEncode(data.toJson())},
                "alert": {"title": alert[0], "body": alert[1]},
              }),
            );
          } catch (e) {
            rejected.add('${data.store}/${data.id}: $e');
            return;
          }

          if (res.statusCode >= 200 && res.statusCode < 300) return;
          if (res.statusCode < 500) {
            logger(
              'The relay refused a push for ${data.store}/${data.id} '
              '(${res.statusCode}) — dropped, not queued: ${res.body}',
              null,
              3,
            );
            return;
          }
          rejected.add('${data.store}/${data.id}: ${res.statusCode}');
        }(),
    ]);

    if (rejected.isNotEmpty) {
      throw PushRelayException(
        '${rejected.length} push(es) not accepted: ${rejected.join('; ')}',
      );
    }
  }
}

/// A retryable relay rejection: the caller keeps the datum queued and retries
/// on the next sync.
class PushRelayException implements Exception {
  PushRelayException(this.message);
  final String message;
  @override
  String toString() => 'PushRelayException: $message';
}
