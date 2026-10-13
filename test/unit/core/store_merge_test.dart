@Tags(['serial'])
library;

import 'package:apexo/core/synchronization/conflict_merge.dart';
import 'package:apexo/core/synchronization/deferred_file_keys.dart';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/core/model.dart';
import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/hive_setup.dart';

class _MergeSyncRemote extends SaveRemote {
  _MergeSyncRemote({required this.remoteUpdates, required this.remoteVersion})
      : super(
          storeName: 'merge-test',
          pbInstance: PocketBase('http://fake-pocketbase'),
        );
  final VersionedResult remoteUpdates;
  final int remoteVersion;
  final pushed = <RowToWriteRemotely>[];

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

Map<String, dynamic> _mergeModelSnapshots({
  required Model winner,
  required Model loser,
  required bool localWins,
}) {
  final winnerJson = winner.toJson();
  final loserJson = loser.toJson();
  return mergeConflict(
    localJson: localWins ? winnerJson : loserJson,
    remoteJson: localWins ? loserJson : winnerJson,
    localWins: localWins,
  );
}

void main() {
  group('mergeConflict scalar and map behavior', () {
    test('preserves fields present on only one side', () {
      final merged = mergeConflict(
        localJson: const {'id': 'row', 'name': 'Alice'},
        remoteJson: const {'id': 'row', 'phone': '555'},
        localWins: true,
      );

      expect(merged, containsPair('name', 'Alice'));
      expect(merged, containsPair('phone', '555'));
    });

    test('uses the selected winner for same-field scalar conflicts', () {
      final localWins = mergeConflict(
        localJson: const {'id': 'row', 'name': 'Alice'},
        remoteJson: const {'id': 'row', 'name': 'Bob'},
        localWins: true,
      );
      final remoteWins = mergeConflict(
        localJson: const {'id': 'row', 'name': 'Alice'},
        remoteJson: const {'id': 'row', 'name': 'Bob'},
        localWins: false,
      );

      expect(localWins['name'], 'Alice');
      expect(remoteWins['name'], 'Bob');
    });

    test('uses winner map snapshot, including only its distinct keys', () {
      final merged = mergeConflict(
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
        '21': 'filling',
        '12': 'remote',
      });
    });

    test('unions additive operator assignments without duplicates', () {
      final merged = mergeConflict(
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

  group('mergeConflict serialized collection snapshots', () {
    for (final localWins in [true, false]) {
      final winningSide = localWins ? 'local' : 'remote';

      test('$winningSide winner clears omitted prescriptions and maps', () {
        final original = Appointment.fromJson({
          'id': 'row',
          'date': 28400400,
          'prescriptions': ['existing prescription'],
          'teeth': {'11': 'existing treatment'},
          'teethExtraNotes': {'11': 'existing note'},
          'drawings': {'11': 'existing drawing'},
        });
        final winner = original.copy(false)
          ..prescriptions.clear()
          ..teeth.clear()
          ..teethExtraNotes.clear()
          ..drawings.clear()
          ..postOpNotes = 'Winning edit';
        final loser = original.copy(false)
          ..preOpNotes = 'Nonconflicting losing edit';
        final clearedFields = [
          'prescriptions',
          'teeth',
          'teethExtraNotes',
          'drawings',
        ];
        for (final field in clearedFields) {
          expect(winner.toJson().containsKey(field), isFalse, reason: field);
          expect(loser.toJson().containsKey(field), isTrue, reason: field);
        }

        final merged = _mergeModelSnapshots(
          winner: winner,
          loser: loser,
          localWins: localWins,
        );
        final restored = Appointment.fromJson(merged);

        for (final field in clearedFields) {
          expect(merged.containsKey(field), isFalse, reason: field);
        }
        expect(restored.prescriptions, isEmpty);
        expect(restored.teeth, isEmpty);
        expect(restored.teethExtraNotes, isEmpty);
        expect(restored.drawings, isEmpty);
        expect(restored.postOpNotes, 'Winning edit');
        expect(restored.preOpNotes, 'Nonconflicting losing edit');
        expect(original.prescriptions, ['existing prescription']);
        expect(original.teeth, {'11': 'existing treatment'});
      });

      for (final field in ['teeth', 'teethExtraNotes', 'drawings']) {
        test('$winningSide winner keeps individual $field deletion', () {
          final original = Appointment.fromJson({
            'id': 'row',
            'date': 28400400,
            field: {'11': 'original value', '12': 'deleted value'},
          });
          final winner = Appointment.fromJson({
            ...original.toJson(),
            field: {'11': 'winning edit', '13': 'winning addition'},
          });
          final loser = Appointment.fromJson({
            ...original.toJson(),
            field: {
              '11': 'losing edit',
              '12': 'losing edit to deleted entry',
              '21': 'losing addition',
            },
            'preOpNotes': 'Nonconflicting losing edit',
          });
          final winnerJson = winner.toJson();
          final winnerBefore = jsonEncode(winnerJson);
          final loserBefore = jsonEncode(loser.toJson());
          final merged = _mergeModelSnapshots(
            winner: winner,
            loser: loser,
            localWins: localWins,
          );

          // Without an ancestor, a loser-only addition and a deletion look
          // identical. The winner's snapshot must be authoritative for both.
          expect(merged[field], {
            '11': 'winning edit',
            '13': 'winning addition',
          });
          expect(
            Appointment.fromJson(merged).toJson()[field],
            winnerJson[field],
          );
          expect(merged['preOpNotes'], 'Nonconflicting losing edit');
          expect(jsonEncode(winner.toJson()), winnerBefore);
          expect(jsonEncode(loser.toJson()), loserBefore);
        });
      }

      test('$winningSide winner preserves prescriptions after removing one',
          () {
        final original = Appointment.fromJson({
          'id': 'row',
          'date': 28400400,
          'prescriptions': ['kept', 'deleted'],
        });
        final winner = original.copy(false)..prescriptions.remove('deleted');
        final loser = original.copy(false)
          ..prescriptions.add('losing addition');
        final merged = _mergeModelSnapshots(
          winner: winner,
          loser: loser,
          localWins: localWins,
        );

        expect(merged['prescriptions'], ['kept']);
        expect(Appointment.fromJson(merged).prescriptions, ['kept']);
      });

      test('$winningSide winner clears omitted patient tags and tooth maps',
          () {
        final original = Patient.fromJson({
          'id': 'row',
          'title': 'Patient',
          'birth': 1990,
          'tags': ['existing tag'],
          'teeth': {'11': 'existing treatment'},
          'teethExtraNotes': {'11': 'existing note'},
        });
        final winner = original.copy(false)
          ..tags.clear()
          ..teeth.clear()
          ..teethExtraNotes.clear();
        final loser = original.copy(false)
          ..notes = 'Nonconflicting losing edit';
        for (final field in ['tags', 'teeth', 'teethExtraNotes']) {
          expect(winner.toJson().containsKey(field), isFalse, reason: field);
          expect(loser.toJson().containsKey(field), isTrue, reason: field);
        }
        final merged = _mergeModelSnapshots(
          winner: winner,
          loser: loser,
          localWins: localWins,
        );
        final restored = Patient.fromJson(merged);

        expect(merged.containsKey('tags'), isFalse);
        expect(merged.containsKey('teeth'), isFalse);
        expect(merged.containsKey('teethExtraNotes'), isFalse);
        expect(restored.tags, isEmpty);
        expect(restored.teeth, isEmpty);
        expect(restored.teethExtraNotes, isEmpty);
        expect(restored.notes, 'Nonconflicting losing edit');
      });

      test('$winningSide winner keeps collection additions absent from loser',
          () {
        final winner = Appointment.fromJson({
          'id': 'row',
          'date': 28400400,
          'prescriptions': ['winning prescription'],
          'teeth': {'11': 'winning treatment'},
          'teethExtraNotes': {'11': 'winning note'},
          'drawings': {'11': 'winning drawing'},
        });
        final loser = Appointment.fromJson({'id': 'row', 'date': 28400400});
        final merged = _mergeModelSnapshots(
          winner: winner,
          loser: loser,
          localWins: localWins,
        );

        expect(merged, winner.toJson());
      });
    }
  });

  group('mergeConflict explicit empty collection snapshots', () {
    for (final localWins in [true, false]) {
      test('${localWins ? 'local' : 'remote'} winner preserves explicit clears',
          () {
        const winner = {
          'id': 'row',
          'tags': <String>[],
          'prescriptions': <String>[],
          'teeth': <String, String>{},
          'teethExtraNotes': <String, String>{},
          'drawings': <String, String>{},
        };
        const loser = {
          'id': 'row',
          'tags': ['losing tag'],
          'prescriptions': ['losing prescription'],
          'teeth': {'11': 'losing treatment'},
          'teethExtraNotes': {'11': 'losing note'},
          'drawings': {'11': 'losing drawing'},
        };
        final merged = mergeConflict(
          localJson: localWins ? winner : loser,
          remoteJson: localWins ? loser : winner,
          localWins: localWins,
        );

        expect(merged['tags'], isEmpty);
        expect(merged['prescriptions'], isEmpty);
        expect(merged.containsKey('teeth'), isFalse);
        expect(merged.containsKey('teethExtraNotes'), isFalse);
        expect(merged.containsKey('drawings'), isFalse);
      });
    }
  });

  group('mergeConflict image reconciliation', () {
    test('keeps a server-present DICOM reference case-insensitively', () {
      final merged = mergeConflict(
        localJson: const {
          'id': 'row',
          'dcmImgs': ['scan.dcm']
        },
        remoteJson: const {'id': 'row', 'dcmImgs': <String>[]},
        localWins: true,
        serverFiles: const ['SCAN.DCM'],
      );

      expect(merged['dcmImgs'], ['scan.dcm']);
    });

    test('keeps a pending upload only for the supplied row context', () {
      final withPendingRow = mergeConflict(
        localJson: const {
          'id': 'row-a',
          'dcmImgs': ['scan.dcm']
        },
        remoteJson: const {'id': 'row-a', 'dcmImgs': <String>[]},
        localWins: true,
        pendingUploads: const {'scan.dcm'},
      );
      final withoutPendingRow = mergeConflict(
        localJson: const {
          'id': 'row-b',
          'dcmImgs': ['scan.dcm']
        },
        remoteJson: const {'id': 'row-b', 'dcmImgs': <String>[]},
        localWins: true,
      );

      expect(withPendingRow['dcmImgs'], ['scan.dcm']);
      expect(withoutPendingRow['dcmImgs'], isEmpty);
    });

    test('does not keep a DICOM preview as a raw DICOM reference', () {
      final merged = mergeConflict(
        localJson: const {
          'id': 'row',
          'dcmImgs': ['scan.dcm.png']
        },
        remoteJson: const {'id': 'row', 'dcmImgs': <String>[]},
        localWins: true,
        serverFiles: const ['scan.dcm.png'],
      );

      expect(merged['dcmImgs'], isEmpty);
    });

    test('server files are authoritative for ordinary images and DICOM files',
        () {
      final merged = mergeConflict(
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
      final merged = mergeConflict(
        localJson: const {
          'id': 'row',
          'imgs': ['queued.jpg'],
          'dcmImgs': ['queued.dicom'],
        },
        remoteJson: const {
          'id': 'row',
          'imgs': <String>[],
          'dcmImgs': <String>[]
        },
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
      final rowAPending = filenamesFromDeferredForRow(deferred, 'row-a');
      final rowBPending = filenamesFromDeferredForRow(deferred, 'row-b');

      final rowA = mergeConflict(
        localJson: const {
          'id': 'row-a',
          'dcmImgs': ['same.dcm']
        },
        remoteJson: const {'id': 'row-a', 'dcmImgs': <String>[]},
        localWins: true,
        pendingUploads: rowAPending,
      );
      final rowB = mergeConflict(
        localJson: const {
          'id': 'row-b',
          'dcmImgs': ['same.dcm']
        },
        remoteJson: const {'id': 'row-b', 'dcmImgs': <String>[]},
        localWins: true,
        pendingUploads: rowBPending,
      );

      expect(rowAPending, {'same.dcm'});
      expect(rowBPending, {'same.dcm'});
      expect(rowA['dcmImgs'], ['same.dcm']);
      expect(rowB['dcmImgs'], ['same.dcm']);
      expect(
        filenamesFromDeferredForRow(deferred, 'row-c'),
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
      final pending = filenamesFromDeferredForRow(deferred, 'row');

      expect(pending, {'valid.dcm'});
      final merged = mergeConflict(
        localJson: const {
          'id': 'row',
          'imgs': ['old.jpg', 'valid.dcm'],
        },
        remoteJson: const {'id': 'row', 'imgs': <String>[]},
        localWins: true,
        pendingUploads: pending,
      );
      expect(merged['imgs'], ['valid.dcm']);
    });

    test('image fields tolerate null and non-list JSON values', () {
      final merged = mergeConflict(
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

    for (final localWins in [true, false]) {
      final winningSide = localWins ? 'local' : 'remote';
      for (final clearAll in [true, false]) {
        final deletion = clearAll ? 'clear-all' : 'individual deletion';
        test('persists $winningSide $deletion without resurrecting collections',
            () async {
          final original = Appointment.fromJson({
            'id': 'row-1',
            'date': 28400400,
            'prescriptions': ['kept prescription', 'deleted prescription'],
            'teeth': {'11': 'kept treatment', '12': 'deleted treatment'},
            'teethExtraNotes': {'11': 'kept note', '12': 'deleted note'},
            'drawings': {'11': 'kept drawing', '12': 'deleted drawing'},
          });
          final winner = original.copy(false);
          if (clearAll) {
            winner.prescriptions.clear();
            winner.teeth.clear();
            winner.teethExtraNotes.clear();
            winner.drawings.clear();
          } else {
            winner.prescriptions.remove('deleted prescription');
            winner.teeth.remove('12');
            winner.teethExtraNotes.remove('12');
            winner.drawings.remove('12');
          }
          final loser = original.copy(false)
            ..preOpNotes = 'Nonconflicting losing edit';
          final localJson = (localWins ? winner : loser).toJson();
          final remoteJson = (localWins ? loser : winner).toJson();
          await local.put({original.id: jsonEncode(localJson)});
          await local.putVersion(1);
          await local.putDeferred({original.id: localWins ? 2000 : 1000});
          remote = _MergeSyncRemote(
            remoteVersion: 2,
            remoteUpdates: VersionedResult(
              2,
              [
                Row(
                  id: original.id,
                  data: jsonEncode(remoteJson),
                  ts: localWins ? 1000 : 2000,
                ),
              ],
            ),
          );
          store = _MergeSyncStore(local: local, remote: remote);
          await store.loaded;

          final result = await store.debugSyncTry();
          final expected = winner.toJson()
            ..['preOpNotes'] = 'Nonconflicting losing edit';
          final savedJson =
              jsonDecode(await local.get(original.id)) as Map<String, dynamic>;
          final saved = Appointment.fromJson(savedJson);

          expect(result.exception, isNull);
          expect(result.conflicts, 1);
          expect(savedJson, expected);
          expect(remote.pushed, hasLength(1));
          expect(remote.pushed.single.id, original.id);
          expect(jsonDecode(remote.pushed.single.data), expected);
          expect(saved.prescriptions, winner.prescriptions);
          expect(saved.teeth, winner.teeth);
          expect(saved.teethExtraNotes, winner.teethExtraNotes);
          expect(saved.drawings, winner.drawings);
          expect(await local.getDeferred(), isEmpty);
          expect(await local.getVersion(), 2);
        });
      }
    }

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
      expect(
          (jsonDecode(await local.get(rowA))
              as Map<String, dynamic>)['dcmImgs'],
          ['same.dcm']);
      expect(
          (jsonDecode(remote.pushed.single.data)
              as Map<String, dynamic>)['dcmImgs'],
          ['same.dcm']);
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

  group('mergeConflict scalar, list, and identity edge cases', () {
    test('preserves the record ID from local when both IDs are present', () {
      final merged = mergeConflict(
        localJson: const {'id': 'local-id', 'name': 'Alice'},
        remoteJson: const {'id': 'remote-id', 'name': 'Bob'},
        localWins: false,
      );

      expect(merged['id'], 'local-id');
    });

    test('uses remote value for a scalar when remote wins', () {
      final merged = mergeConflict(
        localJson: const {'id': 'row', 'date': '2026-08-01'},
        remoteJson: const {'id': 'row', 'date': '2026-08-02'},
        localWins: false,
      );

      expect(merged['date'], '2026-08-02');
    });

    test('uses local value for whole-list tags and prescriptions', () {
      final merged = mergeConflict(
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
      final merged = mergeConflict(
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

    test('uses winner snapshots for all configured map fields', () {
      final merged = mergeConflict(
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

      expect(merged['teeth'], {'11': 'crown'});
      expect(merged['teethExtraNotes'], {'11': 'local note'});
      expect(merged['drawings'], {'a': 'local drawing'});
    });

    test('operatorsIDs deduplicate exact values but preserve distinct casing',
        () {
      final merged = mergeConflict(
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
      final merged = mergeConflict(
        localJson: const {
          'id': 'row',
          'teeth': <String, String>{},
          'operatorsIDs': <String>[]
        },
        remoteJson: const {'id': 'row'},
        localWins: true,
      );

      expect(merged.containsKey('teeth'), isFalse);
      expect(merged.containsKey('operatorsIDs'), isFalse);
    });

    test('map values are stringified consistently', () {
      final merged = mergeConflict(
        localJson: const {
          'id': 'row',
          'teeth': {'11': 1, '12': true},
        },
        remoteJson: const {
          'id': 'row',
          'teeth': {'21': true},
        },
        localWins: true,
      );

      expect(merged['teeth'], {'11': '1', '12': 'true'});
    });
  });
}
