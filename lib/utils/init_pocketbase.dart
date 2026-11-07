import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:pocketbase/pocketbase.dart';

/// This would initialize the server creating required collections, rules, and settings
Future<void> initializePocketbase(PocketBase pb) async {
  await pb.collections.import([
    dataCollectionImport,
    publicCollectionImport,
    ...bookingCollections,
  ]);
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

// Existing clinics never re-import their schema, so an admin login reconciles it
// against constants.dart at most once per version. The import is a pure upsert
// (`deleteMissing` false, so nothing is deleted) and requires superuser auth.

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
    // Non-fatal: the import is idempotent and retries on the next admin login.
  }
}

/// Reconciles the server schema with constants.dart, at most once per version.
Future<void> reconcileSchema(
  PocketBase pb, {
  required String clinicServer,
}) async {
  final clinicKey = simpleHash(clinicServer);
  if (await appliedSchemaVersion(clinicKey) >= schemaVersion) return;

  // PB matches collections by id, but an empty id makes it unmarshal onto the
  // existing collection and lose the real id; attach the server's ids first.
  // Fresh collections keep an empty id and are created normally.
  final existing = await pb.collections.getFullList();
  final idByName = {for (final c in existing) c.name: c.id};

  final definitions = [
    dataCollectionImport,
    publicCollectionImport,
    profilesCollectionImport,
    profilesViewCollectionImport,
    ...bookingCollections,
  ];

  final withServerIds = definitions.map((model) {
    final serverId = idByName[model.name];
    if (serverId == null || serverId.isEmpty) return model;
    return CollectionModel.fromJson(model.toJson())..id = serverId;
  }).toList();

  await pb.collections.import(withServerIds);

  // Re-apply the users createRule hardening so a drifted install converges.
  await pb.collections.update("users", body: {
    "createRule": '@request.auth.collectionName = "_superusers"',
  });

  await storeAppliedSchemaVersion(clinicKey, schemaVersion);
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
