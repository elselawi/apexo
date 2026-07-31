import 'dart:typed_data';

import 'dicom_io_stub.dart' if (dart.library.io) 'dicom_io_native.dart';

/// A stat-only entry for a `.dcm` file discovered during a directory scan.
///
/// No file bytes are read when producing this — just a `File.stat()` call.
/// The [DicomFileCache] keys on `path` and checks `mtime + size`
/// to decide whether the file can be skipped entirely on the next scan.
class DicomFileEntry {
  /// Absolute path to the `.dcm` file.
  final String path;

  /// File's last-modified timestamp (from `File.stat().modified`).
  final DateTime mtime;

  /// File size in bytes (from `File.stat().size`).
  final int size;

  const DicomFileEntry({
    required this.path,
    required this.mtime,
    required this.size,
  });

  @override
  String toString() =>
      'DicomFileEntry(path: $path, mtime: $mtime, size: $size)';
}

/// Conditional-import facade for native filesystem access (directory scan +
/// byte reads). Web gets a no-op stub; native gets the `dart:io` impl.
///
/// **Platform split** (per plan): scanning is only invoked on Windows, but
/// the conditional import compiles on all platforms so the app builds
/// everywhere. The stub returns empty/null on web.
abstract class DicomIO {
  /// Recursively lists all `.dcm` files under [path], returning stat-only
  /// entries (no file opens). Files modified within the last 5 seconds are
  /// skipped (partial-write lock protection — files modified <5s ago).
  static Future<List<DicomFileEntry>> scanDirectory(String path) =>
      DicomIOImpl.scanDirectory(path);

  /// Reads all bytes from the file at [path]. Returns null on failure (e.g.,
  /// exclusive lock during write, file deleted between scan and read).
  static Future<Uint8List?> readBytes(String path) =>
      DicomIOImpl.readBytes(path);
}
