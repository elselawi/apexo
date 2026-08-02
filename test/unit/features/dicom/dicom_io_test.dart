import 'dart:io' as io;

import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // These tests exercise DicomIO.scanDirectory which uses dart:io.
  // They run in the Dart VM test runner (not web). On web, the conditional
  // import stub returns empty — skip there.
  final canRunIoTests = !kIsWeb;

  group('DicomIO.scanDirectory (partial-write skip)', () {
    late io.Directory tempDir;

    setUp(() async {
      if (!canRunIoTests) return;
      tempDir = await io.Directory.systemTemp.createTemp('dicom_io_test_');
    });

    tearDown(() async {
      if (!canRunIoTests) return;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'discovers .dcm files recursively',
      () async {
        if (!canRunIoTests) return;
        // Create an old .dcm file (mtime well in the past — not partial-write)
        final file1 = io.File(p.join(tempDir.path, 'scan1.dcm'));
        await file1.writeAsBytes(List.filled(1024, 0));
        // Set mtime to 1 minute ago so it's outside the 5s skip window
        await file1.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        final file2 = io.File(p.join(tempDir.path, 'subdir', 'scan2.DCM'));
        await file2.parent.create(recursive: true);
        await file2.writeAsBytes(List.filled(2048, 0));
        await file2.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        final results = await DicomIO.scanDirectory(tempDir.path);

        expect(results.length, 2);
        final paths = results.map((e) => e.path).toSet();
        expect(paths, contains(file1.path));
        expect(paths, contains(file2.path));
      },
    );

    test(
      'skips files modified within the last 5 seconds (partial-write lock)',
      () async {
        if (!canRunIoTests) return;
        // Old file — should be discovered
        final oldFile = io.File(p.join(tempDir.path, 'old.dcm'));
        await oldFile.writeAsBytes(List.filled(1024, 0));
        await oldFile.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        // Freshly-written file — should be skipped (partial-write protection)
        final freshFile = io.File(p.join(tempDir.path, 'fresh.dcm'));
        await freshFile.writeAsBytes(List.filled(1024, 0));
        // mtime is "now" — within the 5s skip window

        final results = await DicomIO.scanDirectory(tempDir.path);

        final paths = results.map((e) => e.path).toSet();
        expect(paths, contains(oldFile.path),
            reason: 'Old file should be discovered');
        expect(paths, isNot(contains(freshFile.path)),
            reason:
                'Freshly-written file should be skipped (partial-write lock protection)');
      },
    );

    test(
      'returns empty list for nonexistent directory',
      () async {
        if (!canRunIoTests) return;
        final results =
            await DicomIO.scanDirectory(p.join(tempDir.path, 'does_not_exist'));
        expect(results, isEmpty);
      },
    );

    test(
      'ignores non-.dcm files',
      () async {
        if (!canRunIoTests) return;
        final dcmFile = io.File(p.join(tempDir.path, 'image.dcm'));
        await dcmFile.writeAsBytes(List.filled(1024, 0));
        await dcmFile.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        final jpgFile = io.File(p.join(tempDir.path, 'photo.jpg'));
        await jpgFile.writeAsBytes(List.filled(1024, 0));
        await jpgFile.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        final txtFile = io.File(p.join(tempDir.path, 'notes.txt'));
        await txtFile.writeAsBytes(List.filled(100, 0));
        await txtFile.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        final results = await DicomIO.scanDirectory(tempDir.path);
        expect(results.length, 1);
        expect(results.first.path, dcmFile.path);
      },
    );

    test(
      'readBytes returns file contents',
      () async {
        if (!canRunIoTests) return;
        final file = io.File(p.join(tempDir.path, 'readable.dcm'));
        final bytes = List.filled(512, 42);
        await file.writeAsBytes(bytes);
        await file.setLastModified(
            DateTime.now().subtract(const Duration(minutes: 1)));

        final read = await DicomIO.readBytes(file.path);
        expect(read, isNotNull);
        expect(read!.length, 512);
        expect(read.every((b) => b == 42), isTrue);
      },
    );

    test(
      'readBytes returns null for nonexistent file',
      () async {
        if (!canRunIoTests) return;
        final read = await DicomIO.readBytes(p.join(tempDir.path, 'gone.dcm'));
        expect(read, isNull);
      },
    );
  });
}
