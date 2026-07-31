import 'dart:io' as io;
import 'dart:typed_data';

import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Native (`dart:io`) implementation of [DicomIOImpl].
///
/// Recursively lists `.dcm` files, stat-only (no file opens). Skips files
/// modified within the last 5 seconds
///
/// On non-Windows native platforms (Android/iOS/macOS) this compiles and
/// functions if given a path, but the UI never invokes it there — scanning
/// is Windows-only by design.
class DicomIOImpl {
  /// Files modified within this window are skipped during a scan.
  static const _partialWriteSkipWindow = Duration(seconds: 5);

  /// Extensions recognized as DICOM (case-insensitive).
  static const _dcmExtensions = {'.dcm', '.dicom'};

  static Future<List<DicomFileEntry>> scanDirectory(String path) async {
    final results = <DicomFileEntry>[];
    final dir = io.Directory(path);

    if (!await dir.exists()) {
      log.warning(
          'DicomIOImpl.scanDirectory: directory does not exist: "$path"');
      return results;
    }

    final now = DateTime.now();

    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! io.File) continue;

        final ext = p.extension(entity.path).toLowerCase();
        if (!_dcmExtensions.contains(ext)) continue;

        io.FileStat stat;
        try {
          stat = await entity.stat();
        } catch (e, s) {
          // stat failed (file deleted between list and stat, or permission)
          logger(
              'DicomIOImpl.scanDirectory: stat failed for "${entity.path}": $e',
              s,
              2);
          continue;
        }

        // Partial-write lock protection: skip files that were
        // modified within the last few seconds. The XRay software
        // may still be writing; we'll pick them up on the next resync.
        if (now.difference(stat.modified) < _partialWriteSkipWindow) {
          log.info(
            'DicomIOImpl.scanDirectory: skipping (in-progress, deferred to next scan): "${entity.path}"',
          );
          continue;
        }

        results.add(DicomFileEntry(
          path: entity.path,
          mtime: stat.modified,
          size: stat.size,
        ));
      }
    } catch (e, s) {
      logger('DicomIOImpl.scanDirectory: listing failed for "$path": $e', s, 2);
    }

    return results;
  }

  static Future<Uint8List?> readBytes(String path) async {
    try {
      final file = io.File(path);
      return await file.readAsBytes();
    } catch (e, s) {
      // Common: exclusive lock during write, or file deleted since scan.
      logger('DicomIOImpl.readBytes: failed for "$path": $e', s, 2);
      return null;
    }
  }
}
