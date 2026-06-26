import 'dart:convert';
import 'dart:math';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:pocketbase/pocketbase.dart';

class RowToWriteRemotely {
  String id;
  String data;
  String store = "";
  RowToWriteRemotely({required this.id, required this.data});
  toJson() {
    return {
      "id": id,
      "data": data,
      "store": store,
    };
  }
}

class Row extends RowToWriteRemotely {
  int ts;
  Row({required super.id, required super.data, required this.ts});
}

class VersionedResult {
  int version;
  List<Row> rows;
  VersionedResult(this.version, this.rows);
}

class SaveRemote {
  final String storeName;
  final PocketBase pbInstance;

  // timer to debounce online status checks
  Timer? timer;

  // callback to notify the app of online status changes
  void Function(bool)? onOnlineStatusChange;

  bool isOnline = true;
  final Map<String, Future<String>> _uploadsInFlight = {};
  SaveRemote({
    required this.storeName,
    required this.pbInstance,
    this.onOnlineStatusChange,
  }) {
    checkOnline();
  }

  RecordService get remoteRows {
    return pbInstance.collection(dataCollectionName);
  }

  void retryConnection() {
    if (timer != null && timer!.isActive) {
      return;
    }
    Timer.periodic(const Duration(seconds: 5), (t) {
      timer = t;
      if (isOnline) {
        timer!.cancel();
      } else {
        checkOnline();
      }
    });
  }

  Future<void> checkOnline() async {
    try {
      await pbInstance.health.check().timeout(const Duration(seconds: 3));
    } catch (e) {
      isOnline = false;
      retryConnection();
      if (onOnlineStatusChange != null) onOnlineStatusChange!(isOnline);
      return;
    }
    isOnline = true;
    if (timer != null) {
      timer!.cancel();
    }
    if (onOnlineStatusChange != null) onOnlineStatusChange!(isOnline);
  }

  String formatForPocketBase(int input) {
    // for some reason, pocketbase doesn't accept the ISO8601 format
    // it stores "updated" and "created" fields in the following format: "2024-11-28 12:00:00.000Z"
    // and it disregards the time if a "T" was included in the comparison
    // this format is the more preferable one for pocketbase
    // This behavior is deeply rooted in SQLite: https://www.sqlite.org/lang_datefunc.html
    return "${DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.fromMillisecondsSinceEpoch(input, isUtc: true))}Z";
  }

  Future<VersionedResult> getSince({int version = 0}) async {
    List<Row> result = [];

    final date = formatForPocketBase(version);
    bool nextPageExists = true;
    int currentPage = 1;

    do {
      try {
        final pageResult = await remoteRows.getList(
          filter: 'updated>"$date"&&store="$storeName"',
          sort: "updated",
          perPage: 900,
          page: currentPage,
          fields: "data,id,updated,imgs",
        );

        for (var item in pageResult.items) {
          final ts = DateTime.parse(item.get<String>("updated"))
              .millisecondsSinceEpoch;
          result.add(
              Row(id: item.id, data: jsonEncode(item.data["data"]), ts: ts));
          fullNamesCache
              .addAll({item.id: List<String>.from(item.data["imgs"])});
        }

        // handle pagination
        if (pageResult.totalPages > currentPage) {
          currentPage++;
        } else {
          nextPageExists = false;
        }
      } catch (e) {
        await checkOnline();
        rethrow;
      }
    } while (nextPageExists);

    return VersionedResult(
        result.isNotEmpty ? result.map((r) => r.ts).reduce(max) : 0, result);
  }

  Future<int> getVersion() async {
    try {
      final result = await remoteRows.getList(
          sort: "-updated",
          perPage: 1,
          filter: 'store="$storeName"',
          fields: "updated");
      if (result.items.isEmpty) {
        return 0;
      }
      return DateTime.parse(result.items.first.get<String>("updated"))
          .millisecondsSinceEpoch;
    } catch (e) {
      await checkOnline();
      throw Exception(e);
    }
  }

  Future<bool> put(List<RowToWriteRemotely> data) async {
    if (data.isEmpty) {
      return true;
    }

    // split data into chunks of 100
    List<List<RowToWriteRemotely>> chunks = [];
    for (var i = 0; i < data.length; i += 100) {
      chunks.add(data.sublist(i, min(i + 100, data.length)));
    }

    for (var chunk in chunks) {
      try {
        final batchOperation = pbInstance.createBatch();
        for (var item in chunk) {
          batchOperation.collection(dataCollectionName).upsert(
              body: {"store": storeName, "data": item.data, "id": item.id});
        }
        await batchOperation.send();
      } catch (e) {
        await checkOnline();
        rethrow;
      }
    }
    return true;
  }

  Future<String?> _findExistingByHash(String rowID, String filename) async {
    final hash = p.basenameWithoutExtension(filename).split('_').last;
    try {
      List<String> fullNames;
      if (fullNamesCache.containsKey(rowID)) {
        fullNames = fullNamesCache[rowID]!;
      } else {
        final record = await remoteRows.getOne(rowID, fields: "imgs");
        fullNames = List<String>.from(record.data["imgs"]);
        fullNamesCache[rowID] = fullNames;
      }
      return fullNames.where((e) => e.contains("_${hash}_")).firstOrNull;
    } catch (_) {
      return null; // can't check → proceed with upload
    }
  }

  Future<String> uploadImage({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
    http.MultipartFile? predefinedMultipart,
  }) async {
    final hash = p.basenameWithoutExtension(filename).split('_').last;

    final existing = await _findExistingByHash(rowID, filename);
    if (existing != null) return existing;

    // Guard against concurrent uploads of the same hash
    if (_uploadsInFlight.containsKey(hash)) {
      return _uploadsInFlight[hash]!;
    }

    final future = _doUpload(rowID, filename, path, file, predefinedMultipart);
    _uploadsInFlight[hash] = future;
    try {
      return await future;
    } finally {
      _uploadsInFlight.remove(hash);
    }
  }

  Future<String> _doUpload(
    String rowID,
    String filename,
    String? path,
    XFile? file,
    http.MultipartFile? predefinedMultipart,
  ) async {
    http.MultipartFile multipart;
    if (predefinedMultipart != null) {
      multipart = predefinedMultipart;
    } else if (path != null) {
      multipart = await http.MultipartFile.fromPath(
        "imgs+",
        path,
        filename: filename,
      );
    } else {
      multipart = http.MultipartFile.fromBytes(
        "imgs+",
        (await http.get(file!.path.startsWith("blob")
                ? Uri.parse(file.path)
                : Uri.parse(
                    'https://imgs.apexo.app/?url=${Uri.encodeComponent(file.path)}')))
            .bodyBytes,
        filename: filename,
      );
    }

    try {
      final newListOfImages = List<String>.from(
          (await remoteRows.update(rowID, files: [multipart], fields: "imgs"))
              .data["imgs"]);

      fullNamesCache.addAll({rowID: newListOfImages});
      return newListOfImages.last;
    } catch (e) {
      await checkOnline();
      rethrow;
    }
  }

  Future<bool> deleteImage(String rowID, String imgName) async {
    try {
      final nameWithoutExt = p.basenameWithoutExtension(imgName);
      final allFullNames = List<String>.from(
          (await remoteRows.getOne(rowID, fields: "imgs")).data["imgs"]);
      final fullNameToDelete =
          allFullNames.where((e) => e.contains(nameWithoutExt)).firstOrNull;
      if (fullNameToDelete == null) {
        return false;
      }
      await remoteRows.update(rowID, body: {
        "imgs-": [fullNameToDelete],
      });
    } catch (e) {
      await checkOnline();
      rethrow;
    }
    return true;
  }

  Future<String?> getImageLink(String rowID, String imageName,
      [bool useCache = true]) async {
    try {
      List<String> fullNames;
      bool usedCache = false;
      if (fullNamesCache.containsKey(rowID) && useCache) {
        fullNames = fullNamesCache[rowID]!;
        usedCache = true;
      } else {
        final record = await remoteRows.getOne(rowID, fields: "imgs");
        fullNames = List<String>.from(record.data["imgs"]);
      }
      fullNamesCache[rowID] = fullNames;

      final candidates = fullNames
          .where((e) => e
              .toLowerCase()
              .contains(imageName.toLowerCase().split(".").first))
          .toList();
      if (candidates.isEmpty) {
        if (useCache && usedCache) {
          return await getImageLink(rowID, imageName, false);
        } else {
          return null;
        }
      } else {
        return "${pbInstance.baseURL}/api/files/$dataCollectionName/$rowID/${candidates.first}";
      }
    } catch (e) {
      await checkOnline();
      rethrow;
    }
  }

  Map<String, List<String>> fullNamesCache = {};
}
