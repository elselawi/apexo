import 'dart:convert';
import 'package:apexo/services/dicom/dicom_helpers.dart';
import 'package:path/path.dart' as p;
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:flutter/foundation.dart';

/// NOTE:
/// This feature is not yet used nor referenced in any production code
/// I was planning to use it with a UI button in the settings.
/// But I'm currently not inclined to.
/// Since cleaning is now part of the uploading process.
///
///
/// However, everything in this file works as expected
/// and should kept for future use.

/// Deletes DICOM originals and previews that are not referenced by a row's
/// `dcmImgs` JSON field. This is intentionally dry-run by default.
///
/// Definition: a DCM orphan file is a file that has been uploaded to the disk in PB
/// yet not mentioned in the JSON.
///
///
/// It never deletes ordinary photos, never changes appointment JSON, and
/// never changes the local DICOM link registry. Call with `dryRun: false`
/// only after reviewing [DcmOrphanCleanupResult.orphanFiles].
Future<DcmOrphanCleanupResult> cleanupOrphanDcmFiles({
  bool dryRun = true,
}) async {
  final rows = await getDcmFileRows();
  final orphanFilesByRow = <String, List<String>>{};
  final deletedFilesByRow = <String, List<String>>{};
  final failuresByRow = <String, Object>{};

  for (final row in rows) {
    final orphans = orphanDcmFileNames(
      serverFiles: row.files,
      referencedDcmFiles: row.referencedDcmFiles,
    );
    if (orphans.isEmpty) continue;
    orphanFilesByRow[row.id] = orphans;
    if (dryRun) continue;

    try {
      // The initial list is only a candidate set. Re-read the row and
      // recompute against its current JSON/file state before deleting.
      final current = await _getDcmFileRow(row.id);
      final currentOrphans = orphanDcmFileNames(
        serverFiles: current.files,
        referencedDcmFiles: current.referencedDcmFiles,
      );
      if (currentOrphans.isEmpty) continue;

      await appointments.remote!.remoteRows
          .update(row.id, body: {'imgs-': currentOrphans});
      deletedFilesByRow[row.id] = currentOrphans;
      appointments.remote!.fullNamesCache[row.id] = current.files
          .where((name) => !currentOrphans.contains(name))
          .toList();
    } catch (e) {
      failuresByRow[row.id] = e;
    }
  }

  return DcmOrphanCleanupResult(
    rowsScanned: rows.length,
    orphanFilesByRow: orphanFilesByRow,
    deletedFilesByRow: deletedFilesByRow,
    failuresByRow: failuresByRow,
  );
}

/// Fetches the server-authoritative `data` JSON and `imgs` file list for
/// every row in this store. One page contains both pieces, so callers can
/// validate many DICOM references without one request per appointment.
Future<List<RemoteDcmFileRow>> getDcmFileRows() async {
  final result = <RemoteDcmFileRow>[];
  var page = 1;
  while (true) {
    final pageResult = await appointments.remote!.remoteRows.getList(
      filter: 'store="${appointments.remote!.storeName}"',
      sort: 'id',
      perPage: 900,
      page: page,
      fields: 'id,data,imgs',
    );
    for (final item in pageResult.items) {
      result.add(RemoteDcmFileRow(
        id: item.id,
        data: _asJsonMap(item.data['data']),
        files: List<String>.from(item.data['imgs'] ?? const <String>[]),
      ));
    }
    if (page >= pageResult.totalPages) break;
    page++;
  }
  for (final row in result) {
    appointments.remote!.fullNamesCache[row.id] = List<String>.from(row.files);
  }
  return result;
}

Map<String, dynamic> _asJsonMap(dynamic value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {
      // An invalid row payload has no usable DICOM references.
    }
  }
  return <String, dynamic>{};
}

/// Re-reads one row immediately before destructive cleanup so references
/// added after the initial scan are not deleted from the stale snapshot.
Future<RemoteDcmFileRow> _getDcmFileRow(String rowID) async {
  final record = await appointments.remote!.remoteRows.getOne(
    rowID,
    fields: 'id,data,imgs',
  );
  final row = RemoteDcmFileRow(
    id: record.id,
    data: _asJsonMap(record.data['data']),
    files: List<String>.from(record.data['imgs'] ?? const <String>[]),
  );
  appointments.remote!.fullNamesCache[row.id] = List<String>.from(row.files);
  return row;
}

/// Server snapshot of one data row and its PocketBase file field.
class RemoteDcmFileRow {
  final String id;
  final Map<String, dynamic> data;
  final List<String> files;

  RemoteDcmFileRow({
    required this.id,
    required this.data,
    required this.files,
  });

  /// DICOM originals referenced by the row's `dcmImgs` JSON field.
  List<String> get referencedDcmFiles {
    final raw = data['dcmImgs'];
    if (raw is! List) return const <String>[];
    return raw.map((value) => value.toString()).toList();
  }
}

/// Result of an explicit DICOM orphan-file cleanup.
class DcmOrphanCleanupResult {
  final int rowsScanned;
  final Map<String, List<String>> orphanFilesByRow;
  final Map<String, List<String>> deletedFilesByRow;
  final Map<String, Object> failuresByRow;

  const DcmOrphanCleanupResult({
    required this.rowsScanned,
    required this.orphanFilesByRow,
    required this.deletedFilesByRow,
    required this.failuresByRow,
  });

  List<String> get orphanFiles =>
      orphanFilesByRow.values.expand((files) => files).toList();

  List<String> get deletedFiles =>
      deletedFilesByRow.values.expand((files) => files).toList();
}

/// Computes DICOM originals/previews present in [serverFiles] but absent
/// from the row's referenced `dcmImgs` list. Matching is case-insensitive.
/// A preview is considered owned by its original (`foo.dcm.png` belongs to
/// `foo.dcm`), so both are retained when the original is referenced.
@visibleForTesting
List<String> orphanDcmFileNames({
  required List<String> serverFiles,
  required List<String> referencedDcmFiles,
}) {
  final refs = <String>{};
  for (final name in referencedDcmFiles) {
    final lower = p.basename(name).toLowerCase();
    refs.add(lower);
    if (isDcmPreviewName(lower)) {
      refs.add(lower.substring(0, lower.length - '.png'.length));
    }
  }
  return serverFiles.where((name) {
    final lower = p.basename(name).toLowerCase();
    if (isDcmFileName(lower)) return !refs.contains(lower);
    if (isDcmPreviewName(lower)) {
      final original = lower.substring(0, lower.length - '.png'.length);
      return !refs.contains(original);
    }
    return false;
  }).toList();
}
