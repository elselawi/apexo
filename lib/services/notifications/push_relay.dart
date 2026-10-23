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

  /// The client every relay call goes through: a test answers with a status
  /// instead of a real Worker.
  @visibleForTesting
  static http.Client client = http.Client();

  static const relayServer =
      "https://apexo-notifications-relay.alisaleem.workers.dev";
  static const relayKeyIDInCollection = "notifications_k";

  /// A background registration must not monopolize a refresh forever. The
  /// server may still finish an accepted request after this local timeout; the
  /// next bounded refresh is what reconciles that.
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

  /// This function ensures that a key specific to this server exists
  /// it tries to fetch it from the database, and if it doesn't exist, it creates it
  /// this function must be called right after a successful login occured
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

  /// Resolves the relay key using only values captured for [snapshot].
  ///
  /// This is deliberately not [ensureKey]: that method reads the mutable
  /// `login` globals, which can already describe the next account by the time a
  /// background registration resumes.
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
      // Another bounded attempt may have created it between the read and the
      // create. Re-read once rather than replacing a key that already exists.
      final raced = await _getRelayKeyFrom(pb);
      if (raced != null && raced.isNotEmpty) return raced;
      rethrow;
    }
  }

  /// This function puts a new device into the relay database
  /// The server would add the token only if it doesn't exist
  ///
  /// [platform] is the [PushPlatform] value recorded with the device, so the
  /// relay knows which transport to use and which OS to shape a push for. It
  /// defaults to the relay's backward-compatible [PushPlatform.fcm]; passing
  /// `null` (or an empty string) omits the field entirely rather than claiming
  /// a platform this build could not identify.
  ///
  /// Returns whether the relay accepted the device. A missing key, a rejected
  /// registration (`400`) or an unexpected reply all return `false` so the
  /// caller can retry: the relay answers `200 ok` only when the device is
  /// stored. Network failures still throw, as before.
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

  /// Registers one immutable device tuple.
  ///
  /// Unlike [putDevice], this helper never reads mutable login/patient globals
  /// and never changes [deviceIsPut]. The Windows service checks its snapshot
  /// before recording the result, so a request that belonged to a previous
  /// account cannot mutate the current one.
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

  /// This function replaces an old token with a new one
  /// when FCM refreshes the token
  static Future<void> replaceToken(String oldToken, String newToken) async {
    if (newToken.isEmpty || oldToken == newToken) return;
    final isPatient = login.url.isEmpty && patientSide.server.isNotEmpty;
    final relayKey = isPatient ? patientSide.relayKey : await _getRelayKey();
    final server = isPatient ? patientSide.server : login.url;
    if (relayKey == null || relayKey.isEmpty || server.isEmpty) return;
    if (oldToken.isEmpty) {
      // The first registration of this device: keep recording the OS, which
      // is what the relay uses to shape the push for this device.
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

  /// Sends [bulkData] to the relay, and reports what the relay said.
  ///
  /// Throws [PushRelayException] when a push was not accepted for a reason that
  /// may pass later — no relay key yet, a 5xx, a connection that died — so the
  /// caller keeps it queued. A 4xx is permanent (the relay will never take this
  /// payload), so it is logged and dropped rather than retried forever.
  static Future<void> sendPush(List<PushData> bulkData) async {
    if (bulkData.isEmpty) return;

    final relayKey = await _getRelayKey();
    if (relayKey == null) {
      // The key is minted at login: not having it yet is retryable, not a
      // reason to throw the push away.
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
          // A copy: a caller that queues this datum after a failure must still
          // hold the targets it computed.
          final targets = [
            for (final id in data.targetIDs)
              if (id != login.currentAccountID) id,
          ];
          if (targets.isEmpty) return;

          // Rendered here, in this device's language: the relay has no text of
          // its own, and attaches this to the iOS alert push.
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

/// Thrown when the relay could not take a push for a reason that may pass
/// later: the caller keeps the datum queued and retries on the next sync.
class PushRelayException implements Exception {
  PushRelayException(this.message);
  final String message;
  @override
  String toString() => 'PushRelayException: $message';
}
