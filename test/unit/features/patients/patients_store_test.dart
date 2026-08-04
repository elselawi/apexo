@Tags(['serial'])
library;

import 'package:apexo/core/observable.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Patients store', () {
    setUp(() {
      patients.observableMap.clear();
    });

    test('singleton is Patients instance', () {
      expect(patients, isA<Patients>());
    });

    test('observableMap is ObservableDict', () {
      expect(patients.observableMap, isA<ObservableDict<Patient>>());
    });

    test('observableMap values returns list', () {
      expect(patients.observableMap.values, isA<List<Patient>>());
    });

    test('present returns a map', () {
      expect(patients.present, isA<Map<String, Patient>>());
    });

    test('allTags returns a list', () {
      expect(patients.allTags, isA<List<String>>());
    });

    test('present excludes archived patients and preserves active patients',
        () {
      patients.setAll([
        testPatient(id: 'active', tags: ['vip']),
        testPatient(id: 'archived', archived: true, tags: ['old']),
      ]);

      expect(patients.present.keys, {'active'});
      expect(patients.docs.keys, {'active', 'archived'});
    });

    test('allTags returns distinct tags from active patients only', () {
      patients.setAll([
        testPatient(id: 'one', tags: ['vip', 'allergy']),
        testPatient(id: 'two', tags: ['vip', 'diabetic']),
        testPatient(id: 'archived', archived: true, tags: ['hidden']),
      ]);

      expect(patients.allTags.toSet(), {'vip', 'allergy', 'diabetic'});
    });

    test('set updates an existing patient rather than adding a duplicate', () {
      final patient = testPatient(id: 'update', name: 'Before');
      patients.set(patient);
      patient.title = 'After';
      patients.set(patient);

      expect(patients.docs.length, 1);
      expect(patients.get('update')!.title, 'After');
    });

    test('archive and restore update present visibility', () {
      patients.set(testPatient(id: 'visibility'));
      expect(patients.present.containsKey('visibility'), isTrue);

      patients.archive('visibility');
      expect(patients.present.containsKey('visibility'), isFalse);

      patients.unarchive('visibility');
      expect(patients.present.containsKey('visibility'), isTrue);
    });
  });
}
