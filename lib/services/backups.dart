import 'package:apexo/core/observable.dart';
import 'package:apexo/core/save_local.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/services/login.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';

class BackupFile {
  late String key;
  late int size;
  late DateTime date;
  BackupFile(BackupFileInfo info) {
    key = info.key;
    size = info.size;
    date = DateTime.parse(info.modified);
  }
}

class _Backups {
  final list = ObservableState(List<BackupFile>.from([]));
  final loaded = ObservableState(false);
  final loading = ObservableState(false);
  final creating = ObservableState(false);
  final uploading = ObservableState(false);
  final downloading = ObservableState(Map<String, bool>.from({}));
  final deleting = ObservableState(Map<String, bool>.from({}));
  final restoring = ObservableState(Map<String, bool>.from({}));

  Future<void> newBackup() async {
    creating(true);
    await login.pb!.backups.create("");
    await reloadFromRemote();
    creating(false);
  }

  Future<void> delete(String key) async {
    deleting(deleting()..addAll({key: true}));
    await login.pb!.backups.delete(key);
    deleting(deleting()..remove(key));
    await reloadFromRemote();
  }

  Future<Uri> downloadUri(String key) async {
    downloading(downloading()..addAll({key: true}));
    final token = await login.pb!.files.getToken();
    downloading(downloading()..remove(key));
    return login.pb!.backups.getDownloadURL(token, key);
  }

  Future<void> restore(String key) async {
    restoring(restoring()..addAll({key: true}));
    await login.pb!.backups.restore(key);
    await Future.wait(removeAllLocalData.map((e) => e()));
    restoring(restoring()..remove(key));
    login.logout();
  }

  Future<void> pickAndUpload() async {
    final filePickerRes = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      allowedExtensions: ["zip"],
      withReadStream: true,
      allowCompression: true,
      type: FileType.custom,
    );
    if (filePickerRes == null) {
      return;
    }
    if (filePickerRes.files.isEmpty) {
      return;
    }
    final file = filePickerRes.files.first;
    final multipartFile = MultipartFile(
      "file",
      file.readStream!,
      file.size,
      filename: "uploaded-${DateTime.now().millisecondsSinceEpoch}-${file.name}",
      contentType: MediaType("application", "zip"),
    );
    uploading(true);
    await login.pb!.backups.upload(multipartFile);
    uploading(false);
    await reloadFromRemote();
  }

  Future<void> reloadFromRemote() async {
    if (login.isAdmin == false || login.pb == null || login.token.isEmpty || login.pb!.authStore.isValid == false) {
      return;
    }
    loading(true);
    try {
      list((await login.pb!.backups.getFullList()).map((e) => BackupFile(e)).toList()
        ..sort((a, b) => b.date.compareTo(a.date)));
    } catch (e, s) {
      logger("Error when getting full list of backups service: $e", s);
    }
    loaded(true);
    loading(false);
  }
}

final backups = _Backups();
