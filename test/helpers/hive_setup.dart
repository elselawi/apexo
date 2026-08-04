import 'dart:io';

import 'package:hive_flutter/adapters.dart';

/// Sets up Hive with a temporary directory for testing.
///
/// Call [setupTestHive] in `setUp` or `setUpAll`, and [teardownTestHive] in
/// `tearDown` or `tearDownAll`. Hive in a temp directory is fast, in-memory
/// capable, and more reliable than any mock.
///
/// Usage:
/// ```dart
/// setUpAll(() async => await setupTestHive());
/// tearDownAll(() async => await teardownTestHive());
/// ```
Future<Directory> setupTestHive() async {
  final dir = Directory.systemTemp.createTempSync('apexo_test_hive_');
  Hive.init(dir.path);
  return dir;
}

/// Closes all Hive boxes and deletes the temp directory.
Future<void> teardownTestHive(Directory dir) async {
  await Hive.close();
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

/// Opens a Hive box in the test temp directory. Prefer using this over
/// `Hive.openBox()` directly so all test boxes are isolated.
Future<Box<T>> openTestBox<T>(String name) async {
  return Hive.openBox<T>(name);
}
