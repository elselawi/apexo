import 'dart:io';

import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/adapters.dart';

import '../../../helpers/hive_setup.dart';

void main() {
  group('DicomLinksStore production Hive persistence', () {
    late Directory hiveDirectory;
    late DicomLinksStore store;
    late String boxName;
    var boxNumber = 0;

    setUpAll(() async {
      hiveDirectory = await setupTestHive();
    });

    setUp(() {
      boxName = 'dicom-links-test-${boxNumber++}';
      store = DicomLinksStore.createForTesting(
        boxName: boxName,
        storagePath: hiveDirectory.path,
      );
    });

    tearDown(() async {
      await store.disposeForTesting();
    });

    tearDownAll(() async {
      await teardownTestHive(hiveDirectory);
    });

    test('concurrent init callers share one initialization future', () async {
      final first = store.init();
      final second = store.init();

      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(store.debugInitialization, same(first));
    });

    test('failed initialization clears the future and can be retried',
        () async {
      store.debugFailInitialization = true;
      final failed = store.init();

      await expectLater(failed, throwsA(isA<StateError>()));
      expect(store.debugInitialization, isNull);

      await store.init();
      expect(await store.allImportedKeys, isEmpty);
      expect(store.debugInitialization, isNotNull);
    });

    test('initialization rebuilds cache before accessors complete', () async {
      final box = await Hive.openBox<String>(
        'seeded-links',
        path: hiveDirectory.path,
      );
      await box.put('P100', '{"p":"apexo-1","k":["sop:seed"]}');
      await box.close();
      store = DicomLinksStore.createForTesting(
        boxName: 'seeded-links',
        storagePath: hiveDirectory.path,
      );

      expect(await store.allImportedKeys, {'sop:seed'});
      expect(store.linkedPatients, {'P100': 'apexo-1'});
      expect(store.importedCount, 1);
    });

    test('persisted mutations survive a new store instance', () async {
      await store.linkFile('P100', 'sop:one');
      await store.setPatient('P100', 'apexo-1');
      await store.disposeForTesting();
      store = DicomLinksStore.createForTesting(
        boxName: boxName,
        storagePath: hiveDirectory.path,
      );

      expect(await store.allImportedKeys, {'sop:one'});
      expect(store.linkedPatients, {'P100': 'apexo-1'});
    });

    test('reports imported DICOM counts per patient', () async {
      await store.linkFile('P100', 'sop:one');
      await store.linkFile('P100', 'sop:two');
      await store.linkFile('P200', 'sop:three');

      expect(store.importedFileCountFor('P100'), 2);
      expect(store.importedFileCountFor('P200'), 1);
      expect(store.importedFileCountFor('P999'), 0);
    });

    test('concurrent claims have one first winner in production store',
        () async {
      final results = await Future.wait([
        store.linkFile('P1', 'sop:shared'),
        store.linkFile('P2', 'sop:shared'),
        store.linkFile('P3', 'sop:shared'),
      ]);

      expect(results.where((claimed) => claimed), hasLength(1));
      expect(await store.allImportedKeys, {'sop:shared'});
      expect(store.importedCount, 1);
    });

    test('setPatient and linkFile serialization preserves both mutations',
        () async {
      await Future.wait([
        store.linkFile('P100', 'sop:one'),
        store.setPatient('P100', 'apexo-1'),
        store.linkFile('P100', 'sop:two'),
      ]);

      expect(await store.allImportedKeys, {'sop:one', 'sop:two'});
      expect(store.linkedPatients, {'P100': 'apexo-1'});
    });

    test('unlink is serialized with concurrent link mutation', () async {
      await store.linkFile('P100', 'sop:before');
      await Future.wait([
        store.unlink('P100'),
        store.linkFile('P100', 'sop:after'),
      ]);

      // Whichever mutation runs second is authoritative, but the store must
      // remain internally consistent and never lose a persisted marker.
      final keys = await store.allImportedKeys;
      expect(keys, anyOf(isEmpty, {'sop:after'}));
      expect(store.importedCount, keys.length);
    });

    test('removeKey preserves a confirmed patient mapping after final marker',
        () async {
      await store.linkFile('P100', 'sop:last');
      await store.setPatient('P100', 'apexo-1');

      expect(await store.removeKey('sop:last'), isTrue);
      expect(await store.allImportedKeys, isEmpty);
      expect(store.importedFileCountFor('P100'), 0);
      expect(store.linkedPatients, {'P100': 'apexo-1'});
    });

    test('removeKey deletes an empty unlinked entry', () async {
      await store.linkFile('P100', 'sop:last');

      expect(await store.removeKey('sop:last'), isTrue);
      await store.disposeForTesting();
      final box = await Hive.openBox<String>(
        boxName,
        path: hiveDirectory.path,
      );
      expect(box.containsKey('P100'), isFalse);
      await box.close();
      store = DicomLinksStore.createForTesting(
        boxName: boxName,
        storagePath: hiveDirectory.path,
      );
    });

    test('removeKey unknown marker is idempotently false', () async {
      expect(await store.removeKey('sop:missing'), isFalse);
      expect(await store.allImportedKeys, isEmpty);
    });

    test('allImportedKeys and isImported return defensive consistent snapshots',
        () async {
      await store.linkFile('P100', 'sop:one');
      final keys = await store.allImportedKeys;
      keys.add('sop:memory-only');

      expect(await store.allImportedKeys, {'sop:one'});
      expect(await store.isImported('sop:one'), isTrue);
      expect(await store.isImported('sop:memory-only'), isFalse);
    });

    test('linkFile persistence failure does not update cache', () async {
      await store.init();
      await store.debugCloseBoxWithoutReset();

      await expectLater(
        store.linkFile('P100', 'sop:failed'),
        throwsA(anything),
      );
      expect(await store.allImportedKeys, isEmpty);
      expect(store.linkedPatients, isEmpty);
    });

    test('setPatient persistence failure does not update linkedPatients cache',
        () async {
      await store.linkFile('P100', 'sop:one');
      await store.debugCloseBoxWithoutReset();

      await expectLater(
        store.setPatient('P100', 'apexo-failed'),
        throwsA(anything),
      );
      expect(store.linkedPatients, isEmpty);
    });

    test('removeKey persistence failure rethrows and retains marker cache',
        () async {
      await store.linkFile('P100', 'sop:one');
      await store.debugCloseBoxWithoutReset();

      await expectLater(
        store.removeKey('sop:one'),
        throwsA(anything),
      );
      expect(await store.isImported('sop:one'), isTrue);
    });

    test('unlink persistence failure rethrows and retains cache state',
        () async {
      await store.linkFile('P100', 'sop:one');
      await store.debugCloseBoxWithoutReset();

      await expectLater(
        store.unlink('P100'),
        throwsA(anything),
      );
      expect(await store.isImported('sop:one'), isTrue);
    });
  });

  group('dedupKeyFromValues', () {
    test('uses SOP Instance UID when present (primary key)', () {
      final key = dedupKeyFromValues(
        sopInstanceUid: '1.2.840.10008.5.1.4.1.1.7.1',
        studyInstanceUid: '1.2.3',
        seriesInstanceUid: '1.2.3.1',
        instanceNumber: '1',
      );
      expect(key, 'sop:1.2.840.10008.5.1.4.1.1.7.1');
    });

    test('falls back to composite when SOP UID is empty', () {
      final key = dedupKeyFromValues(
        sopInstanceUid: '',
        studyInstanceUid: '1.2.3',
        seriesInstanceUid: '1.2.3.1',
        instanceNumber: '1',
      );
      expect(key, 'composite:1.2.3|1.2.3.1|1');
    });

    test('falls back to composite when SOP UID is whitespace-only', () {
      final key = dedupKeyFromValues(
        sopInstanceUid: '   ',
        studyInstanceUid: '1.2.3',
        seriesInstanceUid: '1.2.3.1',
        instanceNumber: '1',
      );
      expect(key, 'composite:1.2.3|1.2.3.1|1');
    });

    test('same metadata → same key (deterministic)', () {
      final k1 = dedupKeyFromValues(
        sopInstanceUid: '1.2.3',
        studyInstanceUid: '',
        seriesInstanceUid: '',
        instanceNumber: '',
      );
      final k2 = dedupKeyFromValues(
        sopInstanceUid: '1.2.3',
        studyInstanceUid: '',
        seriesInstanceUid: '',
        instanceNumber: '',
      );
      expect(k1, k2);
    });

    test('trims whitespace in SOP UID', () {
      final k1 = dedupKeyFromValues(
        sopInstanceUid: '  1.2.3  ',
        studyInstanceUid: '',
        seriesInstanceUid: '',
        instanceNumber: '',
      );
      expect(k1, 'sop:1.2.3');
    });

    test('trims whitespace in fallback composite', () {
      final key = dedupKeyFromValues(
        sopInstanceUid: '',
        studyInstanceUid: '  1.2.3  ',
        seriesInstanceUid: '  1.2.3.1  ',
        instanceNumber: '  1  ',
      );
      expect(key, 'composite:1.2.3|1.2.3.1|1');
    });

    test('all empty → composite with all-empty segments', () {
      final key = dedupKeyFromValues(
        sopInstanceUid: '',
        studyInstanceUid: '',
        seriesInstanceUid: '',
        instanceNumber: '',
      );
      expect(key, 'composite:||');
    });
  });

  group('DicomLinksStore (in-memory fake)', () {
    late _FakeLinksStore store;

    setUp(() {
      store = _FakeLinksStore();
    });

    test('allImportedKeys returns empty initially', () async {
      expect(await store.allImportedKeys, isEmpty);
    });

    test('linkedPatients returns empty initially', () {
      expect(store.linkedPatients, isEmpty);
    });

    test('linkFile adds a key and allImportedKeys includes it', () async {
      expect(await store.linkFile('P100', 'sop:abc'), isTrue);
      final keys = await store.allImportedKeys;
      expect(keys, contains('sop:abc'));
    });

    test('linkFile returns false when another importer already owns a key',
        () async {
      expect(await store.linkFile('P100', 'sop:abc'), isTrue);
      expect(await store.linkFile('P200', 'sop:abc'), isFalse);
      expect(await store.allImportedKeys, {'sop:abc'});
    });

    test('isImported returns true after linkFile', () async {
      await store.linkFile('P100', 'sop:abc');
      expect(await store.isImported('sop:abc'), isTrue);
    });

    test('isImported returns false for unknown key', () async {
      expect(await store.isImported('sop:xyz'), isFalse);
    });

    test('linkFile is first-wins — duplicate key silently ignored', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.linkFile('P200', 'sop:abc'); // different patient, same key
      final keys = await store.allImportedKeys;
      // Key only appears once — first patient claims it.
      expect(keys.where((k) => k == 'sop:abc').length, 1);
    });

    test('setPatient links a DICOM patient to an Apexo patient', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.setPatient('P100', 'apexo-1');
      expect(store.linkedPatients, containsPair('P100', 'apexo-1'));
    });

    test('linkedPatients only returns entries with a patient set', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.setPatient('P100', 'apexo-1');
      await store.linkFile('P200', 'sop:def'); // no setPatient yet
      final linked = store.linkedPatients;
      expect(linked, containsPair('P100', 'apexo-1'));
      expect(linked, isNot(contains('P200')));
    });

    test('unlink deletes the entire entry — keys and link gone', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.linkFile('P100', 'sop:def');
      await store.setPatient('P100', 'apexo-1');
      await store.unlink('P100');

      expect(await store.isImported('sop:abc'), isFalse);
      expect(await store.isImported('sop:def'), isFalse);
      expect(store.linkedPatients, isNot(contains('P100')));
      expect(await store.allImportedKeys, isEmpty);
    });

    test('unlink of non-existent patient is a no-op', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.unlink('P999'); // doesn't exist
      expect(await store.isImported('sop:abc'), isTrue);
    });

    test('setPatient can change an existing link', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.setPatient('P100', 'apexo-1');
      await store.setPatient('P100', 'apexo-2');
      expect(store.linkedPatients, containsPair('P100', 'apexo-2'));
    });

    test('multiple patients with separate keys are isolated', () async {
      await store.linkFile('P100', 'sop:abc');
      await store.setPatient('P100', 'apexo-1');
      await store.linkFile('P200', 'sop:def');
      await store.setPatient('P200', 'apexo-2');

      expect(await store.isImported('sop:abc'), isTrue);
      expect(await store.isImported('sop:def'), isTrue);
      expect(store.linkedPatients.length, 2);

      // Unlink P100 — P200 should be unaffected.
      await store.unlink('P100');
      expect(await store.isImported('sop:abc'), isFalse);
      expect(await store.isImported('sop:def'), isTrue);
      expect(store.linkedPatients, containsPair('P200', 'apexo-2'));
    });
  });

  group('DicomLinksStore empty-entry retention', () {
    test('retains an empty entry that still has a confirmed patient link', () {
      expect(
        DicomLinksStore.canDeleteEmptyEntry(
          patientId: 'apexo-1',
          keys: const [],
        ),
        isFalse,
      );
    });

    test('deletes an empty unlinked entry', () {
      expect(
        DicomLinksStore.canDeleteEmptyEntry(
          patientId: null,
          keys: const [],
        ),
        isTrue,
      );
    });

    test('retains an entry while it still owns imported-file markers', () {
      expect(
        DicomLinksStore.canDeleteEmptyEntry(
          patientId: null,
          keys: const ['sop:remaining'],
        ),
        isFalse,
      );
    });

    test('last marker removal must not delete a confirmed patient link', () {
      // This is the exact invariant required by dead-letter and healing
      // recovery: clearing the file marker must not turn an auto-link into a
      // manual-match item.
      expect(
        DicomLinksStore.canDeleteEmptyEntry(
          patientId: 'patient-42',
          keys: const [],
        ),
        isFalse,
        reason: 'patient mapping is independent from imported-file markers',
      );
    });

    test('only an explicitly empty unlinked entry is deletable', () {
      expect(
        DicomLinksStore.canDeleteEmptyEntry(
          patientId: '',
          keys: const [],
        ),
        isTrue,
      );
      expect(
        DicomLinksStore.canDeleteEmptyEntry(
          patientId: '   ',
          keys: const [],
        ),
        isFalse,
        reason:
            'whitespace is still a stored patient value and must not be silently discarded',
      );
    });
  });
}

/// Minimal in-memory fake of [DicomLinksStore] for unit tests.
class _FakeLinksStore {
  final Map<String, String> _registry = {};
  final Map<String, String> _patientLinks = {};

  Set<String> get _allKeys => _registry.keys.toSet();
  Map<String, String> get linkedPatients => Map.of(_patientLinks);

  Future<Set<String>> get allImportedKeys async => _allKeys;
  Future<bool> isImported(String key) async => _allKeys.contains(key);

  Future<bool> linkFile(String dicomPatientId, String key) async {
    if (_allKeys.contains(key)) return false; // first-wins
    _registry[key] = dicomPatientId;
    return true;
  }

  Future<void> setPatient(String dicomPatientId, String apexoPatientId) async {
    _patientLinks[dicomPatientId] = apexoPatientId;
  }

  Future<void> unlink(String dicomPatientId) async {
    _registry.removeWhere((_, v) => v == dicomPatientId);
    _patientLinks.remove(dicomPatientId);
  }
}
