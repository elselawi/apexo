import 'dart:convert';

import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/model_push_data.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:http/http.dart' as http;

class PushRelay {
  static bool deviceIsPut = false;

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
          "${login.url} ${login.token} ${login.email} ${login.password} ${DateTime.now().millisecondsSinceEpoch.toString()}");
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
  static Future<void> putDevice() async {
    final relayKey = await _getRelayKey();

    final res = await http.post(
      Uri.parse('$relayServer/put-device'),
      body: jsonEncode({
        "clinicServer": login.url,
        "clinicKey": relayKey,
        "deviceToken": login.pushNotificationsToken,
        "accountId": login.currentAccountID
      }),
    );
    if (res.body == "ok") {
      deviceIsPut = true;
    }
  }

  /// This function replaces an old token with a new one
  /// when FCM refreshes the token
  static Future<void> replaceToken(String oldToken, String newToken) async {
    final relayKey = await _getRelayKey();

    await http.post(
      Uri.parse('$relayServer/replace-token'),
      body: jsonEncode({
        "clinicServer": login.url,
        "clinicKey": relayKey,
        "oldToken": oldToken,
        "newToken": newToken,
      }),
    );
  }

  static Future<void> sendPush(List<PushData> bulkData) async {
    if (bulkData.isEmpty) return;

    final relayKey = await _getRelayKey();

    final requests = bulkData
        .map((p) {
          p.targetIDs.remove(login.currentAccountID);
          return p;
        })
        .where((p) => p.targetIDs.isNotEmpty)
        .map(
          (data) => http.post(
            Uri.parse('$relayServer/push'),
            body: jsonEncode({
              "clinicServer": login.url,
              "clinicKey": relayKey,
              "accountIds": data.targetIDs,
              "data": {"payload": jsonEncode(data.toJson())},
            }),
          ),
        );

    await Future.wait(requests);
  }
}
