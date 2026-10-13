import 'dart:convert';
import 'dart:math';
import 'package:apexo/services/dicom/dicom_helpers.dart' as dcm_helpers;
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/strip_id_from_file.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pocketbase/pocketbase.dart';

class RowToWriteRemotely {
  RowToWriteRemotely({required this.id, required this.data});
  String id;
  String data;
  String store = "";
  Map<String, String> toJson() {
    return {
      "id": id,
      "data": data,
      "store": store,
    };
  }
}

class Row extends RowToWriteRemotely {
  Row({required super.id, required super.data, required this.ts});
  int ts;
}

class VersionedResult {
  VersionedResult(this.version, this.rows);
  int version;
  List<Row> rows;
}

class SaveRemote {
  SaveRemote({
    required this.storeName,
    required this.pbInstance,
    this.onOnlineStatusChange,
  }) {
    unawaited(checkOnline());
  }
  final String storeName;
  final PocketBase pbInstance;

  // timer to debounce online status checks
  Timer? timer;

  // callback to notify the app of online status changes
  void Function(bool)? onOnlineStatusChange;

  bool isOnline = true;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    timer?.cancel();
    onOnlineStatusChange = null;
  }

  // Scope the in-flight guard to both row and filename. A hash-only key can
  final Map<String, Future<String>> _uploadsInFlight = {};

  RecordService get remoteRows {
    return pbInstance.collection(dataCollectionName);
  }

  void retryConnection() {
    if (_disposed) return;
    if (timer != null && timer!.isActive) {
      return;
    }
    timer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (isOnline) {
        t.cancel();
      } else {
        unawaited(checkOnline());
      }
    });
  }

  Future<void> checkOnline() async {
    if (_disposed) return;
    try {
      await pbInstance.health.check().timeout(const Duration(seconds: 3));
    } catch (e) {
      if (_disposed) return;
      isOnline = false;
      retryConnection();
      if (onOnlineStatusChange != null) onOnlineStatusChange!(isOnline);
      return;
    }
    if (_disposed) return;
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

  /// Uses an (updated, id) keyset within each pull; persisted cursors remain
  /// timestamps, with the same strict newer-than boundary.
  Future<VersionedResult> getSince({int version = 0}) async {
    final result = <String, Row>{};
    final date = formatForPocketBase(version);

    try {
      // Bound the pull so ongoing writes cannot keep extending it. Writes
      // beyond this timestamp stay eligible for the next timestamp-cursor pull.
      final newest = await remoteRows.getList(
        filter: 'updated>"$date"&&store="$storeName"',
        sort: "-updated",
        perPage: 1,
        skipTotal: true,
        fields: "updated",
      );
      if (newest.items.isEmpty) return VersionedResult(0, []);
      final upperDate = newest.items.first.get<String>("updated");
      var afterDate = date;
      String? afterId;

      while (true) {
        final after = afterId == null
            ? 'updated>"$afterDate"'
            : '(updated>"$afterDate"||(updated="$afterDate"&&id>"$afterId"))';
        final pageResult = await remoteRows.getList(
          filter: 'store="$storeName"&&updated<="$upperDate"&&$after',
          sort: "updated,id",
          perPage: 900,
          page: 1,
          skipTotal: true,
          fields: "data,id,updated,imgs",
        );
        if (pageResult.items.isEmpty) break;

        for (final item in pageResult.items) {
          final ts = DateTime.parse(item.get<String>("updated"))
              .millisecondsSinceEpoch;
          // A fetched row can move forward within the window. Keep only its
          // latest revision, in keyset order, rather than a stale duplicate.
          result.remove(item.id);
          result[item.id] =
              Row(id: item.id, data: jsonEncode(item.data["data"]), ts: ts);
          fullNamesCache[item.id] = List<String>.from(
              item.data["imgs"] as List<dynamic>? ?? const <String>[]);
        }

        final last = pageResult.items.last;
        afterDate = last.get<String>("updated");
        afterId = last.id;
      }
    } catch (e) {
      await checkOnline();
      rethrow;
    }

    final rows = result.values.toList();
    return VersionedResult(
        rows.isNotEmpty ? rows.map((r) => r.ts).reduce(max) : 0, rows);
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
    final List<List<RowToWriteRemotely>> chunks = [];
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
    final existingParts = existingBase.split('_');
    for (var i = 0; i < existingParts.length; i++) {
      if (existingParts[i] != hash) continue;
      final collisionSuffix = existingParts.skip(i + 1);
      if (collisionSuffix.every((part) => RegExp(r'^\d+$').hasMatch(part))) {
        return true;
      }
    }
    return false;
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
    final names = List<String>.from(
        record.data["imgs"] as List<dynamic>? ?? const <String>[]);
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
      unawaited(_uploadsInFlight.remove(uploadKey));
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
              .data["imgs"] as List<dynamic>? ??
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

  /// Matches complete ordinary basenames followed only by upload suffixes.
  /// Extensionless legacy references may also omit the generated hash.
  static bool _sameOrdinaryDeletionIdentity(String requested, String existing) {
    final requestedExtension = p.extension(requested).toLowerCase();
    if (requestedExtension.isNotEmpty &&
        requestedExtension != p.extension(existing).toLowerCase()) {
      return false;
    }
    final requestedBase = p.basenameWithoutExtension(requested).toLowerCase();
    final existingBase = p.basenameWithoutExtension(existing).toLowerCase();
    if (requestedBase.isEmpty) return false;
    if (requestedBase == existingBase) return true;
    if (!existingBase.startsWith('${requestedBase}_')) return false;

    final suffix = existingBase.substring(requestedBase.length + 1);
    final suffixPattern = requestedExtension.isEmpty
        ? RegExp(r'^[a-z0-9]+(?:_\d+)*(?:_[a-z0-9]{6,})?(?:_\d+)*$')
        : RegExp(r'^(?:\d+_)*(?:[a-z0-9]{6,}|\d+)(?:_\d+)*$');
    return suffixPattern.hasMatch(suffix);
  }

  Future<bool> deleteImage(String rowID, String imgName) async {
    try {
      final allFullNames = await getFileNames(rowID);
      // Prefer exact match first — avoids ambiguity between e.g.
      // "x.dcm" and "x.dcm.png" (the DCM original and its PNG preview).
      var fullNameToDelete = allFullNames
          .where((e) => e.toLowerCase() == imgName.toLowerCase())
          .firstOrNull;
      // Only ordinary attachments allow legacy names, and an ambiguous
      // fallback must never choose a destructive match by list order.
      if (fullNameToDelete == null && !_isDcmOrDcmPreview(imgName)) {
        final matches = allFullNames
            .where((name) =>
                !_isDcmOrDcmPreview(name) &&
                _sameOrdinaryDeletionIdentity(imgName, name))
            .toList();
        if (matches.length == 1) fullNameToDelete = matches.single;
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
        fullNames = List<String>.from(
            record.data["imgs"] as List<dynamic>? ?? const <String>[]);
      }
      fullNamesCache[rowID] = fullNames;

      // Prefer exact match first — avoids ambiguity between e.g.
      // "x.dcm" and "x.dcm.png" (the DCM original and its PNG preview).
      final lower = imageName.toLowerCase();
      var candidates =
          fullNames.where((e) => e.toLowerCase() == lower).toList();
      // PocketBase adds another suffix when the derived PNG is uploaded.
      // Match only previews with the same full extension chain, never a raw
      // original or an ambiguous pair of collision-suffixed previews.
      if (candidates.isEmpty && dcm_helpers.isDcmPreviewName(imageName)) {
        final previews = fullNames
            .where((name) =>
                dcm_helpers.isDcmPreviewName(name) &&
                sameStoredFileName(name.toLowerCase(), lower))
            .toList();
        if (previews.length == 1) candidates = previews;
      }
      // Keep the legacy fuzzy fallback for ordinary attachments only.
      if (candidates.isEmpty && !_isDcmOrDcmPreview(imageName)) {
        candidates = fullNames
            .where((e) => e.toLowerCase().contains(lower.split(".").first))
            .toList();
      }
      if (candidates.isEmpty) {
        // Never fall back from a DICOM original to a similarly-named preview
        // (or vice versa). The viewer needs the raw original and a PNG is
        // not a valid DICOM payload.
        if (useCache && usedCache) {
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
