import 'dart:typed_data';

import 'package:apexo/services/dicom/dicom_skipped.dart';
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';

/// Thin wrapper around `dicom_toolkit`'s [DicomParser].
///
/// All methods return `null` on failure (graceful skipping — failures are
/// Parse failures are logged to the `dicom_skipped` Hive box with the
/// optional [sourcePath] and the failure reason, so the dentist can see
/// why a file was skipped via the DICOM screen's "Skipped files" section.
///
/// Use [parseMetadata] for the fast header-only scan (no GPU, no pixel
/// decode) — perfect for directory sweeps. Use [parse] for the full parse
/// (metadata + pixels) needed by the viewer and PNG export.
class DicomParserWrapper {
  const DicomParserWrapper();

  /// Parses only the DICOM metadata (28 typed fields). Fast — skips pixel
  /// extraction via `skipPixels: true` in the Rust engine. No GPU needed.
  ///
  /// Returns `null` on any parse failure. If [sourcePath] is provided, the
  /// failure is logged to [DicomSkippedLog] with the path and reason.
  Future<DicomMetadata?> parseMetadata(
    final Uint8List bytes, {
    final String? sourcePath,
  }) async {
    try {
      const parser = DicomParser();
      return await parser.parseMetadata(bytes);
    } catch (e, s) {
      final reason = 'parseMetadata failed: $e';
      logger('DicomParserWrapper.parseMetadata error: $e', s, 2);
      if (sourcePath != null) {
        try {
          await dicomSkippedLog.add(path: sourcePath, reason: reason);
        } catch (_) {
          // best-effort logging — never crash on the logging path
        }
      }
      return null;
    }
  }

  /// Full parse: metadata + pixel data. Needed for the viewer and PNG export.
  ///
  /// Returns `null` on pixel-decode failure (e.g., unsupported compressed
  /// transfer syntax). The caller may still have metadata from a prior
  /// [parseMetadata] call — in that case the file is still importable (the
  /// `.dcm` is preserved; the viewer will show an error per-file if it
  /// can't decode).
  Future<DicomParseResult?> parse(
    final Uint8List bytes, {
    final String? sourcePath,
  }) async {
    try {
      const parser = DicomParser();
      return await parser.parse(bytes);
    } catch (e, s) {
      final reason = 'parse (full) failed: $e';
      logger('DicomParserWrapper.parse error: $e', s, 2);
      if (sourcePath != null) {
        try {
          await dicomSkippedLog.add(path: sourcePath, reason: reason);
        } catch (_) {}
      }
      return null;
    }
  }
}

/// Singleton instance used throughout the app.
const dicomParser = DicomParserWrapper();
