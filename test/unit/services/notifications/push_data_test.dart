import 'package:apexo/core/synchronization/push_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushData', () {
    test('fromJson parses all required fields', () {
      final json = {
        'store': 'appointments',
        'id': 'abc123',
        'readableIdentifier': 'John Doe',
        'isCreation': true,
        'isUpdate': false,
        'updatedFields': <String>[],
        'oldVals': <dynamic>[],
        'newVals': <dynamic>[],
        'targetIDs': <String>['user1', 'user2'],
      };

      final push = PushData.fromJson(json);

      expect(push.store, 'appointments');
      expect(push.id, 'abc123');
      expect(push.readableIdentifier, 'John Doe');
      expect(push.isCreation, isTrue);
      expect(push.isUpdate, isFalse);
      expect(push.updatedFields, isEmpty);
      expect(push.oldVals, isEmpty);
      expect(push.newVals, isEmpty);
      expect(push.targetIDs, ['user1', 'user2']);
    });

    test('toJson round-trip preserves all fields', () {
      final original = PushData(
        store: 'notes',
        id: 'note1',
        readableIdentifier: 'Lab Note',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['done'],
        oldVals: [false],
        newVals: [true],
        targetIDs: ['user1'],
      );

      final json = original.toJson();
      final restored = PushData.fromJson(json);

      expect(restored.store, 'notes');
      expect(restored.id, 'note1');
      expect(restored.readableIdentifier, 'Lab Note');
      expect(restored.isCreation, isFalse);
      expect(restored.isUpdate, isTrue);
      expect(restored.updatedFields, ['done']);
      expect(restored.oldVals, [false]);
      expect(restored.newVals, [true]);
      expect(restored.targetIDs, ['user1']);
    });

    test('fromJson handles empty updatedFields/oldVals/newVals', () {
      final json = {
        'store': 'appointments',
        'id': 'x',
        'readableIdentifier': '',
        'isCreation': false,
        'isUpdate': false,
        'updatedFields': <String>[],
        'oldVals': <dynamic>[],
        'newVals': <dynamic>[],
        'targetIDs': <String>[],
      };

      final push = PushData.fromJson(json);

      expect(push.updatedFields, isEmpty);
      expect(push.oldVals, isEmpty);
      expect(push.newVals, isEmpty);
      expect(push.targetIDs, isEmpty);
    });

    test('toJson produces valid map', () {
      final push = PushData(
        store: 'appointments',
        id: 'test',
        readableIdentifier: 'Patient X',
        isCreation: true,
        isUpdate: false,
        updatedFields: ['date'],
        oldVals: [1000],
        newVals: [2000],
        targetIDs: ['u1'],
      );

      final map = push.toJson();

      expect(map, isA<Map<String, dynamic>>());
      expect(map['store'], 'appointments');
      expect(map['id'], 'test');
      expect(map['isCreation'], true);
      expect(map['updatedFields'], ['date']);
    });

    test('fromChange reads the before/after values in field order', () {
      final push = PushData.fromChange(
        store: 'appointments',
        id: 'appt1',
        readableIdentifier: 'Ada Lovelace',
        isCreation: false,
        changed: const ['date', 'isDone'],
        before: const {'date': 200, 'isDone': false},
        after: const {'date': 100, 'isDone': true},
        targets: const ['account1'],
      );

      expect(push.isCreation, isFalse);
      expect(push.isUpdate, isTrue);
      expect(push.updatedFields, ['date', 'isDone']);
      expect(push.oldVals, [200, false]);
      expect(push.newVals, [100, true]);
      expect(push.targetIDs, ['account1']);
    });

    test('fromChange carries no old values for a creation', () {
      final push = PushData.fromChange(
        store: 'notes',
        id: 'note1',
        readableIdentifier: 'Call the lab',
        isCreation: true,
        changed: const [],
        before: null,
        after: const {'done': true},
        targets: const ['account1'],
      );

      expect(push.isCreation, isTrue);
      expect(push.isUpdate, isFalse);
      expect(push.updatedFields, isEmpty);
      expect(push.oldVals, isEmpty);
      expect(push.newVals, isEmpty);
    });
  });
}
