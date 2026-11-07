import 'dart:io';

import 'package:hive_flutter/adapters.dart';

/// Points the process-global Hive at a fresh temp directory; call before any
/// box is opened.
Future<Directory> setupTestHive() async {
  final dir = Directory.systemTemp.createTempSync('apexo_test_hive_');
  Hive.init(dir.path);
  return dir;
}

/// Closes all Hive boxes and deletes the temp directory.
Future<void> teardownTestHive(Directory dir) async {
  await Hive.close();
  if (dir.existsSync()) {
    await dir.delete(recursive: true);
  }
}

/// Thin wrapper over `Hive.openBox`; isolation comes from [setupTestHive].
Future<Box<T>> openTestBox<T>(String name) async {
  return Hive.openBox<T>(name);
}
