import 'dart:convert';

import 'package:apexo/services/login.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

class PushRelay {
  static bool deviceIsPut = false;

  /// The client every relay call goes through: a test answers with a status
  /// instead of a real Worker.
  @visibleForTesting
  static http.Client client = http.Client();

  static const relayServer =
      "https://apexo-notifications-relay.alisaleem.workers.dev";
  static const relayKeyIDInCollection = "notifications_k";

  static Future<String?> _getRelayKey() async {
    try {
      final keyRecord = await login.pb!
          .collection(dataCollectionName)
          .getOne(relayKeyIDInCollection);
      return keyRecord.get<String>("data.key");
    } catch (e) {
      return null;
    }
  }

  /// This function ensures that a key specific to this server exists
  /// it tries to fetch it from the database, and if it doesn't exist, it creates it
  /// this function must be called right after a successful login occured
  static Future<String> ensureKey() async {
    final key = await _getRelayKey();
    if (key == null) {
      final String newKey = secureHash(
          "${login.url} ${login.token} ${login.email} ${DateTime.now().millisecondsSinceEpoch.toString()}");
      await login.pb!.collection(dataCollectionName).create(body: {
        "id": relayKeyIDInCollection,
        "data": jsonEncode({"key": newKey}),
      });
      return newKey;
    } else {
      return key;
    }
  }

  /// This function puts a new device into the relay database
  /// The server would add the token only if it doesn't exist
  static Future<void> putDevice({bool isPatient = false}) async {
    final relayKey = isPatient ? patientSide.relayKey : await _getRelayKey();
    final server = isPatient ? patientSide.server : login.url;
    final accountId = isPatient ? patientSide.patientID : login.currentAccountID;
    final token = login.pushNotificationsToken;
    if (relayKey == null ||
        relayKey.isEmpty ||
        server.isEmpty ||
        accountId.isEmpty ||
        token.isEmpty) {
      return;
    }

    final res = await client.post(
      Uri.parse('$relayServer/put-device'),
      body: jsonEncode({
        "clinicServer": server,
        "clinicKey": relayKey,
        "deviceToken": token,
        "accountId": accountId,
      }),
    );
    if (res.body == "ok") {
      deviceIsPut = true;
    }
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
      await putDevice(isPatient: isPatient);
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

          final http.Response res;
          try {
            res = await client.post(
              Uri.parse('$relayServer/push'),
              body: jsonEncode({
                "clinicServer": login.url,
                "clinicKey": relayKey,
                "accountIds": targets,
                "data": {"payload": jsonEncode(data.toJson())},
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
