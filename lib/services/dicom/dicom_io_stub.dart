import 'dart:typed_data';

import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/utils/logger.dart';

/// Web / non-native no-op implementation of [DicomIOImpl].
///
/// Directory scanning is a Windows-only feature (xray software is
/// Windows-only). On web, this stub returns empty results so the app
/// compiles and runs — the DICOM import UI is never shown on web.
class DicomIOImpl {
  static Future<List<DicomFileEntry>> scanDirectory(String path) async {
    log.info(
        'DicomIOImpl.scanDirectory: no-op on this platform (path="$path")');
    return const [];
  }

  static Future<Uint8List?> readBytes(String path) async {
    log.info('DicomIOImpl.readBytes: no-op on this platform (path="$path")');
    return null;
  }
}
