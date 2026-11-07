import 'dart:typed_data';

import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/utils/logger.dart';

/// Web no-op [DicomIOImpl]: scanning is Windows-only, so this stub lets the
/// app build and run elsewhere without the DICOM import UI.
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
