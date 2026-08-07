import 'dart:async';
import 'dart:convert';

import 'package:apexo/core/save_remote.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/dicom/dicom_orphans_cleaner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePocketBaseApi {
  final requests = <http.Request>[];
  final requestBodies = <String>[];
  final pageRows = <int, List<String>>{
    1: ['row-1']
  };
  final filesByRow = <String, List<String>>{};
  final revalidatedFilesByRow = <String, List<String>>{};
  final rowDataByRow = <String, dynamic>{};
  final revalidatedDataByRow = <String, dynamic>{};
  final nullImgsRows = <String>{};
  final omitImgsRows = <String>{};
  final failedDeleteRows = <String>{};
  final getOneCountByRow = <String, int>{};
  final uploadedNamesByRow = <String, List<String>>{};

  List<String> files = [];
  dynamic rowData = <String, dynamic>{};
  dynamic revalidatedRowData;
  int updateCount = 0;
  int getOneCount = 0;
  bool returnEmptyUploadList = false;
  bool disappearRetainedFilesAfterDelete = false;
  bool revalidateOnFirstGet = false;
  bool returnOriginalAndPreviewAfterUpload = false;
  Completer<void>? uploadGate;
  Completer<void>? uploadStarted;
  String _lastUploadedName = '';

  MockClient get client => MockClient(_handle);

  List<String> _filesFor(String rowID, {bool revalidated = false}) {
    if (revalidated &&
        revalidatedFilesByRow.containsKey(rowID) &&
        (revalidateOnFirstGet || (getOneCountByRow[rowID] ?? 0) > 1)) {
      return revalidatedFilesByRow[rowID]!;
    }
    return filesByRow[rowID] ?? (rowID == 'row-1' ? files : const <String>[]);
  }

  dynamic _dataFor(String rowID, {bool revalidated = false}) {
    final values = revalidated ? revalidatedDataByRow : rowDataByRow;
    if (values.containsKey(rowID)) return values[rowID];
    if (rowID == 'row-1') {
      final value = revalidated ? revalidatedRowData : rowData;
      if (revalidated && value != null) return value;
      return rowData;
    }
    return <String, dynamic>{};
  }

  String _rowID(Uri uri) => uri.pathSegments.last;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/api/health')) {
      return _json({'code': 200, 'message': 'ok'});
    }

    if (request.method == 'GET' && path.contains('/records')) {
      final isSingle = path.contains('/records/');
      if (isSingle) {
        final rowID = _rowID(request.url);
        getOneCount++;
        getOneCountByRow[rowID] = (getOneCountByRow[rowID] ?? 0) + 1;
        return _json(_record(
          rowID,
          _dataFor(rowID, revalidated: true),
          _filesFor(rowID, revalidated: true),
        ));
      }

      final page =
          int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      final ids = pageRows[page] ?? const <String>[];
      final totalPages = pageRows.keys.isEmpty
          ? 1
          : pageRows.keys.reduce((a, b) => a > b ? a : b);
      return _json({
        'page': page,
        'perPage': 900,
        'totalItems': pageRows.values.expand((ids) => ids).length,
        'totalPages': totalPages,
        'items': [
          for (final rowID in ids)
            _record(rowID, _dataFor(rowID), _filesFor(rowID)),
        ],
      });
    }

    if (request.method == 'PATCH' && path.contains('/records/')) {
      final rowID = _rowID(request.url);
      updateCount++;
      requestBodies.add(request.body);
      if (request.headers['content-type']?.startsWith('multipart/') == true) {
        if (uploadStarted != null && !uploadStarted!.isCompleted) {
          uploadStarted!.complete();
        }
        if (uploadGate != null) await uploadGate!.future;
        if (returnEmptyUploadList) {
          return _json(_record(rowID, _dataFor(rowID), const <String>[]));
        }
        // Extract filename from the multipart Content-Disposition header.
        final nameMatch =
            RegExp(r'filename="([^"]+)"').firstMatch(request.body);
        final filename = nameMatch?.group(1) ?? 'unknown.bin';
        _lastUploadedName = filename;
        uploadedNamesByRow.putIfAbsent(rowID, () => []).add(filename);
        final updated = returnOriginalAndPreviewAfterUpload
            ? <String>[filename, '$filename.png']
            : [..._filesFor(rowID), filename];
        filesByRow[rowID] = updated;
        if (rowID == 'row-1') files = updated;
        return _json(_record(rowID, _dataFor(rowID), updated));
      }

      if (failedDeleteRows.contains(rowID)) {
        return _json({'code': 500, 'message': 'delete failed'}, 500);
      }
      if (request.body.isNotEmpty) {
        final decoded = jsonDecode(request.body) as Map<String, dynamic>;
        final removed = decoded['imgs-'];
        if (removed is List) {
          final updated = _filesFor(rowID)
              .where((name) => !removed.contains(name))
              .toList();
          filesByRow[rowID] =
              disappearRetainedFilesAfterDelete ? <String>[] : updated;
          if (revalidatedFilesByRow.containsKey(rowID) &&
              disappearRetainedFilesAfterDelete) {
            revalidatedFilesByRow[rowID] = filesByRow[rowID]!;
          }
          if (rowID == 'row-1') files = filesByRow[rowID]!;
        }
      }
      if (returnEmptyUploadList) {
        return _json(_record(rowID, _dataFor(rowID), const <String>[]));
      }
      return _json(_record(rowID, _dataFor(rowID), _filesFor(rowID)));
    }

    return http.Response('not found', 404);
  }

  Map<String, dynamic> _record(
    String rowID,
    dynamic data,
    List<String> rowFiles,
  ) {
    final record = <String, dynamic>{
      'id': rowID,
      'collectionId': 'data',
      'collectionName': 'data',
      'data': data,
    };
    if (!omitImgsRows.contains(rowID)) {
      record['imgs'] =
          nullImgsRows.contains(rowID) ? null : List<String>.from(rowFiles);
    }
    return record;
  }

  http.Response _json(Object body, [int statusCode = 200]) => http.Response(
        jsonEncode(body),
        statusCode,
        headers: const {'content-type': 'application/json'},
      );
}

void main() {
  late _FakePocketBaseApi api;
  late SaveRemote remote;
  late SaveRemote? previousAppointmentsRemote;
  late MockClient client;

  setUp(() {
    api = _FakePocketBaseApi();
    client = api.client;
    final pb = PocketBase(
      'http://fake-pocketbase',
      httpClientFactory: () => client,
    );
    previousAppointmentsRemote = appointments.remote;
    remote = SaveRemote(storeName: 'appointments', pbInstance: pb);
    remote.timer?.cancel();
    // dicom_orphans_cleaner.dart operates on the appointments store's global
    // remote rather than on a SaveRemote argument.
    appointments.remote = remote;
  });

  tearDown(() {
    appointments.remote = previousAppointmentsRemote;
    remote.timer?.cancel();
    client.close();
  });

  group('authoritative file retrieval', () {
    test('getFileNames retrieves authoritative files and refreshes cache',
        () async {
      api.files = ['server.dcm', 'server.dcm.png'];
      remote.fullNamesCache['row-1'] = ['stale.dcm'];

      final names = await remote.getFileNames('row-1');

      expect(names, ['server.dcm', 'server.dcm.png']);
      expect(remote.fullNamesCache['row-1'], ['server.dcm', 'server.dcm.png']);
      expect(api.getOneCountByRow['row-1'], 1);
    });

    test('getFileNames useCache avoids a request and returns a defensive copy',
        () async {
      remote.fullNamesCache['row-1'] = ['cached.dcm'];

      final names = await remote.getFileNames('row-1', useCache: true);
      names.add('mutated-locally.dcm');

      expect(names, ['cached.dcm', 'mutated-locally.dcm']);
      expect(remote.fullNamesCache['row-1'], ['cached.dcm']);
      expect(api.getOneCount, 0);
    });

    test('getFileNames handles absent and null imgs fields', () async {
      api.omitImgsRows.add('row-1');
      expect(await remote.getFileNames('row-1'), isEmpty);

      api.nullImgsRows.add('row-1');
      expect(await remote.getFileNames('row-1'), isEmpty);
      expect(remote.fullNamesCache['row-1'], isEmpty);
    });

    test('getDcmFileRows decodes map, string, and invalid row data', () async {
      api.rowData = jsonEncode({
        'dcmImgs': ['scan.dcm']
      });
      api.files = ['scan.dcm'];

      final rows = await getDcmFileRows();

      expect(rows, hasLength(1));
      expect(rows.single.id, 'row-1');
      expect(rows.single.data, {
        'dcmImgs': ['scan.dcm']
      });
      expect(rows.single.files, ['scan.dcm']);
      expect(rows.single.referencedDcmFiles, ['scan.dcm']);
      expect(remote.fullNamesCache['row-1'], ['scan.dcm']);

      api.rowData = '{not valid json';
      final invalidRows = await getDcmFileRows();
      expect(invalidRows.single.data, isEmpty);
      expect(invalidRows.single.referencedDcmFiles, isEmpty);
    });

    test(
        'getDcmFileRows paginates, preserves row identity, and caches each row',
        () async {
      api.pageRows
        ..clear()
        ..addAll({
          1: ['row-1'],
          2: ['row-2']
        });
      api.filesByRow['row-1'] = ['one.dcm'];
      api.filesByRow['row-2'] = ['two.dcm', 'two.dcm.png'];
      api.rowDataByRow['row-1'] = {
        'dcmImgs': ['one.dcm']
      };
      api.rowDataByRow['row-2'] = jsonEncode({
        'dcmImgs': ['two.dcm']
      });

      final rows = await getDcmFileRows();

      expect(rows.map((row) => row.id), ['row-1', 'row-2']);
      expect(rows[0].files, ['one.dcm']);
      expect(rows[1].files, ['two.dcm', 'two.dcm.png']);
      expect(rows[1].referencedDcmFiles, ['two.dcm']);
      expect(remote.fullNamesCache, {
        'row-1': ['one.dcm'],
        'row-2': ['two.dcm', 'two.dcm.png'],
      });
      final listRequests = api.requests
          .where((request) =>
              request.method == 'GET' &&
              request.url.path.endsWith('/api/collections/data/records'))
          .toList();
      expect(listRequests, hasLength(2));
      expect(listRequests.map((request) => request.url.queryParameters['page']),
          ['1', '2']);
      expect(
          listRequests.every((request) =>
              request.url.queryParameters['filter'] == 'store="appointments"'),
          isTrue);
    });

    test('getImageLink returns null when the server has no files', () async {
      final link = await remote.getImageLink('row-1', 'missing.dcm', false);

      expect(link, isNull);
    });

    test(
        'getImageLink uses exact DICOM identity and never crosses original/preview',
        () async {
      api.files = ['scan.dcm', 'scan.dcm.png'];

      final original = await remote.getImageLink('row-1', 'scan.dcm', false);
      final preview = await remote.getImageLink('row-1', 'scan.dcm.png', false);

      expect(original, 'http://fake-pocketbase/api/files/data/row-1/scan.dcm');
      expect(
          preview, 'http://fake-pocketbase/api/files/data/row-1/scan.dcm.png');

      api.files = ['scan.dcm.png'];
      remote.fullNamesCache.clear();
      expect(await remote.getImageLink('row-1', 'scan.dcm', false), isNull);

      api.files = ['scan.dcm'];
      remote.fullNamesCache.clear();
      expect(await remote.getImageLink('row-1', 'scan.dcm.png', false), isNull);
    });

    test('getImageLink retains ordinary attachment fallback behavior',
        () async {
      api.files = ['photo_hash.jpg'];

      final link = await remote.getImageLink('row-1', 'photo', false);

      expect(
          link, 'http://fake-pocketbase/api/files/data/row-1/photo_hash.jpg');
    });

    test('getImageLink refreshes a stale ordinary-image cache miss', () async {
      api.files = ['photo_hash.jpg'];
      remote.fullNamesCache['row-1'] = ['stale_attachment.jpg'];

      final link = await remote.getImageLink('row-1', 'photo', true);

      expect(
          link, 'http://fake-pocketbase/api/files/data/row-1/photo_hash.jpg');
      expect(remote.fullNamesCache['row-1'], ['photo_hash.jpg']);
      expect(api.getOneCountByRow['row-1'], 1);
    });
  });

  group('orphan cleanup mutation safety', () {
    test('dry-run reports candidates without updating PocketBase', () async {
      api.files = ['orphan.dcm', 'orphan.dcm.png', 'photo.jpg'];
      api.rowData = {'dcmImgs': []};

      final result = await cleanupOrphanDcmFiles();

      expect(result.rowsScanned, 1);
      expect(result.orphanFiles, ['orphan.dcm', 'orphan.dcm.png']);
      expect(result.deletedFiles, isEmpty);
      expect(api.updateCount, 0);
    });

    test('destructive cleanup revalidates and skips a newly referenced file',
        () async {
      api.files = ['late.dcm'];
      api.rowData = {'dcmImgs': []};
      api.revalidatedRowData = {
        'dcmImgs': ['late.dcm']
      };

      final result = await cleanupOrphanDcmFiles(dryRun: false);

      expect(result.orphanFiles, ['late.dcm']);
      expect(result.deletedFiles, isEmpty);
      expect(result.failuresByRow, isEmpty);
      expect(api.updateCount, 0);
    });

    test('destructive cleanup deletes only current DICOM orphans', () async {
      api.files = ['orphan.dcm', 'orphan.dcm.png', 'photo.jpg'];
      api.rowData = {'dcmImgs': []};
      api.revalidatedRowData = {'dcmImgs': []};

      final result = await cleanupOrphanDcmFiles(dryRun: false);

      expect(result.deletedFiles, ['orphan.dcm', 'orphan.dcm.png']);
      expect(api.files, ['photo.jpg']);
      expect(api.updateCount, 1);
    });

    test('dry-run scans all pages without re-reading or mutating rows',
        () async {
      api.pageRows
        ..clear()
        ..addAll({
          1: ['row-1'],
          2: ['row-2']
        });
      api.filesByRow['row-1'] = ['one.dcm', 'one.dcm.png'];
      api.filesByRow['row-2'] = ['two.dicom', 'two.dicom.png', 'ordinary.jpg'];
      api.rowDataByRow['row-1'] = {'dcmImgs': []};
      api.rowDataByRow['row-2'] = {
        'dcmImgs': ['two.dicom']
      };

      final result = await cleanupOrphanDcmFiles();

      expect(result.rowsScanned, 2);
      expect(result.orphanFilesByRow, {
        'row-1': ['one.dcm', 'one.dcm.png'],
      });
      expect(result.deletedFilesByRow, isEmpty);
      expect(result.failuresByRow, isEmpty);
      expect(api.updateCount, 0);
      expect(api.getOneCount, 0);
      expect(remote.fullNamesCache, {
        'row-1': ['one.dcm', 'one.dcm.png'],
        'row-2': ['two.dicom', 'two.dicom.png', 'ordinary.jpg'],
      });
      expect(api.rowDataByRow['row-2'], {
        'dcmImgs': ['two.dicom']
      });
    });

    test('cleanup recomputes the latest file list before deletion', () async {
      api.files = ['old-orphan.dcm'];
      api.rowData = {'dcmImgs': []};
      api.revalidatedFilesByRow['row-1'] = [
        'new-orphan.dcm',
        'new-orphan.dcm.png',
        'ordinary.jpg',
      ];
      api.revalidateOnFirstGet = true;
      api.revalidatedDataByRow['row-1'] = {'dcmImgs': []};

      final result = await cleanupOrphanDcmFiles(dryRun: false);

      expect(result.orphanFiles, ['old-orphan.dcm']);
      expect(result.deletedFiles, ['new-orphan.dcm', 'new-orphan.dcm.png']);
      expect(api.files, ['old-orphan.dcm']);
      expect(remote.fullNamesCache['row-1'], ['ordinary.jpg']);
      expect(jsonDecode(api.requestBodies.single)['imgs-'], [
        'new-orphan.dcm',
        'new-orphan.dcm.png',
      ]);
    });

    test(
        'cleanup leaves appointment JSON unchanged and updates cache after success',
        () async {
      final originalData = {
        'dcmImgs': ['kept.dcm'],
        'notes': 'must remain unchanged',
      };
      api.files = ['kept.dcm', 'orphan.dcm', 'orphan.dcm.png'];
      api.rowData = originalData;
      api.revalidatedRowData = originalData;

      final result = await cleanupOrphanDcmFiles(dryRun: false);

      expect(result.failuresByRow, isEmpty);
      expect(api.rowData, originalData);
      expect(api.files, ['kept.dcm']);
      expect(remote.fullNamesCache['row-1'], ['kept.dcm']);
    });

    test('cleanup records a per-row deletion failure and continues', () async {
      api.pageRows
        ..clear()
        ..addAll({
          1: ['row-1', 'row-2']
        });
      api.filesByRow['row-1'] = ['failed.dcm'];
      api.filesByRow['row-2'] = ['success.dcm', 'success.dcm.png'];
      api.rowDataByRow['row-1'] = {'dcmImgs': []};
      api.rowDataByRow['row-2'] = {'dcmImgs': []};
      api.failedDeleteRows.add('row-1');

      final result = await cleanupOrphanDcmFiles(dryRun: false);

      expect(result.rowsScanned, 2);
      expect(result.orphanFilesByRow, {
        'row-1': ['failed.dcm'],
        'row-2': ['success.dcm', 'success.dcm.png'],
      });
      expect(result.deletedFilesByRow, {
        'row-2': ['success.dcm', 'success.dcm.png'],
      });
      expect(result.failuresByRow.keys, {'row-1'});
      expect(result.failuresByRow['row-1'], isA<Object>());
      expect(api.filesByRow['row-1'], ['failed.dcm']);
      expect(api.filesByRow['row-2'], isEmpty);
      expect(remote.fullNamesCache['row-1'], ['failed.dcm']);
      expect(remote.fullNamesCache['row-2'], isEmpty);
    });

    test('cleanup does not mutate rows that have no DICOM orphans', () async {
      api.files = ['kept.dcm', 'kept.dcm.png', 'photo.jpg'];
      api.rowData = {
        'dcmImgs': ['kept.dcm']
      };

      final result = await cleanupOrphanDcmFiles(dryRun: false);

      expect(result.orphanFiles, isEmpty);
      expect(result.deletedFiles, isEmpty);
      expect(result.failuresByRow, isEmpty);
      expect(api.updateCount, 0);
      expect(api.files, ['kept.dcm', 'kept.dcm.png', 'photo.jpg']);
    });
  });

  group('upload and delete edge cases', () {
    test('empty PocketBase upload response is rejected', () async {
      api.returnEmptyUploadList = true;
      api.files = ['existing.dcm'];
      api.rowData = {'dcmImgs': []};

      await expectLater(
        remote.uploadImage(
          rowID: 'row-1',
          filename: 'scan.dcm',
          predefinedMultipart: http.MultipartFile.fromString(
            'imgs+',
            'bytes',
            filename: 'scan.dcm',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('deleting a DICOM original also deletes its preview', () async {
      api.files = ['scan.dcm', 'scan.dcm.png'];
      api.rowData = {'dcmImgs': []};

      final deleted = await remote.deleteImage('row-1', 'scan.dcm');

      expect(deleted, isTrue);
      expect(api.files, isEmpty);
      expect(remote.fullNamesCache['row-1'], isEmpty);
      expect(api.updateCount, 1);
    });

    test('deleting a DICOM original deletes a mixed-case preview name',
        () async {
      api.files = ['SCAN.DCM', 'SCAN.DCM.PNG'];
      api.rowData = {'dcmImgs': []};

      final deleted = await remote.deleteImage('row-1', 'scan.dcm');

      expect(deleted, isTrue);
      expect(api.files, isEmpty);
      expect(remote.fullNamesCache['row-1'], isEmpty);
      expect(api.updateCount, 1);
    });

    test(
        'deleting a DICOM original without a preview deletes only the original',
        () async {
      api.files = ['scan.dcm'];
      api.rowData = {'dcmImgs': []};

      final deleted = await remote.deleteImage('row-1', 'scan.dcm');

      expect(deleted, isTrue);
      expect(api.files, isEmpty);
      expect(remote.fullNamesCache['row-1'], isEmpty);
      expect(api.updateCount, 1);
    });

    test('missing DICOM original does not fuzzy-delete its preview', () async {
      api.files = ['scan.dcm.png'];
      api.rowData = {'dcmImgs': []};

      final deleted = await remote.deleteImage('row-1', 'scan.dcm');

      expect(deleted, isFalse);
      expect(api.updateCount, 0);
      expect(api.files, ['scan.dcm.png']);
    });

    test('ordinary attachment still supports legacy fuzzy deletion', () async {
      api.files = ['photo_hash.jpg'];
      api.rowData = {
        'imgs': ['photo_hash.jpg']
      };

      final deleted = await remote.deleteImage('row-1', 'photo');

      expect(deleted, isTrue);
      expect(api.updateCount, 1);
    });

    test('near-colliding ordinary filename is uploaded rather than reused',
        () async {
      api.files = ['photo_hash123.jpg'];
      api.rowData = {'imgs': api.files};

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'photo_hash12.jpg',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'photo_hash12.jpg',
        ),
      );

      expect(returned, 'photo_hash12.jpg');
      expect(api.updateCount, 1);
    });

    test('matching ordinary attachment is reused without another upload',
        () async {
      api.files = ['photo_hash12.jpg'];
      api.rowData = {'imgs': api.files};

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'photo_hash12.jpg',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'photo_hash12.jpg',
        ),
      );

      expect(returned, 'photo_hash12.jpg');
      expect(api.updateCount, 0);
    });

    // -------------------------------------------------------------------
    // DICOM upload deduplication integration tests
    // -------------------------------------------------------------------
    test('DICOM: both original + preview exist → returns existing, no upload',
        () async {
      api.files = ['dcm_scan.dcm', 'dcm_scan.dcm.png'];
      api.rowData = {'dcmImgs': []};
      api.revalidatedFilesByRow['row-1'] = api.files;

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_scan.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_scan.dcm',
        ),
      );

      // Should return the existing original without re-uploading.
      expect(returned, 'dcm_scan.dcm');
      // updateCount should still be 0 — no PATCH occurred.
      expect(api.updateCount, 0);
      // The pair is checked once and then re-read before returning.
      expect(api.getOneCountByRow['row-1'], 2);
    });

    test('DICOM: pair plus collision duplicates deletes only the extras',
        () async {
      api.files = [
        'dcm_scan.dcm',
        'dcm_scan.dcm.png',
        'dcm_scan_1.dcm',
        'dcm_scan_1.dcm.png',
        'dcm_scan_2.dcm',
      ];
      api.rowData = {'dcmImgs': []};
      api.revalidatedFilesByRow['row-1'] = ['dcm_scan.dcm', 'dcm_scan.dcm.png'];
      api.disappearRetainedFilesAfterDelete = false;

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_scan.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_scan.dcm',
        ),
      );

      expect(returned, 'dcm_scan.dcm');
      expect(api.updateCount, 1);
      expect(api.uploadedNamesByRow, isEmpty);
      expect(api.files, ['dcm_scan.dcm', 'dcm_scan.dcm.png']);
      expect(remote.fullNamesCache['row-1'], api.files);
      final deletion = jsonDecode(api.requestBodies.single);
      expect(deletion['imgs-'], [
        'dcm_scan_1.dcm',
        'dcm_scan_1.dcm.png',
        'dcm_scan_2.dcm',
      ]);
    });

    test('DICOM: retained-file disappearance aborts without uploading',
        () async {
      api.files = ['dcm_scan.dcm', 'dcm_scan.dcm.png', 'dcm_scan_1.dcm'];
      api.rowData = {'dcmImgs': []};
      api.disappearRetainedFilesAfterDelete = true;
      api.revalidatedFilesByRow['row-1'] = <String>[];

      await expectLater(
        remote.uploadImage(
          rowID: 'row-1',
          filename: 'dcm_scan.dcm',
          predefinedMultipart: http.MultipartFile.fromString(
            'imgs+',
            'bytes',
            filename: 'dcm_scan.dcm',
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(api.updateCount, 1);
      expect(api.uploadedNamesByRow, isEmpty);
      expect(api.getOneCountByRow['row-1'], 2);
    });

    test('DICOM: only original exists → deletes it and re-uploads both',
        () async {
      api.files = ['dcm_new.dcm']; // only original, no preview
      api.rowData = {'dcmImgs': []};

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_new.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_new.dcm',
        ),
      );

      // Should delete the lone original and upload fresh.
      expect(returned, 'dcm_new.dcm');
      // One PATCH for deletion, one multipart PATCH for upload.
      expect(api.updateCount, 2);
      // The new file was uploaded.
      expect(api._lastUploadedName, 'dcm_new.dcm');
    });

    test('DICOM: only preview exists → deletes it and re-uploads both',
        () async {
      api.files = ['dcm_new.dcm.png']; // only preview, no original
      api.rowData = {'dcmImgs': []};
      api.disappearRetainedFilesAfterDelete = false;

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_new.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_new.dcm',
        ),
      );

      // Should delete the lone preview and upload fresh.
      expect(returned, 'dcm_new.dcm');
      // One PATCH for deletion, one multipart PATCH for upload.
      expect(api.updateCount, 2);
    });

    test('DICOM: reversed server pair order retains the requested original',
        () async {
      api.files = ['dcm_order.dcm.png', 'dcm_order.dcm'];
      api.rowData = {'dcmImgs': []};
      api.revalidatedFilesByRow['row-1'] = api.files;

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_order.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_order.dcm',
        ),
      );

      expect(returned, 'dcm_order.dcm');
      expect(api.updateCount, 0);
    });

    test('DICOM: reversed server pair order retains the requested original 2',
        () async {
      api.files = ['dcm_order.dcm', 'dcm_order.dcm.png', "k.dcm.png", "k.dcm"];
      api.rowData = {'dcmImgs': []};
      api.revalidatedFilesByRow['row-1'] = api.files;

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_order.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_order.dcm',
        ),
      );

      expect(returned, 'dcm_order.dcm');
      expect(api.updateCount, 0);
    });

    test('DICOM: no matching files → fresh upload', () async {
      api.files = ['other.dcm', 'other.dcm.png'];
      api.rowData = {'dcmImgs': []};

      final returned = await remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_fresh.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_fresh.dcm',
        ),
      );

      expect(returned, 'dcm_fresh.dcm');
      // Only one multipart PATCH — no deletion needed.
      expect(api.updateCount, 1);
      expect(api._lastUploadedName, 'dcm_fresh.dcm');
      expect(remote.fullNamesCache['row-1'],
          ['other.dcm', 'other.dcm.png', 'dcm_fresh.dcm']);
    });

    test('successful upload updates the authoritative file cache', () async {
      api.files = [];

      await remote.uploadImage(
        rowID: 'row-1',
        filename: 'photo_hash.jpg',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'photo_hash.jpg',
        ),
      );

      expect(remote.fullNamesCache['row-1'], ['photo_hash.jpg']);
    });

    test('concurrent same-row same-identity uploads share one request',
        () async {
      api.uploadGate = Completer<void>();
      api.uploadStarted = Completer<void>();
      final first = remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_concurrent.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'bytes',
          filename: 'dcm_concurrent.dcm',
        ),
      );
      await api.uploadStarted!.future;
      final second = remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_concurrent.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'different-bytes',
          filename: 'dcm_concurrent.dcm',
        ),
      );
      api.uploadGate!.complete();

      expect(await first, 'dcm_concurrent.dcm');
      expect(await second, 'dcm_concurrent.dcm');
      expect(api.uploadedNamesByRow['row-1'], ['dcm_concurrent.dcm']);
    });

    test('concurrent uploads on different rows do not share an in-flight key',
        () async {
      api.pageRows
        ..clear()
        ..addAll({
          1: ['row-1', 'row-2']
        });
      api.uploadGate = Completer<void>();
      api.uploadStarted = Completer<void>();

      final first = remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_same.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'one',
          filename: 'dcm_same.dcm',
        ),
      );
      await api.uploadStarted!.future;
      final second = remote.uploadImage(
        rowID: 'row-2',
        filename: 'dcm_same.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'two',
          filename: 'dcm_same.dcm',
        ),
      );
      api.uploadGate!.complete();

      expect(await first, 'dcm_same.dcm');
      expect(await second, 'dcm_same.dcm');
      expect(api.uploadedNamesByRow['row-1'], ['dcm_same.dcm']);
      expect(api.uploadedNamesByRow['row-2'], ['dcm_same.dcm']);
    });

    test('original and preview uploads use separate in-flight keys', () async {
      api.uploadGate = Completer<void>();
      api.uploadStarted = Completer<void>();

      final original = remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_pair.dcm',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'original',
          filename: 'dcm_pair.dcm',
        ),
      );
      await api.uploadStarted!.future;
      final preview = remote.uploadImage(
        rowID: 'row-1',
        filename: 'dcm_pair.dcm.png',
        predefinedMultipart: http.MultipartFile.fromString(
          'imgs+',
          'preview',
          filename: 'dcm_pair.dcm.png',
        ),
      );
      api.uploadGate!.complete();

      expect(await original, 'dcm_pair.dcm');
      expect(await preview, 'dcm_pair.dcm.png');
      expect(api.uploadedNamesByRow['row-1'],
          ['dcm_pair.dcm', 'dcm_pair.dcm.png']);
    });
  });
}
