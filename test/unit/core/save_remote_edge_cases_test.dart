import 'package:apexo/core/save_remote.dart';
import 'package:apexo/services/dicom/dicom_orphans_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

/// Unit-level tests for SaveRemote DTOs, filename hashing pattern,
/// and edge cases that don't require a real PocketBase server.
///
/// For integration-level upload/download/delete tests against a live
/// PocketBase instance, see `test/live_backend/core/save_remote_test.dart`.
void main() {
  final remote = SaveRemote(
    storeName: 'unit-test',
    // The DTO and timestamp tests below must not require credentials or a
    // reachable server. SaveRemote starts its health check in the
    // constructor, so cancel its retry timer when this file finishes.
    pbInstance: PocketBase('http://127.0.0.1:65535'),
  );

  tearDownAll(() {
    remote.timer?.cancel();
  });

  // ---------------------------------------------------------------------------
  // RowToWriteRemotely DTO
  // ---------------------------------------------------------------------------
  group('RowToWriteRemotely', () {
    test('defaults store to empty string', () {
      final r = RowToWriteRemotely(id: 'abc', data: '{"x":1}');
      expect(r.id, 'abc');
      expect(r.data, '{"x":1}');
      expect(r.store, '');
    });

    test('accepts explicit store name', () {
      final r = RowToWriteRemotely(id: 'r1', data: '{}');
      r.store = 'appointments';
      expect(r.store, 'appointments');
    });

    test('toJson includes id, data, and store', () {
      final r = RowToWriteRemotely(id: 'id1', data: '{"k":"v"}');
      r.store = 'patients';
      final j = r.toJson();
      expect(j['id'], 'id1');
      expect(j['data'], '{"k":"v"}');
      expect(j['store'], 'patients');
      expect(j.length, 3);
    });

    test('toJson when store is empty string includes it', () {
      final r = RowToWriteRemotely(id: 'id2', data: '{}');
      final j = r.toJson();
      expect(j['store'], '');
    });

    test('different instances with same fields are independent', () {
      final a = RowToWriteRemotely(id: 'x', data: '1');
      final b = RowToWriteRemotely(id: 'x', data: '1');
      expect(a.id, b.id);
      expect(a.data, b.data);
    });

    test('with empty data string', () {
      final r = RowToWriteRemotely(id: 'empty-data', data: '');
      expect(r.data, '');
      expect(r.toJson()['data'], '');
    });

    test('with nested JSON data', () {
      final r =
          RowToWriteRemotely(id: 'json', data: '{"complex":{"nested":true}}');
      expect(r.data, contains('nested'));
    });
  });

  // ---------------------------------------------------------------------------
  // Row DTO (extends RowToWriteRemotely)
  // ---------------------------------------------------------------------------
  group('Row', () {
    test('extends RowToWriteRemotely and adds ts', () {
      const ts = 1700000000000;
      final r = Row(id: 'row1', data: '{}', ts: ts);
      r.store = 'notes';
      expect(r.id, 'row1');
      expect(r.store, 'notes');
      expect(r.ts, ts);
    });

    test('toJson includes id, data, store but NOT ts (not overridden)', () {
      final r = Row(id: 'r6', data: '{"a":1}', ts: 99);
      r.store = 'appointments';
      final j = r.toJson();
      // Row inherits toJson from RowToWriteRemotely which only
      // serializes id, data, store. ts is NOT in the JSON output.
      expect(j['id'], 'r6');
      expect(j['data'], '{"a":1}');
      expect(j['store'], 'appointments');
      expect(j.length, 3);
    });

    test('ts can be a large timestamp (year 2038+)', () {
      final far = DateTime(2040, 1, 1).millisecondsSinceEpoch;
      final r = Row(id: 'row4', data: '{}', ts: far);
      expect(r.ts, far);
    });

    test('ts defaults to 0 when provided explicitly', () {
      final r = Row(id: 'row2', data: '{}', ts: 0);
      expect(r.ts, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // VersionedResult DTO
  // ---------------------------------------------------------------------------
  group('VersionedResult', () {
    test('holds version and rows (positional constructor)', () {
      final vr = VersionedResult(0, []);
      expect(vr.version, 0);
      expect(vr.rows, isEmpty);
    });

    test('version > 0 with non-empty rows', () {
      final rows = [Row(id: 'a', data: '{}', ts: 1)];
      final vr = VersionedResult(100, rows);
      expect(vr.version, 100);
      expect(vr.rows.length, 1);
    });

    test('rows list and version remain independently mutable DTO fields', () {
      final result = VersionedResult(1, []);
      result.version = 2;
      result.rows.add(Row(id: 'later', data: '{}', ts: 3));

      expect(result.version, 2);
      expect(result.rows.single.id, 'later');
      expect(result.rows.single.ts, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // DICOM orphan-file detection
  // ---------------------------------------------------------------------------
  group('RemoteDcmFileRow and DcmOrphanCleanupResult', () {
    test('extracts only list-valued dcmImgs references', () {
      final row = RemoteDcmFileRow(
        id: 'row-1',
        data: {
          'dcmImgs': ['scan.dcm', 42]
        },
        files: const [],
      );
      expect(row.id, 'row-1');
      expect(row.data['dcmImgs'], ['scan.dcm', 42]);
      expect(row.files, isEmpty);
      expect(row.referencedDcmFiles, ['scan.dcm', '42']);

      final empty = RemoteDcmFileRow(
        id: 'row-2',
        data: {'dcmImgs': 'not-a-list'},
        files: const ['scan.dcm'],
      );
      expect(empty.id, 'row-2');
      expect(empty.files, ['scan.dcm']);
      expect(empty.referencedDcmFiles, isEmpty);
    });

    test('referencedDcmFiles converts null and nested values predictably', () {
      final row = RemoteDcmFileRow(
        id: 'row-3',
        data: {
          'dcmImgs': [
            null,
            {'name': 'scan.dcm'},
            true
          ]
        },
        files: const [],
      );

      expect(row.referencedDcmFiles, ['null', '{name: scan.dcm}', 'true']);
    });

    test('flattens orphan and deleted file results', () {
      const result = DcmOrphanCleanupResult(
        rowsScanned: 2,
        orphanFilesByRow: {
          'row-1': ['one.dcm'],
          'row-2': ['two.dcm', 'two.dcm.png'],
        },
        deletedFilesByRow: {
          'row-1': ['one.dcm']
        },
        failuresByRow: {},
      );
      expect(result.rowsScanned, 2);
      expect(result.orphanFiles, ['one.dcm', 'two.dcm', 'two.dcm.png']);
      expect(result.deletedFiles, ['one.dcm']);
      expect(result.failuresByRow, isEmpty);
    });

    test('cleanup result preserves per-row failures without flattening them',
        () {
      final failure = StateError('row update failed');
      final result = DcmOrphanCleanupResult(
        rowsScanned: 1,
        orphanFilesByRow: const {
          'row-1': ['one.dcm']
        },
        deletedFilesByRow: const {},
        failuresByRow: {'row-1': failure},
      );

      expect(result.orphanFiles, ['one.dcm']);
      expect(result.deletedFiles, isEmpty);
      expect(result.failuresByRow['row-1'], same(failure));
    });
  });

  group('SaveRemote DICOM deduplication', () {
    test('keeps the retained original and its preview', () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_local_remote.dcm',
          matchingFiles: const [
            'dcm_local_remote.dcm',
            'dcm_local_remote.dcm.png',
            'dcm_local_other.dcm',
            'dcm_local_other.dcm.png',
          ],
        ),
        ['dcm_local_other.dcm', 'dcm_local_other.dcm.png'],
      );
    });

    test('retained preview matching is case-insensitive', () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_local_remote.dcm',
          matchingFiles: const [
            'DCM_LOCAL_REMOTE.DCM',
            'DCM_LOCAL_REMOTE.DCM.PNG',
          ],
        ),
        isEmpty,
      );
    });

    test('retained preview input still protects its original', () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_local_remote.dcm.png',
          matchingFiles: const [
            'dcm_local_remote.dcm',
            'dcm_local_remote.dcm.png',
            'dcm_local_remote_suffix.dcm',
          ],
        ),
        ['dcm_local_remote_suffix.dcm'],
      );
    });

    // -------------------------------------------------------------------
    // dcmFilesToDelete: boundary scenarios
    // -------------------------------------------------------------------
    test(
        'only original exists (no preview) → delete all to force clean re-upload',
        () {
      // When only the DCM original is on the server but not its preview,
      // everything must be deleted so the upload path recreates both.
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_scan.dcm',
          matchingFiles: const ['dcm_scan.dcm'],
        ),
        ['dcm_scan.dcm'],
      );
    });

    test(
        'only preview exists (no original) → delete all to force clean re-upload',
        () {
      // When only the generated preview is on the server but not the DCM,
      // everything must be deleted so the upload path recreates both.
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_scan.dcm.png',
          matchingFiles: const ['dcm_scan.dcm.png'],
        ),
        ['dcm_scan.dcm.png'],
      );
    });

    test('only preview exists with .dicom extension (no original) → delete all',
        () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'scan.dicom.png',
          matchingFiles: const ['scan.dicom.png'],
        ),
        ['scan.dicom.png'],
      );
    });

    test('pair + collision-suffix duplicates → keep pair, delete rest', () {
      // The original + preview pair is protected; collision-suffix variants
      // (e.g. from PocketBase filename collisions) are deleted.
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_scan.dcm',
          matchingFiles: const [
            'dcm_scan.dcm',
            'dcm_scan.dcm.png',
            'dcm_scan_x29.dcm',
            'dcm_scan_x29.dcm.png',
          ],
        ),
        ['dcm_scan_x29.dcm', 'dcm_scan_x29.dcm.png'],
      );
    });

    test(
        'pair + single collision-suffix original (no collision preview) → keep pair, delete extra',
        () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_scan.dcm',
          matchingFiles: const [
            'dcm_scan.dcm',
            'dcm_scan.dcm.png',
            'dcm_scan_extra.dcm',
          ],
        ),
        ['dcm_scan_extra.dcm'],
      );
    });

    test(
        'pair + only a collision-suffix preview (no collision original) → keep pair, delete extra',
        () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_scan.dcm',
          matchingFiles: const [
            'dcm_scan.dcm',
            'dcm_scan.dcm.png',
            'dcm_scan_extra.dcm.png',
          ],
        ),
        ['dcm_scan_extra.dcm.png'],
      );
    });

    test('empty matchingFiles → returns empty list', () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_scan.dcm',
          matchingFiles: const [],
        ),
        isEmpty,
      );
    });

    test(
        'multiple unrelated pairs → only excess beyond the retained pair is deleted',
        () {
      // Three different upload-identity pairs exist; only the two that
      // don't match the retained name pair are deleted.
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_a.dcm',
          matchingFiles: const [
            'dcm_a.dcm',
            'dcm_a.dcm.png',
            'dcm_b.dcm',
            'dcm_b.dcm.png',
            'dcm_c.dcm',
            'dcm_c.dcm.png',
          ],
        ),
        ['dcm_b.dcm', 'dcm_b.dcm.png', 'dcm_c.dcm', 'dcm_c.dcm.png'],
      );
    });

    test('retention protects exactly one original/preview pair', () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_uid.dcm',
          matchingFiles: const [
            'dcm_uid.dcm',
            'dcm_uid.dcm.png',
            'dcm_uid_1.dcm',
            'dcm_uid_1.dcm.png',
            'dcm_uid_2.dcm',
          ],
        ),
        ['dcm_uid_1.dcm', 'dcm_uid_1.dcm.png', 'dcm_uid_2.dcm'],
      );
    });

    test('retention deletes every malformed or incomplete pair', () {
      expect(
        SaveRemote.dcmFilesToDelete(
          retainedDcmName: 'dcm_uid.dcm',
          matchingFiles: const [
            'dcm_uid.dcm',
            'dcm_uid_1.dcm.png',
          ],
        ),
        ['dcm_uid.dcm', 'dcm_uid_1.dcm.png'],
      );
    });

    test('DICOM identities ignore collision suffixes and preview extension',
        () {
      expect(
        SaveRemote.sameDcmUploadIdentity(
          'dcm_hash.dcm',
          'dcm_hash_1.dcm',
        ),
        isTrue,
      );
      expect(
        SaveRemote.sameDcmUploadIdentity(
          'dcm_hash.dcm',
          'dcm_hash_1.dcm.png',
        ),
        isTrue,
      );
      expect(
        SaveRemote.sameDcmUploadIdentity('dcm_hash.dcm', 'dcm_other.dcm'),
        isFalse,
      );
      expect(SaveRemote.dcmUploadIdentity('photo_hash.jpg'), isNull);
      expect(SaveRemote.dcmUploadIdentity('dcm_hash.jpg'), isNull);
    });

    test('identity extraction supports every DICOM extension and casing', () {
      expect(SaveRemote.dcmUploadIdentity('dcm_abc.dcm'), 'dcm_abc');
      expect(SaveRemote.dcmUploadIdentity('dcm_abc.dicom'), 'dcm_abc');
      expect(SaveRemote.dcmUploadIdentity('dcm_abc.dcm.png'), 'dcm_abc');
      expect(SaveRemote.dcmUploadIdentity('dcm_abc.dicom.png'), 'dcm_abc');
      expect(SaveRemote.dcmUploadIdentity('DCM_ABC.DICOM.PNG'), 'dcm_abc');
    });

    test(
        'identity extraction ignores path components and preserves hash boundaries',
        () {
      expect(
        SaveRemote.dcmUploadIdentity(r'C:\incoming\dcm_uid_1.dcm'),
        'dcm_uid',
      );
      expect(
        SaveRemote.dcmUploadIdentity('dcm_uid_1_extra.dicom.png'),
        'dcm_uid',
      );
      expect(SaveRemote.dcmUploadIdentity('dcm_.dcm'), isNull);
      expect(SaveRemote.dcmUploadIdentity('dcm_uid'), isNull);
      expect(SaveRemote.dcmUploadIdentity('not_dcm_uid.dcm'), isNull);
    });

    test('ordinary extensions never produce DICOM identities', () {
      for (final filename in [
        'dcm_uid.jpg',
        'dcm_uid.jpeg',
        'dcm_uid.png',
        'dcm_uid.pdf',
        'dcm_uid.dcm.txt',
        'dcm_uid.dicom.jpg',
      ]) {
        expect(
          SaveRemote.dcmUploadIdentity(filename),
          isNull,
          reason: '$filename must not be classified as DICOM',
        );
      }
    });

    test('same DICOM identity rejects malformed or unrelated names', () {
      expect(
          SaveRemote.sameDcmUploadIdentity('dcm_a.dcm', 'dcm_a.dicom'), isTrue);
      expect(
        SaveRemote.sameDcmUploadIdentity('dcm_a.dcm.png', 'dcm_a.dicom.png'),
        isTrue,
      );
      expect(
          SaveRemote.sameDcmUploadIdentity('dcm_a.dcm', 'dcm_ab.dcm'), isFalse);
      expect(SaveRemote.sameDcmUploadIdentity('dcm_a.dcm', 'photo_a.png'),
          isFalse);
      expect(SaveRemote.sameDcmUploadIdentity('dcm_a.dcm', 'dcm_a'), isFalse);
    });
  });

  group('SaveRemote.orphanDcmFileNames', () {
    test('keeps a referenced DCM and its preview together', () {
      final orphans = orphanDcmFileNames(
        serverFiles: const [
          'dcm_scan.dcm',
          'dcm_scan.dcm.png',
          'dcm_orphan.dcm',
          'dcm_orphan.dcm.png',
          'ordinary.jpg',
        ],
        referencedDcmFiles: const ['dcm_scan.dcm'],
      );

      expect(orphans, ['dcm_orphan.dcm', 'dcm_orphan.dcm.png']);
    });

    test('matches references case-insensitively', () {
      final orphans = orphanDcmFileNames(
        serverFiles: const ['SCAN.DCM', 'SCAN.DCM.PNG'],
        referencedDcmFiles: const ['scan.dcm'],
      );

      expect(orphans, isEmpty);
    });

    test('does not delete an orphan preview when its original is referenced',
        () {
      final orphans = orphanDcmFileNames(
        serverFiles: const ['scan.dcm', 'scan.dcm.png'],
        referencedDcmFiles: const ['scan.dcm'],
      );

      expect(orphans, isEmpty);
    });

    test('supports .dicom originals and previews', () {
      final orphans = orphanDcmFileNames(
        serverFiles: const [
          'kept.dicom',
          'kept.dicom.png',
          'orphan.dicom',
          'orphan.dicom.png',
        ],
        referencedDcmFiles: const ['kept.dicom'],
      );

      expect(orphans, ['orphan.dicom', 'orphan.dicom.png']);
    });

    test('does not classify ordinary PNG/JPEG attachments as DICOM orphans',
        () {
      final orphans = orphanDcmFileNames(
        serverFiles: const ['photo.png', 'photo.jpg', 'report.pdf'],
        referencedDcmFiles: const [],
      );

      expect(orphans, isEmpty);
    });

    test('a referenced preview also protects its original', () {
      final orphans = orphanDcmFileNames(
        serverFiles: const ['scan.dcm', 'scan.dcm.png'],
        referencedDcmFiles: const ['scan.dcm.png'],
      );

      expect(orphans, isEmpty);
    });

    test(
        'a reference to a missing server file does not make another file orphaned',
        () {
      final orphans = orphanDcmFileNames(
        serverFiles: const ['available.dcm', 'available.dcm.png'],
        referencedDcmFiles: const ['missing.dcm'],
      );

      expect(orphans, ['available.dcm', 'available.dcm.png']);
    });
  });

  // ---------------------------------------------------------------------------
  // PocketBase timestamp formatting
  // ---------------------------------------------------------------------------
  group('SaveRemote.formatForPocketBase', () {
    test('formats the epoch in PocketBase/SQLite UTC format', () {
      expect(remote.formatForPocketBase(0), '1970-01-01 00:00:00.000Z');
    });

    test('uses UTC rather than the machine local timezone', () {
      final timestamp =
          DateTime.utc(2024, 2, 29, 23, 59, 58, 123).millisecondsSinceEpoch;
      expect(
        remote.formatForPocketBase(timestamp),
        '2024-02-29 23:59:58.123Z',
      );
    });

    test('retains milliseconds required by incremental sync comparisons', () {
      final timestamp =
          DateTime.utc(2038, 1, 19, 3, 14, 7, 7).millisecondsSinceEpoch;
      final formatted = remote.formatForPocketBase(timestamp);

      expect(formatted, endsWith('.007Z'));
      expect(formatted, contains('2038-01-19 03:14:07'));
    });
  });

  // ---------------------------------------------------------------------------
  // Filename hash pattern (_$hash format used by _findExistingByHash)
  // ---------------------------------------------------------------------------
  group('Filename hash pattern', () {
    test('recognizes _hash.extension pattern', () {
      const filename = 'photo_h1a2b3c4d5e6f7g8.jpg';
      final parts = filename.split('_');
      final hash = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      // h1a2b3c4d5e6f7g8 is 16 hex chars
      expect(hash, 'h1a2b3c4d5e6f7g8');
      expect(hash.length, 16);
    });

    test('hash from complex name with multiple underscores', () {
      const filename = 'scan_report_h2x3y4z5.jpg';
      final parts = filename.split('_');
      final hash = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(hash, 'h2x3y4z5');
    });

    test('no-underscore filename gives whole basename as "hash"', () {
      const filename = 'simple.jpg';
      final parts = filename.split('_');
      final hash = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(hash, 'simple');
    });

    test('no extension just returns last segment', () {
      const filename = 'rawfile_h1h2h3h4';
      final parts = filename.split('_');
      final hash = parts.last;
      expect(hash, 'h1h2h3h4');
    });

    test('case is preserved for hash matching', () {
      const filename = 'xray_AbC123.DCM';
      final hash = filename.split('_').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(hash, 'AbC123');
    });
  });
}
