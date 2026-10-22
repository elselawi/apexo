import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

const baseDir = 'apexo-files';

/// Whether the app is running under `flutter test`.
///
/// The test runner sets `FLUTTER_TEST` for every process it starts.
bool get isTestEnvironment =>
    Platform.environment.containsKey('FLUTTER_TEST');

/// Where the app keeps its files: the platform's documents folder, with the
/// app's own folder inside it.
///
/// Falls back to the folder's own name when the platform has no documents
/// folder to give — which is the case in a test.
Future<String> appFilesDir() async {
  try {
    return join((await getApplicationDocumentsDirectory()).path, baseDir);
  } catch (e) {
    return baseDir;
  }
}

/// Where the files this process opens live.
///
/// A test process gets a directory of its own. Hive locks the files it opens,
/// and the test runner runs several test files at once — two processes sharing
/// one directory would fail to open the same box, one of them with a
/// "lock failed" error. It also keeps a test run from touching the files the
/// developer has on their own machine.
Future<String> filesDir() async {
  if (isTestEnvironment) {
    return join(Directory.systemTemp.path, 'apexo-test-$pid');
  }
  return appFilesDir();
}
