import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

const baseDir = 'apexo-files';

/// True under `flutter test`, which sets `FLUTTER_TEST`; checked before touching
/// `Platform.environment`, which throws on web.
bool get isTestEnvironment =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Documents folder plus [baseDir], falling back to [baseDir] when the platform
/// gives no documents folder, as in a test.
Future<String> appFilesDir() async {
  try {
    return join((await getApplicationDocumentsDirectory()).path, baseDir);
  } catch (e) {
    return baseDir;
  }
}

/// Where this process opens its files; under test it is a per-PID temp
/// directory, since Hive locks boxes and the runner runs test files in parallel.
Future<String> filesDir() async {
  if (isTestEnvironment) {
    return join(Directory.systemTemp.path, 'apexo-test-$pid');
  }
  return appFilesDir();
}
