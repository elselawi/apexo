import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/dicom/dicom_parser.dart';
import 'package:apexo/services/dicom/dicom_skipped.dart';
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Touches [dicomCtrl] so the `login.activators['dicom']` scan hook is registered
/// before `login.activate()` runs; a lazy top-level `final` is not created on import.
DicomController initializeDicomScan() => dicomCtrl;

/// Loads the native DICOM engine. Must run after `ensureInitialized()` and
/// before any DICOM call; failure is non-fatal, so the app still boots.
Future<bool> initDicomToolkit() async {
  try {
    await DicomToolkit.init();
    log.info('dicom_toolkit engine initialized successfully');
    return true;
  } catch (e, s) {
    // Non-fatal: the app continues to run; DICOM features degrade gracefully.
    logger('Failed to initialize dicom_toolkit engine: $e', s, 2);
    return false;
  }
}

/// PNG magic header (first 8 bytes of any valid PNG file).
const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Manual check, not wired to an automated test, that PNG export works without
/// an active widget surface.
Future<bool> verifyHeadlessExport({String? filePath}) async {
  if (kIsWeb) {
    log.warning(
      'verifyHeadlessExport: skipped on web (no local file access).',
    );
    return false;
  }

  final path = filePath ??
      'test${Platform.pathSeparator}fixtures${Platform.pathSeparator}dicom${Platform.pathSeparator}sample.dcm';

  log.info('verifyHeadlessExport: reading DICOM file at "$path"');
  final Uint8List bytes;
  try {
    final file = File(path);
    if (!file.existsSync()) {
      log.severe(
        'verifyHeadlessExport: file not found at "$path". '
        'Pass an explicit filePath, or run via `flutter run` from the '
        'project root so the default test fixture is reachable.',
      );
      return false;
    }
    bytes = await file.readAsBytes();
  } catch (e, s) {
    log.severe('verifyHeadlessExport: failed to read file: $e');
    logger('verifyHeadlessExport read error: $e', s, 2);
    return false;
  }

  log.info('verifyHeadlessExport: read ${bytes.length} bytes; parsing...');
  final DicomParseResult parseResult;
  try {
    const parser = DicomParser();
    parseResult = await parser.parse(bytes);
    log.info(
      'verifyHeadlessExport: parse OK — '
      'patientName="${parseResult.metadata.patientName}", '
      'modality="${parseResult.metadata.modality}", '
      '${parseResult.metadata.width}x${parseResult.metadata.height}',
    );
  } catch (e, s) {
    log.severe('verifyHeadlessExport: DicomParser.parse() failed: $e');
    logger('verifyHeadlessExport parse error: $e', s, 2);
    return false;
  }

  log.info('verifyHeadlessExport: exporting PNG (headless)...');
  try {
    const exporter = DicomExport();
    final png = await exporter.toPngBytes(parseResult);

    final nonEmpty = png.isNotEmpty;
    final magicOk = png.length >= 8 &&
        List.generate(8, (i) => png[i] == _pngMagic[i]).every((x) => x);

    if (nonEmpty && magicOk) {
      log.info(
        'verifyHeadlessExport: SUCCESS — headless export works. '
        'PNG is ${png.length} bytes, magic header OK.',
      );
      return true;
    } else {
      log.severe('verifyHeadlessExport: FAIL — png nonEmpty=$nonEmpty, '
          'magicOk=$magicOk, length=${png.length}. ');
      return false;
    }
  } catch (e, s) {
    log.severe('verifyHeadlessExport: DicomExport.toPngBytes() failed: $e');
    logger('verifyHeadlessExport export error: $e', s, 2);
    log.severe(
      'verifyHeadlessExport: headless export is NOT supported.',
    );
    return false;
  }
}

/// Manual scan/parse check for a directory of `.dcm` files, not wired to an
/// automated test because the Rust FFI library isn't loaded under `flutter test`.
Future<int> verifyDicomScan({String dirPath = r'C:\dcm'}) async {
  if (kIsWeb) {
    log.warning('verifyDicomScan: skipped on web (no local file access).');
    return 0;
  }

  log.info('verifyDicomScan: scanning "$dirPath"...');

  final entries = await DicomIO.scanDirectory(dirPath);
  log.info('verifyDicomScan: discovered ${entries.length} .dcm file(s).');

  if (entries.isEmpty) {
    log.warning('verifyDicomScan: no .dcm files found in "$dirPath".');
    return 0;
  }

  var successCount = 0;
  for (final entry in entries) {
    log.info('verifyDicomScan: reading "${entry.path}" '
        '(${entry.size} bytes, mtime=${entry.mtime})...');
    final bytes = await DicomIO.readBytes(entry.path);
    if (bytes == null) {
      log.severe('verifyDicomScan: ❌ readBytes failed for "${entry.path}"');
      continue;
    }

    final meta = await dicomParser.parseMetadata(bytes, sourcePath: entry.path);
    if (meta == null) {
      log.severe(
          'verifyDicomScan: ❌ parseMetadata returned null for "${entry.path}" '
          '(logged to dicom_skipped)');
      continue;
    }

    successCount++;
    log.info('verifyDicomScan: ✅ OK "${entry.path}"');
    log.info('   patientName:    "${meta.patientName}"');
    log.info('   patientId:      "${meta.patientId}"');
    log.info('   studyDate:      "${meta.studyDate}"');
    log.info('   sopInstanceUid: "${meta.sopInstanceUid}"');
    log.info('   modality:       "${meta.modality}"');
    log.info('   dimensions:     ${meta.width}x${meta.height}');
    log.info('   dedupKey:       "${dedupKey(meta)}"');
  }

  // Report skipped files.
  final skipped = await dicomSkippedLog.all;
  log.info('verifyDicomScan: ${skipped.length} skipped-file entry(ies):');
  for (final s in skipped) {
    log.info('   - "${s.path}" — reason: ${s.reason}');
  }

  log.info(
      'verifyDicomScan: DONE — $successCount/${entries.length} parsed OK.');
  return successCount;
}
