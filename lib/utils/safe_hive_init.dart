import 'package:apexo/utils/safe_dir.dart';
import 'package:hive_flutter/adapters.dart';

Future<void> safeHiveInit() async {
  // A test process keeps its files in a directory of its own, and must not
  // reach for the platform's documents folder at all: it is not there, and the
  // fallback below would put a Hive box in the working directory.
  if (isTestEnvironment) {
    Hive.init(await filesDir());
    return;
  }
  try {
    await Hive.initFlutter();
  } catch (e) {
    Hive.init(baseDir);
  }
}
