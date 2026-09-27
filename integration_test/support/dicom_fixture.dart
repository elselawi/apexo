// The DICOM engine, the sample X-ray the repo ships, and a watch folder with a
// copy of it in it. Everything the DICOM group needs that is not the app. §2.12.
//
// Two things the app does in `main()` have to be done here instead, because a
// test pumps `ApexoApp` itself and never runs `main()`:
//
//  * `initDicomToolkit()` loads the `dicom_toolkit` native engine. Without it
//    every parse and render call fails, so a scan finds nothing.
//  * `initializeDicomScan()` *touches* `dicomCtrl`, which is what registers the
//    scan lifecycle with the login (`login.activators['dicom']`). Without it the
//    periodic scan never starts and only the screen's manual button would work.
import 'dart:io';
import 'dart:typed_data';

import 'package:apexo/features/dicom/dicom_controller.dart' show dicomCtrl;
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_importer.dart' show DicomParsedMeta;
import 'package:apexo/services/dicom/dicom_parser.dart';
import 'package:apexo/utils/dicom_init.dart';
import 'package:flutter_test/flutter_test.dart';

abstract final class DicomFixture {
  static bool _engineStarted = false;

  /// Starts the engine and the scan lifecycle once per run, and says whether the
  /// engine came up.
  static Future<bool> startEngine() async {
    if (!_engineStarted) {
      _engineStarted = true;
      initializeDicomScan();
      return initDicomToolkit();
    }
    return true;
  }

  /// The paths the sample may be at, in the order they are tried.
  ///
  /// `flutter test integration_test/…` runs the app with the project root as its
  /// working directory, which is what makes the repo's own fixture reachable —
  /// the same file `lib/utils/dicom_init.dart`'s manual `verifyHeadlessExport`
  /// helper defaults to.
  static const _samplePaths = [
    'test/fixtures/dicom/sample.dcm',
    '../test/fixtures/dicom/sample.dcm',
  ];

  /// The shipped sample X-ray, as bytes.
  static Future<Uint8List> sampleBytes() async {
    for (final path in _samplePaths) {
      final file = File(path);
      if (file.existsSync()) return file.readAsBytes();
    }
    fail('The DICOM sample is not where this process can see it (tried '
        '${_samplePaths.join(", ")} from ${Directory.current.path}). The DICOM '
        'group needs test/fixtures/dicom/sample.dcm.');
  }

  /// What the sample says it is — read through the same parser the importer
  /// uses, so a test can create the patient the file will match instead of
  /// hard-coding a name that a new sample would break.
  static Future<({String patientName, DateTime? date})> sampleIdentity() async {
    final meta =
        await const DicomParserWrapper().parseMetadata(await sampleBytes());
    if (meta == null) {
      fail('The DICOM sample did not parse. Either the `dicom_toolkit` engine '
          'is not up, or test/fixtures/dicom/sample.dcm is not a DICOM file.');
    }
    // Through the app's own mapping, so this is the identity the matcher will
    // see (`dcmDate` is the toolkit's `bestDate`).
    final parsed = DicomParsedMeta.fromDicomMetadata(meta);
    return (patientName: parsed.patientName, date: parsed.dcmDate);
  }

  /// A fresh folder holding a copy of the sample, aged past the importer's
  /// partial-write guard (a file modified in the last 5 seconds is skipped as
  /// possibly still being written), and configured as the watch folder.
  ///
  /// Returns the folder; the caller deletes it (see [cleanup]).
  static Future<Directory> watchFolderWithSample({
    String name = 'e2e-xray.dcm',
  }) async {
    final dir = await Directory.systemTemp.createTemp('apexo-e2e-dicom-');
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(await sampleBytes());
    await file.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    return dir;
  }

  /// Points the clinic's settings at [dirs] and lets the controller apply them.
  ///
  /// This branch has no single "the folders changed" step: the settings are
  /// plain fields, and the screen's own reaction to a change is to stop the
  /// timer, start it again when there is somewhere to look, and scan once.
  static Future<void> watch(List<String> dirs) async {
    globalSettings.dicomWatchDirs = dirs;
    dicomCtrl.stopPeriodicScan();
    if (dirs.isNotEmpty) dicomCtrl.startPeriodicScan();
    await dicomCtrl.refresh();
  }

  /// Puts the watch folders back and deletes the temp folders.
  ///
  /// Every later group shares this clinic: a leftover watch folder would have
  /// the DICOM screen scanning a deleted directory, and (`auto-import` is on by
  /// default) a leftover setting is a scan running behind every test.
  static Future<void> cleanup(Iterable<Directory> dirs) async {
    globalSettings.dicomWatchDirs = const <String>[];
    dicomCtrl.stopPeriodicScan();
    for (final dir in dirs) {
      if (dir.existsSync()) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // best effort: a temp folder the OS will collect anyway
        }
      }
    }
  }
}
