import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:pocketbase/pocketbase.dart';

const String _usersCreateRule = '@request.auth.collectionName = "_superusers"';

/// This would initialize the server creating required collections, rules, and settings
Future<void> initializePocketbase(PocketBase pb) async {
  await pb.collections.import([
    dataCollectionImport,
    publicCollectionImport,
    ...bookingCollections,
  ]);
  await pb.collections.update("users", body: {"createRule": _usersCreateRule});
  await pb.settings.update(body: {
    "batch": {
      "enabled": true,
      "maxRequests": 101,
      "timeout": 3,
      "maxBodySize": 0
    }
  });
}

Future<void> initializeProfiles(PocketBase pb) async {
  await pb.collections
      .import([profilesCollectionImport, profilesViewCollectionImport]);
}

// Existing clinics never re-import their schema, so an admin login reconciles it
// against constants.dart at most once per version. The import is a pure upsert
// (`deleteMissing` false, so nothing is deleted) and requires superuser auth.

const String _schemaVersionBoxPrefix = "schema-version-";

/// PocketBase's page-size ceiling; a full page means the list may be truncated.
const int _collectionPageSize = 500;

/// The schema version already applied on this device for the given clinic.
Future<int> appliedSchemaVersion(String clinicKey) async {
  try {
    final box = await Hive.openBox<String>(
      "$_schemaVersionBoxPrefix$clinicKey",
      // An explicit path needs no Hive initialization, and the app's own boxes
      // have already initialized it by the time a login runs.
      path: await filesDir(),
    );
    return int.tryParse(box.get("version", defaultValue: "") ?? "") ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<void> storeAppliedSchemaVersion(String clinicKey, int version) async {
  try {
    final box = await Hive.openBox<String>(
      "$_schemaVersionBoxPrefix$clinicKey",
      path: await filesDir(),
    );
    await box.put("version", version.toString());
  } catch (_) {
    // Non-fatal: the import is idempotent and retries on the next admin login.
  }
}

/// Records that the current definitions were imported on this device, so a
/// fresh install does not reconcile what it has only just created.
Future<void> markSchemaApplied(String clinicServer) =>
    storeAppliedSchemaVersion(simpleHash(clinicServer), schemaVersion);

/// Reconciles the server schema with constants.dart, at most once per version.
///
/// [appliedVersion] is what the caller has already persisted (the login state
/// keeps it), which skips all local reads; the larger of the two markers wins.
/// [onWork] runs only when a reconcile is really needed, so the caller never
/// announces work that did not happen.
Future<void> reconcileSchema(
  PocketBase pb, {
  required String clinicServer,
  int appliedVersion = 0,
  void Function()? onWork,
}) async {
  final clinicKey = simpleHash(clinicServer);
  if (appliedVersion >= schemaVersion) return;
  if (await appliedSchemaVersion(clinicKey) >= schemaVersion) return;

  onWork?.call();

  // PB matches collections by id, but an empty id makes it unmarshal onto the
  // existing collection and lose the real id; attach the server's ids first.
  // Fresh collections keep an empty id and are created normally.
  final existing = await pb.collections.getList(
    perPage: _collectionPageSize,
    skipTotal: true,
    // Only what the import needs, not every field, rule and index.
    fields: 'id,name,createRule',
  );
  final byName = {
    for (final collection in existing.items)
      if (collection.name.isNotEmpty) collection.name: collection,
  };
  if (byName.isEmpty || existing.items.length >= _collectionPageSize) {
    // Importing without the server ids can rewrite the wrong collections, so an
    // unreadable or truncated list defers the reconcile to the next admin login.
    throw StateError(
        "The server's collection list could not be read completely; the "
        "schema import was skipped.");
  }

  final definitions = [
    dataCollectionImport,
    publicCollectionImport,
    profilesCollectionImport,
    profilesViewCollectionImport,
    ...bookingCollections,
  ];

  final withServerIds = definitions.map((model) {
    final serverId = byName[model.name]?.id ?? "";
    if (serverId.isEmpty) return model;
    return CollectionModel.fromJson(model.toJson())..id = serverId;
  }).toList();

  await pb.collections.import(withServerIds);

  // The import is what makes the schema current, so record it before the
  // hardening below: a rule that keeps failing must not force a full re-import
  // on every admin login.
  await storeAppliedSchemaVersion(clinicKey, schemaVersion);

  // Re-apply the users createRule so a drifted install converges.
  if (byName["users"]?.createRule != _usersCreateRule) {
    try {
      await pb.collections
          .update("users", body: {"createRule": _usersCreateRule});
    } catch (e, s) {
      logger("Could not re-apply the users create rule: $e", s, 2);
    }
  }
}

/// Explicit superuser repair of the booking collections. Bypasses the version
/// marker (it may say applied while a collection is missing), preserves existing
/// ids and records, and never deletes a field or row.
Future<void> ensureBookingSchema(PocketBase pb) async {
  final existing = await pb.collections.getFullList();
  final idByName = {for (final c in existing) c.name: c.id};
  final withServerIds = bookingCollections.map((model) {
    final serverId = idByName[model.name];
    if (serverId == null || serverId.isEmpty) return model;
    return CollectionModel.fromJson(model.toJson())..id = serverId;
  }).toList();
  await pb.collections.import(withServerIds);
}

/// Whether the server has the PMS batch API enabled; booking scheduling needs it,
/// so setup checks rather than assumes.
Future<bool> pmsBatchApiEnabled(PocketBase pb) async {
  try {
    final settings = await pb.settings.getAll();
    final batch = settings["batch"] as Map<String, dynamic>?;
    return batch?["enabled"] == true;
  } catch (_) {
    return false;
  }
}

/// Enables batching while preserving any custom sibling values.
Future<void> ensurePmsBatchEnabled(PocketBase pb) async {
  final settings = await pb.settings.getAll();
  final current = settings["batch"] as Map<String, dynamic>? ?? {};
  await pb.settings.update(body: {
    "batch": {
      "enabled": true,
      "maxRequests": current["maxRequests"] ?? 101,
      "timeout": current["timeout"] ?? 3,
      "maxBodySize": current["maxBodySize"] ?? 0,
    }
  });
}
