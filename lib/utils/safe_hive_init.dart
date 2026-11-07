import 'package:apexo/utils/safe_dir.dart';
import 'package:hive_flutter/adapters.dart';

Future<void> safeHiveInit() async {
  // Under test, init from the per-process test dir: there is no documents
  // folder, and the fallback would put a Hive box in the working directory.
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
