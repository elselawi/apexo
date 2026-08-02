import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      await store.linkFile('P100', 'sop:abc');
      final keys = await store.allImportedKeys;
      expect(keys, contains('sop:abc'));
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
}

/// Minimal in-memory fake of [DicomLinksStore] for unit tests.
class _FakeLinksStore {
  final Map<String, String> _registry = {};
  final Map<String, String> _patientLinks = {};

  Set<String> get _allKeys => _registry.keys.toSet();
  Map<String, String> get linkedPatients => Map.of(_patientLinks);

  Future<Set<String>> get allImportedKeys async => _allKeys;
  Future<bool> isImported(String key) async => _allKeys.contains(key);

  Future<void> linkFile(String dicomPatientId, String key) async {
    if (_allKeys.contains(key)) return; // first-wins
    _registry[key] = dicomPatientId;
  }

  Future<void> setPatient(String dicomPatientId, String apexoPatientId) async {
    _patientLinks[dicomPatientId] = apexoPatientId;
  }

  Future<void> unlink(String dicomPatientId) async {
    _registry.removeWhere((_, v) => v == dicomPatientId);
    _patientLinks.remove(dicomPatientId);
  }
}
