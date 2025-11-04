import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/remote_versions.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _VersionService {
  final current = ObservableState("");
  final latest = ObservableState("");

  bool get newVersionAvailable {
    return latest() != "" && latest() != current();
  }

  Future<void> update() async {
    try {
      current((await PackageInfo.fromPlatform()).version);
    } catch (_) {
      current("0.0.0");
    }

    try {
      latest((await getLatestVersion('elselawi', 'apexo', 'dist')).version);
    } catch (e, s) {
      logger("Could not get latest version: $e", s);
    }
  }

  _VersionService() {
    update();
  }
}

final version = _VersionService();
