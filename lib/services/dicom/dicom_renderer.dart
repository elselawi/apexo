import 'dart:typed_data';

import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';

/// Renders PNG bytes from a parsed result via the Rust backend, headless, so it is
/// safe in background pipelines.
class DicomRendererWrapper {
  const DicomRendererWrapper();

  /// Uses the DICOM header window when center/width are null; null on failure.
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
