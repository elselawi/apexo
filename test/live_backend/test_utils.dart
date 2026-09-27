import 'dart:io';

import 'package:apexo/core/save_local.dart';
import 'package:apexo/core/save_remote.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase/pocketbase.dart';
import '../secret.dart';

class TestUtils {
  static Future<void> removeLocalData() async {
    final directory = Directory(await filesDir());
    if (await directory.exists()) {
      await for (var entity in directory.list(recursive: false)) {
        if (entity is File &&
            (entity.path.endsWith("hive") || entity.path.endsWith("lock"))) {
          try {
            await entity.delete();
            logger('Deleted: ${entity.path}', null, 3);
          } catch (e) {
            logger('Failed to delete ${entity.path}: $e', null, 2);
          }
        }
      }
    } else {
      logger('Directory does not exist: ${directory.path}', null, 3);
    }
    logger(
        "Local data removed successfully, the app now is like a freshly installed app",
        null,
        3);
  }

  static void integrationLoggerInit() {
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('➡️: ${record.message}');
    });
  }

  // Pocketbase and local hive setup

  static final SaveLocal local = SaveLocal(name: "test", uniqueId: "test");
  static final SaveRemote remote =
      SaveRemote(storeName: "test", pbInstance: pb);
  static final pb = PocketBase(testPBServer);
  static Future<void> deleteRemoteData() async {
    // just like a fresh install
    if (pb.authStore.isValid == false) {
      await pb
          .collection("_superusers")
          .authWithPassword(testPBEmail, testPBPassword);
    }
    try {
      await pb.collections.delete("public");
      // ignore: empty_catches
    } catch (e) {}
    try {
      await pb.collections.delete("data");
      // ignore: empty_catches
    } catch (e) {}
    logger(
        "Remote data removed successfully, the server now is like a freshly installed pocketbase",
        null,
        3);
  }

  static Future<void> resetServer() async {
    await deleteRemoteData();
    await initializePocketbase(pb);
  }
}
