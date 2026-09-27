import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:pocketbase/pocketbase.dart';

/// This would initialize the server creating required collections, rules, and settings
Future<void> initializePocketbase(PocketBase pb) async {
  await pb.collections.import([dataCollectionImport, publicCollectionImport]);
  await pb.collections.update("users",
      body: {"createRule": '@request.auth.collectionName = "_superusers"'});
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

// ---------------------------------------------------------------------------
// Schema reconciliation
// ---------------------------------------------------------------------------
//
// Existing clinics never re-import their schema on their own, so rule/field
// changes (eg. the patient portal scoping) would otherwise never reach them.
// When an admin (superuser) logs in we reconcile the server schema with the
// definitions in constants.dart, at most once per app schema version.
//
// Safety guarantees (verified against PocketBase's import implementation):
//  - `deleteMissing` stays false → the import is a pure upsert (create or
//    update); it can never delete collections or fields (PocketBase only
//    deletes missing non-system collections when deleteMissing is true).
//  - All app-owned collections are imported in a single call so the list is
//    always complete and system/auth collections (users, _superusers) are
//    never touched.
//  - The import endpoint requires superuser auth, so this only ever runs for
//    admins, and the caller never lets a failure block login.

const String _schemaVersionBoxPrefix = "schema-version-";

Future<void> _ensureHive() async {
  try {
    await safeHiveInit();
  } catch (_) {
    // Hive is already initialized (app startup or tests) — that's fine.
  }
}

Future<Box<String>> _schemaVersionBox(String clinicKey) async {
  await _ensureHive();
  return Hive.openBox<String>(
    "$_schemaVersionBoxPrefix$clinicKey",
    path: await filesDir(),
  );
}

/// The schema version already applied on this device for the given clinic.
Future<int> appliedSchemaVersion(String clinicKey) async {
  try {
    final box = await _schemaVersionBox(clinicKey);
    return int.tryParse(box.get("version", defaultValue: "") ?? "") ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<void> storeAppliedSchemaVersion(String clinicKey, int version) async {
  try {
    final box = await _schemaVersionBox(clinicKey);
    await box.put("version", version.toString());
  } catch (_) {
    // Marker failures are non-fatal: the import is idempotent and will
    // simply be retried on the next admin login.
  }
}

/// Applies the schema defined in constants.dart to an existing clinic.
///
/// Safe by construction (see guarantees above) and version-gated so it runs
/// at most once per app schema version per device.
Future<void> reconcileSchema(
  PocketBase pb, {
  required String clinicServer,
}) async {
  final clinicKey = simpleHash(clinicServer);
  if (await appliedSchemaVersion(clinicKey) >= schemaVersion) return;

  // PB's import matches existing collections by id (falling back to name),
  // but when the imported model carries an empty id the server unmarshals
  // it on top of the existing collection and the real collection id is
  // lost → the subsequent save fails with "failed to retrieve old cached
  // collection: sql: no rows in result set" (verified against a live PB).
  // So we attach the server's current ids to our definitions first; fresh
  // collections keep an empty id and are created normally.
  final existing = await pb.collections.getFullList();
  final idByName = {for (final c in existing) c.name: c.id};

  final definitions = [
    dataCollectionImport,
    publicCollectionImport,
    profilesCollectionImport,
    profilesViewCollectionImport,
  ];

  final withServerIds = definitions.map((model) {
    final serverId = idByName[model.name];
    if (serverId == null || serverId.isEmpty) return model;
    return CollectionModel.fromJson(model.toJson())..id = serverId;
  }).toList();

  await pb.collections.import(withServerIds);

  // Re-apply the users collection createRule hardening (idempotent) so a
  // fresh or drifted install converges to the app's canonical schema.
  await pb.collections.update("users", body: {
    "createRule": '@request.auth.collectionName = "_superusers"',
  });

  await storeAppliedSchemaVersion(clinicKey, schemaVersion);
}
