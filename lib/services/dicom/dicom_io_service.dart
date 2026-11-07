import 'dart:typed_data';

import 'dicom_io_stub.dart' if (dart.library.io) 'dicom_io_native.dart';

/// A stat-only entry for a `.dcm` file; no bytes are read. [DicomFileCache]
/// keys on `path` and reuses an entry when `mtime` and `size` both match.
class DicomFileEntry {
  const DicomFileEntry({
    required this.path,
    required this.mtime,
    required this.size,
  });

  /// Absolute path to the `.dcm` file.
  final String path;

  /// File's last-modified timestamp (from `File.stat().modified`).
  final DateTime mtime;

  /// File size in bytes (from `File.stat().size`).
  final int size;

  @override
  String toString() =>
      'DicomFileEntry(path: $path, mtime: $mtime, size: $size)';
}

/// Conditional-import facade for filesystem access: native gets the `dart:io`
/// impl, web a no-op stub, so the app builds on both.
abstract class DicomIO {
  /// Recursively lists `.dcm` files under [path] as stat-only entries; files
  /// modified in the last 5 seconds are skipped (partial-write protection).
  static Future<List<DicomFileEntry>> scanDirectory(String path) =>
      DicomIOImpl.scanDirectory(path);

  /// Returns null on failure, e.g. an exclusive write lock or the file being
  /// deleted between the scan and the read.
  static Future<Uint8List?> readBytes(String path) =>
      DicomIOImpl.readBytes(path);
}
