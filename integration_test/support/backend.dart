import 'dart:io';

import 'package:apexo/utils/init_pocketbase.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase/pocketbase.dart';
import 'credentials.dart';

/// The backend and device state an end-to-end run starts from.
///
/// Self-contained on purpose: an e2e file may only import `lib/` and its own
/// `integration_test/` tree, because a web build compiles nothing else. That is
/// why this does not reuse `test/live_backend/test_utils.dart`, which reaches
/// into `test/secret.dart` and is only usable from a native run.
abstract final class Backend {
  /// Sends the app's log lines to the test output.
  static void initLogging() {
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('➡️: ${record.message}');
    });
  }

  /// Deletes the device-local files, so the app starts like a fresh install —
  /// no session, no cached settings, no remembered schema version, no local
  /// database, and no attachment bytes.
  ///
  /// The database matters: the migrated stores live in `localpocket`'s SQLite
  /// file, not in Hive, so wiping only `*.hive` left every patient from every
  /// earlier run behind — invisible while the server is reset to empty too, and
  /// then showing up in every list.
  ///
  /// On web there is nothing to delete here: the local data is the browser
  /// profile (IndexedDB / OPFS), which this process cannot touch. A web run
  /// starts from whatever the profile holds; use a fresh browser profile when
  /// that matters.
  static Future<void> resetLocalData() async {
    if (kIsWeb) {
      logger('Local data wipe skipped: on web it is browser profile storage',
          null, 2);
      return;
    }

    final directory = Directory(await filesDir());
    if (!directory.existsSync()) {
      logger(
          'No local data to wipe (${directory.path} does not exist)', null, 3);
      return;
    }
    await for (final entity in directory.list(recursive: false)) {
      if (entity is File && _isLocalDataFile(entity.path)) {
        try {
          await entity.delete();
        } catch (e) {
          logger('Failed to delete ${entity.path}: $e', null, 2);
        }
      } else if (entity is Directory && _isLocalDataDirectory(entity.path)) {
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          logger('Failed to delete ${entity.path}: $e', null, 2);
        }
      }
    }
    logger('Local data wiped: the app is a fresh install', null, 3);
  }

  /// Hive boxes, their locks, and `localpocket`'s SQLite file with the journal
  /// and WAL siblings SQLite keeps beside it.
  static bool _isLocalDataFile(String path) {
    const suffixes = [
      'hive',
      'lock',
      '.db',
      '.db-journal',
      '.db-wal',
      '.db-shm',
    ];
    return suffixes.any(path.endsWith);
  }

  /// A clinic's attachment directory: one per database, beside it, holding the
  /// `blobs` its store writes to (`blobRootFor(dbPath)`, i.e. `apexo-<hash>`).
  ///
  /// Matched by layout, not by name: the old rule looked for
  /// `localpocket_blobs`, which is the **web worker's** OPFS directory and can
  /// never exist here (this wipe returns early on web) — so every attachment
  /// byte survived a "fresh install".
  static bool _isLocalDataDirectory(String path) =>
      Directory('$path${Platform.pathSeparator}blobs').existsSync();

  static final PocketBase _pb = PocketBase(pbServer);

  /// Puts the server back to a freshly initialized PocketBase: the `data` and
  /// `public` collections are dropped and re-imported from the definitions the
  /// app ships (`lib/utils/constants.dart`).
  ///
  /// This is destructive to the clinic it is pointed at — which is why the
  /// credentials of a throw-away test server belong in `test/secret.dart`.
  static Future<void> resetServer() async {
    await dropCollections();
    try {
      await initializePocketbase(_pb);
    } catch (e) {
      // PocketBase can still hold the collection it has just been told to
      // delete in its in-memory cache, and the import then fails with
      // `failed to retrieve old cached collection: sql: no rows in result set`
      // (the same quirk `reconcileSchema` works around by attaching the
      // server's ids). A second attempt is after that cache has been dropped.
      // Measured once, on a `dicom` run whose first boot was the only test that
      // failed.
      logger('The first schema import after the reset failed ($e) — retrying',
          null, 2);
      await initializePocketbase(_pb);
    }
    logger('Remote data reset: the server is a freshly initialized PocketBase',
        null, 3);
  }

  /// Drops the `data` and `public` collections and **leaves them dropped**.
  ///
  /// `resetServer` deletes and then re-creates them, so the app always finds a
  /// ready clinic; a server that answers with "no such collection" is what a
  /// *brand new* PocketBase looks like, and it is the only way to reach the
  /// app's first-launch path (`activate` sets `launch.isFirstLaunch`, creates
  /// the collections itself, and the app then shows its first-launch dialog).
  /// The next login puts the collections back, so this is destructive in the
  /// same way `resetServer` is: the clinic's rows go with them.
  static Future<void> dropCollections() async {
    if (!_pb.authStore.isValid) {
      await _pb.collection("_superusers").authWithPassword(pbEmail, pbPassword);
    }
    for (final name in ["public", "data"]) {
      try {
        await _pb.collections.delete(name);
        // ignore: empty_catches
      } catch (e) {
        // Absent already: a freshly initialized server has neither.
      }
    }
  }

  /// One collection's list rule, as the server has it — the cheapest piece of
  /// the schema to read back and reason about (a rule change is what the
  /// reconciliation exists to ship, and it destroys no rows).
  static Future<String?> collectionRule(String name) async {
    if (!_pb.authStore.isValid) {
      await _pb.collection("_superusers").authWithPassword(pbEmail, pbPassword);
    }
    return (await _pb.collections.getOne(name)).listRule;
  }

  /// Sets a collection's list rule — the app's own reconciliation is what puts
  /// the definition back (`initializePocketbase`/`reconcileSchema`).
  static Future<void> setCollectionRule(String name, String rule) async {
    if (!_pb.authStore.isValid) {
      await _pb.collection("_superusers").authWithPassword(pbEmail, pbPassword);
    }
    await _pb.collections.update(name, body: {'listRule': rule});
  }
}
