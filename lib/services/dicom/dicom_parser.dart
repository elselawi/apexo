import 'dart:typed_data';

import 'package:apexo/services/dicom/dicom_skipped.dart';
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';

/// Thin wrapper over `dicom_toolkit`'s parser; failures return null and are logged
/// to [DicomSkippedLog]. Use [parseMetadata] for sweeps, [parse] for pixels.
class DicomParserWrapper {
  const DicomParserWrapper();

  /// Header-only parse (no pixels, no GPU), for directory sweeps. Null on failure,
  /// logged to [DicomSkippedLog] when [sourcePath] is given.
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

  /// Full parse (metadata + pixels) for the viewer and PNG export. Null on
  /// pixel-decode failure; the file is still importable with its metadata.
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
