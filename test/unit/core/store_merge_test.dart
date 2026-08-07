import 'dart:convert';
import 'dart:io';

import 'package:apexo/core/model.dart';
import 'package:apexo/core/save_local.dart';
import 'package:apexo/core/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/hive_setup.dart';

class _MergeSyncRemote extends SaveRemote {
  final VersionedResult remoteUpdates;
  final int remoteVersion;
  final pushed = <RowToWriteRemotely>[];

  _MergeSyncRemote({required this.remoteUpdates, required this.remoteVersion})
      : super(
          storeName: 'merge-test',
          pbInstance: PocketBase('http://fake-pocketbase'),
        );

  @override
  Future<void> checkOnline() async {
    isOnline = true;
  }

  @override
  Future<int> getVersion() async => remoteVersion;

  @override
  Future<VersionedResult> getSince({int version = 0}) async => remoteUpdates;

  @override
  Future<bool> put(List<RowToWriteRemotely> data) async {
    pushed.addAll(data);
    return true;
  }
}

class _MergeSyncModel extends Model {
  _MergeSyncModel.fromJson(super.json) : super.fromJson();

  @override
  _MergeSyncModel copy(bool blank) =>
      _MergeSyncModel.fromJson(blank ? {} : toJson());
}

class _MergeSyncStore extends Store<_MergeSyncModel> {
  _MergeSyncStore({required SaveLocal local, required SaveRemote remote})
      : super(
          modeling: _MergeSyncModel.fromJson,
          local: local,
          remote: remote,
          manualSyncOnly: true,
        );
}

void main() {
  group('Store.mergeConflict scalar and map behavior', () {
    test('preserves fields present on only one side', () {
      final merged = Store.mergeConflict(
        localJson: const {'id': 'row', 'name': 'Alice'},
        remoteJson: const {'id': 'row', 'phone': '555'},
        localWins: true,
      );

      expect(merged, containsPair('name', 'Alice'));
      expect(merged, containsPair('phone', '555'));
    });

    test('uses the selected winner for same-field scalar conflicts', () {
      final localWins = Store.mergeConflict(
        localJson: const {'id': 'row', 'name': 'Alice'},
        remoteJson: const {'id': 'row', 'name': 'Bob'},
        localWins: true,
      );
      final remoteWins = Store.mergeConflict(
        localJson: const {'id': 'row', 'name': 'Alice'},
        remoteJson: const {'id': 'row', 'name': 'Bob'},
        localWins: false,
      );

      expect(localWins['name'], 'Alice');
      expect(remoteWins['name'], 'Bob');
    });

    test('merges different map keys and resolves same-key conflicts', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'teeth': {'11': 'crown', '12': 'local'},
        },
        remoteJson: const {
          'id': 'row',
          'teeth': {'21': 'filling', '12': 'remote'},
        },
        localWins: false,
      );

      expect(merged['teeth'], {
        '11': 'crown',
        '21': 'filling',
        '12': 'remote',
      });
    });

    test('unions additive operator assignments without duplicates', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'operatorsIDs': ['a', 'b']
        },
        remoteJson: const {
          'id': 'row',
          'operatorsIDs': ['b', 'c']
        },
        localWins: true,
      );

      expect(merged['operatorsIDs'], ['a', 'b', 'c']);
    });
  });

  group('Store.mergeConflict image reconciliation', () {
    test('keeps a server-present DICOM reference case-insensitively', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'dcmImgs': ['scan.dcm']
        },
        remoteJson: const {'id': 'row', 'dcmImgs': []},
        localWins: true,
        serverFiles: const ['SCAN.DCM'],
      );

      expect(merged['dcmImgs'], ['scan.dcm']);
    });

    test('keeps a pending upload only for the supplied row context', () {
      final withPendingRow = Store.mergeConflict(
        localJson: const {
          'id': 'row-a',
          'dcmImgs': ['scan.dcm']
        },
        remoteJson: const {'id': 'row-a', 'dcmImgs': []},
        localWins: true,
        pendingUploads: const {'scan.dcm'},
      );
      final withoutPendingRow = Store.mergeConflict(
        localJson: const {
          'id': 'row-b',
          'dcmImgs': ['scan.dcm']
        },
        remoteJson: const {'id': 'row-b', 'dcmImgs': []},
        localWins: true,
      );

      expect(withPendingRow['dcmImgs'], ['scan.dcm']);
      expect(withoutPendingRow['dcmImgs'], isEmpty);
    });

    test('does not keep a DICOM preview as a raw DICOM reference', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'dcmImgs': ['scan.dcm.png']
        },
        remoteJson: const {'id': 'row', 'dcmImgs': []},
        localWins: true,
        serverFiles: const ['scan.dcm.png'],
      );

      expect(merged['dcmImgs'], isEmpty);
    });

    test('server files are authoritative for ordinary images and DICOM files',
        () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'imgs': ['local.jpg', 'missing.jpg', 'scan.dcm'],
          'dcmImgs': ['scan.dcm', 'missing.dicom', 'scan.dcm.png'],
        },
        remoteJson: const {
          'id': 'row',
          'imgs': ['remote.png'],
          'dcmImgs': ['remote.dicom'],
        },
        localWins: true,
        serverFiles: const [
          'LOCAL.JPG',
          'remote.png',
          'SCAN.DCM',
          'scan.dcm.png',
        ],
      );

      // DICOM originals are excluded from imgs. The preview is also absent
      // from the model's imgs candidates, while the raw DICOM stays in
      // dcmImgs only.
      expect(merged['imgs'], ['local.jpg', 'remote.png']);
      expect(merged['dcmImgs'], ['scan.dcm']);
    });

    test('pending uploads preserve missing files with case-insensitive names',
        () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'imgs': ['queued.jpg'],
          'dcmImgs': ['queued.dicom'],
        },
        remoteJson: const {'id': 'row', 'imgs': [], 'dcmImgs': []},
        localWins: true,
        serverFiles: const [],
        pendingUploads: const {'QUEUED.JPG', 'QUEUED.DICOM'},
      );

      expect(merged['imgs'], ['queued.jpg']);
      expect(merged['dcmImgs'], ['queued.dicom']);
    });

    test('pending upload from another row cannot protect this row', () {
      final deferred = {
        'FILE||row-a||C:/a||same.dcm||0': 1,
        'FILE||row-b||C:/b||same.dcm||0': 1,
      };
      final rowAPending = Store.filenamesFromDeferredForRow(deferred, 'row-a');
      final rowBPending = Store.filenamesFromDeferredForRow(deferred, 'row-b');

      final rowA = Store.mergeConflict(
        localJson: const {
          'id': 'row-a',
          'dcmImgs': ['same.dcm']
        },
        remoteJson: const {'id': 'row-a', 'dcmImgs': []},
        localWins: true,
        pendingUploads: rowAPending,
      );
      final rowB = Store.mergeConflict(
        localJson: const {
          'id': 'row-b',
          'dcmImgs': ['same.dcm']
        },
        remoteJson: const {'id': 'row-b', 'dcmImgs': []},
        localWins: true,
        pendingUploads: rowBPending,
      );

      expect(rowAPending, {'same.dcm'});
      expect(rowBPending, {'same.dcm'});
      expect(rowA['dcmImgs'], ['same.dcm']);
      expect(rowB['dcmImgs'], ['same.dcm']);
      expect(
        Store.filenamesFromDeferredForRow(deferred, 'row-c'),
        isEmpty,
      );
    });

    test('delete entries and malformed pending values do not protect files',
        () {
      final deferred = {
        'FILE||row||old.dcm': 0,
        'FILE||row||C:/valid||valid.dcm||1': 1,
        'FILE||row||C:/delete||delete.dcm||0': 0,
        'FILE||row||||missing-path.dcm||0': 1,
        'DOC||row': 1,
      };
      final pending = Store.filenamesFromDeferredForRow(deferred, 'row');

      expect(pending, {'valid.dcm'});
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'imgs': ['old.jpg', 'valid.dcm'],
        },
        remoteJson: const {'id': 'row', 'imgs': []},
        localWins: true,
        pendingUploads: pending,
      );
      expect(merged['imgs'], ['valid.dcm']);
    });

    test('image fields tolerate null and non-list JSON values', () {
      final merged = Store.mergeConflict(
        localJson: const {'id': 'row', 'imgs': 'not-a-list', 'dcmImgs': null},
        remoteJson: const {'id': 'row', 'imgs': null, 'dcmImgs': 'invalid'},
        localWins: true,
        serverFiles: const ['photo.jpg', 'scan.dcm'],
      );

      expect(merged['imgs'], isEmpty);
      expect(merged['dcmImgs'], isEmpty);
    });
  });

  group('Store._syncTry conflict integration', () {
    late Directory hiveDirectory;
    late SaveLocal local;
    late _MergeSyncRemote remote;
    late _MergeSyncStore store;
    var testNumber = 0;

    setUpAll(() async {
      hiveDirectory = await setupTestHive();
    });

    setUp(() {
      local = SaveLocal(
        name: 'merge-sync',
        uniqueId: 'case-${testNumber++}',
        storagePath: hiveDirectory.path,
      );
    });

    tearDown(() async {
      remote.timer?.cancel();
      await local.dispose();
    });

    tearDownAll(() async {
      await teardownTestHive(hiveDirectory);
    });

    test('detects conflict, merges fields, writes both sides, and clears defer',
        () async {
      const rowId = 'row-1';
      await local.put({
        rowId: '{"id":"row-1","name":"local","phone":"555"}',
      });
      await local.putVersion(1);
      await local.putDeferred({rowId: 2000});
      remote = _MergeSyncRemote(
        remoteVersion: 2,
        remoteUpdates: VersionedResult(
          2,
          [
            Row(
              id: rowId,
              data: jsonEncode({
                'id': rowId,
                'name': 'remote',
                'email': 'remote@example.com',
              }),
              ts: 1000,
            ),
          ],
        ),
      );
      store = _MergeSyncStore(local: local, remote: remote);
      await store.loaded;

      final result = await store.debugSyncTry();
      final expected = {
        'id': rowId,
        'name': 'local',
        'phone': '555',
        'email': 'remote@example.com',
      };

      expect(result.exception, isNull);
      expect(result.conflicts, 1);
      expect(jsonDecode(await local.get(rowId)), expected);
      expect(remote.pushed, hasLength(1));
      expect(jsonDecode(remote.pushed.single.data), expected);
      expect(await local.getDeferred(), isEmpty);
      expect(await local.getVersion(), 2);
    });

    test('conflict merge keeps only pending uploads for the conflicting row',
        () async {
      const rowA = 'row-a';
      await local.put({
        rowA: '{"id":"row-a","dcmImgs":["same.dcm"]}',
      });
      await local.putVersion(1);
      await local.putDeferred({
        rowA: 2000,
        'FILE||row-a||C:/a||same.dcm||0': 1,
        'FILE||row-b||C:/b||same.dcm||0': 1,
      });
      remote = _MergeSyncRemote(
        remoteVersion: 2,
        remoteUpdates: VersionedResult(
          2,
          [
            Row(
              id: rowA,
              data: '{"id":"row-a","dcmImgs":[]}',
              ts: 1000,
            ),
          ],
        ),
      );
      store = _MergeSyncStore(local: local, remote: remote);
      await store.loaded;

      final result = await store.debugSyncTry();

      expect(result.exception, isNull);
      expect(jsonDecode(await local.get(rowA))['dcmImgs'], ['same.dcm']);
      expect(jsonDecode(remote.pushed.single.data)['dcmImgs'], ['same.dcm']);
    });

    test('conflict merge trusts server file type and case-insensitive presence',
        () async {
      const rowId = 'row-1';
      await local.put({
        rowId:
            '{"id":"row-1","imgs":["photo.jpg","missing.jpg"],"dcmImgs":["scan.dcm"]}',
      });
      await local.putVersion(1);
      await local.putDeferred({rowId: 2000});
      remote = _MergeSyncRemote(
        remoteVersion: 2,
        remoteUpdates: VersionedResult(
          2,
          [
            Row(
              id: rowId,
              data: '{"id":"row-1","imgs":[],"dcmImgs":[]}',
              ts: 1000,
            ),
          ],
        ),
      )..fullNamesCache[rowId] = ['PHOTO.JPG', 'SCAN.DCM'];
      store = _MergeSyncStore(local: local, remote: remote);
      await store.loaded;

      final result = await store.debugSyncTry();
      final merged = jsonDecode(await local.get(rowId)) as Map<String, dynamic>;

      expect(result.exception, isNull);
      expect(merged['imgs'], ['photo.jpg']);
      expect(merged['dcmImgs'], ['scan.dcm']);
    });
  });

  group('Store.mergeConflict scalar, list, and identity edge cases', () {
    test('preserves the record ID from local when both IDs are present', () {
      final merged = Store.mergeConflict(
        localJson: const {'id': 'local-id', 'name': 'Alice'},
        remoteJson: const {'id': 'remote-id', 'name': 'Bob'},
        localWins: false,
      );

      expect(merged['id'], 'local-id');
    });

    test('uses remote value for a scalar when remote wins', () {
      final merged = Store.mergeConflict(
        localJson: const {'id': 'row', 'date': '2026-08-01'},
        remoteJson: const {'id': 'row', 'date': '2026-08-02'},
        localWins: false,
      );

      expect(merged['date'], '2026-08-02');
    });

    test('uses local value for whole-list tags and prescriptions', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'tags': ['local', 'shared'],
          'prescriptions': ['local-prescription'],
        },
        remoteJson: const {
          'id': 'row',
          'tags': ['remote', 'shared'],
          'prescriptions': ['remote-prescription'],
        },
        localWins: true,
      );

      expect(merged['tags'], ['local', 'shared']);
      expect(merged['prescriptions'], ['local-prescription']);
    });

    test('uses remote value for whole-list fields when remote wins', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'tags': ['local']
        },
        remoteJson: const {
          'id': 'row',
          'tags': ['remote']
        },
        localWins: false,
      );

      expect(merged['tags'], ['remote']);
    });

    test('merges all configured map fields independently', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'teeth': {'11': 'crown'},
          'teethExtraNotes': {'11': 'local note'},
          'drawings': {'a': 'local drawing'},
        },
        remoteJson: const {
          'id': 'row',
          'teeth': {'21': 'filling'},
          'teethExtraNotes': {'21': 'remote note'},
          'drawings': {'b': 'remote drawing'},
        },
        localWins: true,
      );

      expect(merged['teeth'], {'11': 'crown', '21': 'filling'});
      expect(merged['teethExtraNotes'], {
        '11': 'local note',
        '21': 'remote note',
      });
      expect(merged['drawings'], {
        'a': 'local drawing',
        'b': 'remote drawing',
      });
    });

    test('operatorsIDs deduplicate exact values but preserve distinct casing',
        () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'operatorsIDs': ['A', 'a']
        },
        remoteJson: const {
          'id': 'row',
          'operatorsIDs': ['a', 'B']
        },
        localWins: true,
      );

      expect(merged['operatorsIDs'], ['A', 'a', 'B']);
    });

    test('missing map and union fields do not create empty fields', () {
      final merged = Store.mergeConflict(
        localJson: const {'id': 'row', 'teeth': {}, 'operatorsIDs': []},
        remoteJson: const {'id': 'row'},
        localWins: true,
      );

      expect(merged.containsKey('teeth'), isFalse);
      expect(merged.containsKey('operatorsIDs'), isFalse);
    });

    test('map values are stringified consistently', () {
      final merged = Store.mergeConflict(
        localJson: const {
          'id': 'row',
          'teeth': {'11': 1},
        },
        remoteJson: const {
          'id': 'row',
          'teeth': {'21': true},
        },
        localWins: true,
      );

      expect(merged['teeth'], {'11': '1', '21': 'true'});
    });
  });
}
