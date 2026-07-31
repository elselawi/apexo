import 'dart:typed_data';

import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';

/// Wraps `dicom_toolkit`'s [DicomExport] to render PNG preview bytes from a
/// fully-parsed [DicomParseResult].
///
/// Headless export is verified to work (no widget surface required) —
/// renders PNG bytes directly via the Rust backend. Safe to call from
/// background pipelines (e.g., the lazy PNG generation task queue).
class DicomRendererWrapper {
  const DicomRendererWrapper();

  /// Renders [result] to PNG bytes using the given windowing.
  ///
  /// [windowCenter] / [windowWidth] default to the DICOM header values when
  /// null. Returns `null` on any failure (caller logs to `dicom_skipped`).
  Future<Uint8List?> renderPreviewPng(
    final DicomParseResult result, {
    final double? windowCenter,
    final double? windowWidth,
  }) async {
    try {
      const exporter = DicomExport();
      return await exporter.toPngBytes(
        result,
        windowCenter: windowCenter,
        windowWidth: windowWidth,
      );
    } catch (e, s) {
      logger('DicomRendererWrapper.renderPreviewPng error: $e', s, 2);
      return null;
    }
  }
}

/// Singleton instance used throughout the app.
const dicomRenderer = DicomRendererWrapper();
