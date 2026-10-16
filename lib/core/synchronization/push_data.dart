/// The push payload: the JSON that travels from the change that caused it to the
/// device that displays it.
///
/// This file is the **wire shape only** — the fields, how a payload serializes,
/// and how a store change becomes one. The three things that used to share this
/// responsibilities live in `services/notifications/`:
///
/// * `push_interpretation.dart` — what a payload *means*, and how it reads in
///   each language;
/// * `push_relay.dart` — how it leaves the device.
///
/// ---------------------------------------------------------------------------
///  !!!! IMPORTANT !!!!
/// the JSON below is mirrored by the `web/fcm/push_data.js` file, which the web
/// app and its service worker use to display a push. A field added, renamed or
/// removed here must be added, renamed or removed there. That file mirrors the
/// interpretation and its translations too — see `push_interpretation.dart` for
/// the rest of the contract.
/// ---------------------------------------------------------------------------
library;

/// The data behind every notice: FCM carries it as a JSON string, the deferred
/// queue stores it, and the in-app list displays it.
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

  /// The payload for one store change: [changed] are the fields that moved, and
  /// the values are read from [before] and [after] in that same order.
  ///
  /// Both producers of a notice build their payload here, so the two cannot
  /// disagree about the shape. [before] is null for a creation.
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

  /// Whether an uninterpretable payload has already been reported for this
  /// datum. `displayTuple()` is called from `build`, so the diagnosis must be
  /// reported once and not once per frame.
  ///
  /// The diagnosis itself is in `push_interpretation.dart`; the flag is here
  /// because it is per-datum state that has to survive between those calls, and
  /// Dart privacy is per-library — an extension in another file cannot reach a
  /// private field of this class.
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
