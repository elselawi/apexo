import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_matched_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_unmatched_store.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/dicom/dicom_parser.dart';
import 'package:apexo/services/dicom/dicom_skipped.dart';
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Initializes the `dicom_toolkit` native (Rust/WASM) engine.
///
/// Must be called once at app startup, after `WidgetsFlutterBinding
/// .ensureInitialized()`, and before any DICOM parse / render / export call.
///
/// Wraps [DicomToolkit.init] in a `try/catch` so that a failure to load the
/// native engine does not prevent the rest of Apexo from booting. DICOM
/// features will simply be unavailable (surfaced to the user later via the
/// feature gates). All other app functionality is unaffected.
///
/// Returns `true` if initialization succeeded, `false` otherwise.
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

/// Headless export verification — confirms that `DicomExport().toPngBytes()`
/// works without an active widget surface (i.e. from a background pipeline).
///
/// This is a manual verification helper — not wired to any automated test.
///
/// Flow:
///   1. Reads the `.dcm` file at [filePath] (defaults to the shipped test
///      fixture at `test/fixtures/dicom/sample.dcm`).
///   2. Parses it with `DicomParser().parse()` (full parse: metadata + pixels).
///   3. Renders a PNG via `DicomExport().toPngBytes()` using DICOM-default
///      windowing.
///   4. Logs whether the result is non-empty and starts with the PNG magic
///      header.
///
/// On web, local file access is unavailable.
///
/// Returns `true` if headless export succeeded (non-empty PNG bytes with the
/// correct magic header), `false` otherwise. The result is also logged.
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
    if (!await file.exists()) {
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

/// Manual verification helper — scans [dirPath] for `.dcm` files and parses
/// each, logging the extracted metadata (patientName, patientId, studyDate,
/// sopInstanceUid, modality, dimensions) for valid files, and logging
/// failures to the `dicom_skipped` Hive box.
///
/// This is a **manual verification helper** — not wired to any automated
/// test (the Rust FFI library isn't loaded under `flutter test`). The user
/// triggers it from a temporary debug button or `flutter run` console call.
///
/// Defaults to `C:\dcm`. Returns
/// the number of successfully-parsed files.
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
