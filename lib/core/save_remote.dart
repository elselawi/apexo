import 'dart:convert';
import 'dart:math';
import 'package:apexo/services/dicom/dicom_helpers.dart' as dcm_helpers;
import 'package:apexo/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
  // Scope the in-flight guard to both row and filename. A hash-only key can
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
          fullNamesCache.addAll({
            item.id: List<String>.from(item.data["imgs"] ?? const <String>[]),
          });
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

  Future<List<String>> _findDuplicates(String rowID, String filename,
      [bool allowPngExtensionToo = false]) async {
    final extension = p.extension(filename).toLowerCase();
    final isDcm = _isDcmOrDcmPreview(filename);
    try {
      final fullNames = await getFileNames(rowID);
      return fullNames.where((fullName) {
        final fullExtension = p.extension(fullName).toLowerCase();
        final matchingExtension = fullExtension == extension ||
            (allowPngExtensionToo && fullExtension == '.png');
        if (!matchingExtension) return false;
        if (isDcm) {
          return sameDcmUploadIdentity(filename, fullName);
        }
        // Ordinary image attachments retain hash identity, but require a
        // basename boundary so a shorter hash cannot match a longer one.
        return _sameOrdinaryUploadIdentity(filename, fullName);
      }).toList();
    } catch (_) {
      return []; // can't check → proceed with upload
    }
  }

  /// Returns whether two ordinary attachment names represent the same
  /// generated upload identity.
  static bool _sameOrdinaryUploadIdentity(String requested, String existing) {
    final requestedBase = p.basenameWithoutExtension(requested).toLowerCase();
    final hash = requestedBase.split('_').last;
    final existingBase = p.basenameWithoutExtension(existing).toLowerCase();
    return existingBase.split('_').contains(hash);
  }

  /// Returns the normalized DICOM upload identity, ignoring a PocketBase
  /// collision suffix and the generated `.dcm.png` preview extension.
  @visibleForTesting
  static String? dcmUploadIdentity(String filename) =>
      dcm_helpers.dcmUploadIdentity(filename);

  @visibleForTesting
  static bool sameDcmUploadIdentity(String a, String b) =>
      dcm_helpers.sameDcmUploadIdentity(a, b);

  /// Returns the DICOM files that may be removed when [retainedDcmName]
  /// remains. The retained original and its generated preview are protected.
  @visibleForTesting
  static List<String> dcmFilesToDelete({
    required String retainedDcmName,
    required List<String> matchingFiles,
  }) {
    var retainedOriginal = retainedDcmName.toLowerCase();
    if (retainedOriginal.endsWith('.dcm.png') ||
        retainedOriginal.endsWith('.dicom.png')) {
      retainedOriginal = retainedOriginal.substring(
          0, retainedOriginal.length - '.png'.length);
    }

    final retainedPreview = '$retainedOriginal.png';
    final toDelete = matchingFiles.where((name) {
      final lower = name.toLowerCase();
      return lower != retainedOriginal && lower != retainedPreview;
    }).toList();

    // if we're not retaining BOTH preview and dicom then we should delete them all
    // so that a new upload can happen cleanily
    return toDelete.length == matchingFiles.length - 2
        ? toDelete
        : matchingFiles;
  }

  /// Returns the current PocketBase file names for [rowID].
  ///
  /// Cleanup and DICOM healing must use this server-authoritative list rather
  /// than the model's `imgs` field: DICOM originals live in the PocketBase
  /// `imgs` file field but are represented separately by `dcmImgs` in the
  /// appointment JSON.
  Future<List<String>> getFileNames(String rowID,
      {bool useCache = false}) async {
    if (useCache && fullNamesCache.containsKey(rowID)) {
      return List<String>.from(fullNamesCache[rowID]!);
    }
    final record = await remoteRows.getOne(rowID, fields: "imgs");
    final names = List<String>.from(record.data["imgs"] ?? const <String>[]);
    fullNamesCache[rowID] = names;
    return List<String>.from(names);
  }

  Future<String> uploadImage({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
    http.MultipartFile? predefinedMultipart,
  }) async {
    final identity =
        _isDcmOrDcmPreview(filename) ? dcmUploadIdentity(filename) : null;
    final uploadKey =
        '$rowID||${identity ?? filename}||${dcm_helpers.isDcmPreviewName(filename) ? 'preview' : 'original'}';
    final inFlight = _uploadsInFlight[uploadKey];
    if (inFlight != null) return inFlight;

    final future = _uploadImageOnce(
      rowID: rowID,
      filename: filename,
      path: path,
      file: file,
      predefinedMultipart: predefinedMultipart,
    );
    _uploadsInFlight[uploadKey] = future;
    try {
      return await future;
    } finally {
      _uploadsInFlight.remove(uploadKey);
    }
  }

  Future<String> _uploadImageOnce({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
    http.MultipartFile? predefinedMultipart,
  }) async {
    final existingFullNames =
        await _findDuplicates(rowID, filename, _isDcmOrDcmPreview(filename));

    // If matching files exist, retain the requested physical type for DICOM
    // (original or preview), then remove only the remaining duplicates. The
    // fallback is important for incomplete pairs: it lets dcmFilesToDelete
    // remove the lone opposite-type file before a clean upload.
    final isDcmRequest = _isDcmOrDcmPreview(filename);
    final toKeep = isDcmRequest
        ? (dcm_helpers.isDcmFileName(filename)
                ? existingFullNames.where(dcm_helpers.isDcmFileName).firstOrNull
                : existingFullNames
                    .where(dcm_helpers.isDcmPreviewName)
                    .firstOrNull) ??
            existingFullNames.firstOrNull
        : existingFullNames.firstOrNull;
    if (toKeep != null) {
      final duplicates = isDcmRequest
          ? ((dcm_helpers.isDcmFileName(filename) &&
                      dcm_helpers.isDcmPreviewName(toKeep)) ||
                  (dcm_helpers.isDcmPreviewName(filename) &&
                      dcm_helpers.isDcmFileName(toKeep)))
              ? existingFullNames
              : dcmFilesToDelete(
                  retainedDcmName: toKeep,
                  matchingFiles: existingFullNames,
                )
          : existingFullNames.where((name) => name != toKeep).toList();

      if (duplicates.isNotEmpty) {
        await remoteRows.update(rowID, body: {
          "imgs-": duplicates,
        });
      }
      final deletedAll = duplicates.length == existingFullNames.length;
      if (isDcmRequest && duplicates.isNotEmpty) {
        final refreshedFiles = await getFileNames(rowID);
        if (!refreshedFiles
            .any((name) => name.toLowerCase() == toKeep.toLowerCase())) {
          if (deletedAll) {
            return _doUpload(rowID, filename, path, file, predefinedMultipart);
          }
          throw StateError('Retained file disappeared during deduplication: '
              '$toKeep');
        }
        fullNamesCache[rowID] = refreshedFiles;
        final requestedName = filename.toLowerCase();
        final requestedTypePresent = refreshedFiles.any((name) {
          final lower = name.toLowerCase();
          return lower == requestedName;
        });
        if (requestedTypePresent) return filename;
        if (deletedAll) {
          return _doUpload(rowID, filename, path, file, predefinedMultipart);
        }
      }
      if (!deletedAll) {
        final refreshedFiles = await getFileNames(rowID);
        if (!refreshedFiles
            .any((name) => name.toLowerCase() == toKeep.toLowerCase())) {
          throw StateError('Retained file disappeared during deduplication: '
              '$toKeep');
        }
        fullNamesCache[rowID] = refreshedFiles;
        return toKeep;
      }
    }
    return _doUpload(rowID, filename, path, file, predefinedMultipart);
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
      final newListOfImages = List<String>.from((await remoteRows.update(
            rowID,
            files: [multipart],
            fields: "imgs",
          ))
              .data["imgs"] ??
          const <String>[]);
      if (newListOfImages.isEmpty) {
        throw StateError('PocketBase upload returned no file names');
      }

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
      final allFullNames = await getFileNames(rowID);
      // Prefer exact match first — avoids ambiguity between e.g.
      // "x.dcm" and "x.dcm.png" (the DCM original and its PNG preview).
      var fullNameToDelete = allFullNames
          .where((e) => e.toLowerCase() == imgName.toLowerCase())
          .firstOrNull;
      // Fuzzy matching is unsafe for DICOM originals/previews: if the
      // original is missing, it could delete the preview instead.  Keep the
      // legacy fallback only for ordinary image attachments.
      if (fullNameToDelete == null && !_isDcmOrDcmPreview(imgName)) {
        fullNameToDelete =
            allFullNames.where((e) => e.contains(nameWithoutExt)).firstOrNull;
      }
      if (fullNameToDelete == null) {
        return false;
      }
      final toDelete = [
        fullNameToDelete,
        if (dcm_helpers.isDcmFileName(imgName))
          allFullNames
              .where(
                  (name) => name.toLowerCase() == '$imgName.png'.toLowerCase())
              .firstOrNull,
      ].whereType<String>().toList();
      await remoteRows.update(rowID, body: {
        "imgs-": toDelete,
      });
      fullNamesCache[rowID] =
          allFullNames.where((name) => !toDelete.contains(name)).toList();
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
        fullNames = List<String>.from(record.data["imgs"] ?? const <String>[]);
      }
      fullNamesCache[rowID] = fullNames;

      // Prefer exact match first — avoids ambiguity between e.g.
      // "x.dcm" and "x.dcm.png" (the DCM original and its PNG preview).
      final lower = imageName.toLowerCase();
      var candidates =
          fullNames.where((e) => e.toLowerCase() == lower).toList();
      // Fuzzy matching is unsafe for DICOM originals/previews: if one side
      // is missing, it can resolve to the other side and return the wrong
      // payload type. Keep the legacy fallback for ordinary attachments.
      if (candidates.isEmpty && !_isDcmOrDcmPreview(imageName)) {
        candidates = fullNames
            .where((e) => e.toLowerCase().contains(lower.split(".").first))
            .toList();
      }
      if (candidates.isEmpty) {
        // Never fall back from a DICOM original to a similarly-named preview
        // (or vice versa). The viewer needs the raw original and a PNG is
        // not a valid DICOM payload.
        if (!_isDcmOrDcmPreview(imageName) && useCache && usedCache) {
          return await getImageLink(rowID, imageName, false);
        }
        return null;
      } else {
        return "${pbInstance.baseURL}/api/files/$dataCollectionName/$rowID/${candidates.first}";
      }
    } catch (e) {
      await checkOnline();
      rethrow;
    }
  }

  bool _isDcmOrDcmPreview(String name) {
    return dcm_helpers.isDcmFileName(name) ||
        dcm_helpers.isDcmPreviewName(name);
  }

  Map<String, List<String>> fullNamesCache = {};
}
