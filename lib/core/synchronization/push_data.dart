/// Push payload wire shape. The JSON below is mirrored by `web/fcm/push_data.js`
/// (web app + service worker): a field added, renamed or removed here must be
/// changed there too.
library;

/// One notice payload; FCM carries it as a JSON string.
class PushData {
  PushData({
    required this.store,
    required this.id,
    required this.readableIdentifier,
    required this.isCreation,
    required this.isUpdate,
    required this.updatedFields,
    required this.oldVals,
    required this.newVals,
    required this.targetIDs,
  });

  factory PushData.fromJson(Map<String, dynamic> json) {
    return PushData(
      store: (json["store"] as String?) ?? "",
      id: (json["id"] as String?) ?? "",
      readableIdentifier: (json["readableIdentifier"] as String?) ?? "",
      isCreation: (json["isCreation"] as bool?) ?? false,
      isUpdate: (json["isUpdate"] as bool?) ?? false,
      updatedFields: List<String>.from(
        (json["updatedFields"] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString()),
      ),
      oldVals: List<dynamic>.from(
        json["oldVals"] as List<dynamic>? ?? const <dynamic>[],
      ),
      newVals: List<dynamic>.from(
        json["newVals"] as List<dynamic>? ?? const <dynamic>[],
      ),
      targetIDs: List<String>.from(
        (json["targetIDs"] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString()),
      ),
    );
  }

  /// Builds the payload for one store change. [oldVals]/[newVals] are parallel to
  /// [changed]; [before] is null for a creation.
  factory PushData.fromChange({
    required String store,
    required String id,
    required String readableIdentifier,
    required bool isCreation,
    required List<String> changed,
    required Map<String, Object?>? before,
    required Map<String, Object?> after,
    required List<String> targets,
  }) =>
      PushData(
        store: store,
        id: id,
        readableIdentifier: readableIdentifier,
        isCreation: isCreation,
        isUpdate: !isCreation,
        updatedFields: changed,
        oldVals: [for (final field in changed) before?[field]],
        newVals: [for (final field in changed) after[field]],
        targetIDs: targets,
      );

  final String store;
  final String id;
  final String readableIdentifier;
  final List<String> targetIDs;
  final bool isCreation;
  final bool isUpdate;
  final List<String> updatedFields;
  final List<dynamic> oldVals;
  final List<dynamic> newVals;

  /// Set once an uninterpretable payload has been reported, so repeated
  /// `displayTuple()` calls log it only once. Public because Dart privacy is
  /// per-library and the diagnosis lives in another file.
  bool uninterpretableReported = false;

  Map<String, dynamic> toJson() {
    return {
      "store": store,
      "id": id,
      "readableIdentifier": readableIdentifier,
      "isCreation": isCreation,
      "isUpdate": isUpdate,
      "updatedFields": updatedFields,
      "oldVals": oldVals,
      "newVals": newVals,
      "targetIDs": targetIDs
    };
  }
}
