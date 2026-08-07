import 'dart:async';

import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRegistry {
  final Map<String, String> owners = {};
  final Map<String, String> patients = {};
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> linkFile(String patient, String key) => _serialized(() async {
        if (owners.containsKey(key)) return false;
        owners[key] = patient;
        return true;
      });

  Future<void> setPatient(String patient, String apexo) =>
      _serialized(() async {
        patients[patient] = apexo;
      });
}

void main() {
  test('serialized first-wins claims keep exactly one owner', () async {
    final registry = _MemoryRegistry();
    final results = await Future.wait([
      registry.linkFile('P1', 'sop:shared'),
      registry.linkFile('P2', 'sop:shared'),
      registry.linkFile('P3', 'sop:shared'),
    ]);

    expect(results.where((claimed) => claimed), hasLength(1));
    expect(registry.owners, hasLength(1));
  });

  test('patient link mutation is serialized with marker mutation', () async {
    final registry = _MemoryRegistry();
    await Future.wait([
      registry.linkFile('P1', 'sop:one'),
      registry.setPatient('P1', 'apexo-1'),
    ]);

    expect(registry.owners['sop:one'], 'P1');
    expect(registry.patients['P1'], 'apexo-1');
  });

  test('empty-entry deletion policy retains confirmed links', () {
    expect(
      DicomLinksStore.canDeleteEmptyEntry(
        patientId: 'apexo-1',
        keys: const [],
      ),
      isFalse,
    );
    expect(
      DicomLinksStore.canDeleteEmptyEntry(
        patientId: null,
        keys: const [],
      ),
      isTrue,
    );
  });
}
