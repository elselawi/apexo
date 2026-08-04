import 'package:apexo/services/notifications/model_push_data.dart';
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

    test('displayTuple returns non-empty strings', () {
      final push = PushData(
        store: 'appointments',
        id: 'test',
        readableIdentifier: 'Patient',
        isCreation: true,
        isUpdate: false,
        updatedFields: [],
        oldVals: [],
        newVals: [],
        targetIDs: [],
      );

      final tuple = push.displayTuple();

      expect(tuple.length, 2);
      expect(tuple[0], isNotEmpty);
      expect(tuple[1], isNotEmpty);
    });

    test('displayTuple for update with date field', () {
      final push = PushData(
        store: 'appointments',
        id: 'test',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['date'],
        oldVals: [2000],
        newVals: [1000],
        targetIDs: [],
      );

      final tuple = push.displayTuple();

      expect(tuple.length, 2);
      expect(tuple[1], contains('Patient'));
    });

    test('displayTuple for note creation', () {
      final push = PushData(
        store: 'notes',
        id: 'test',
        readableIdentifier: 'Note Title',
        isCreation: true,
        isUpdate: false,
        updatedFields: [],
        oldVals: [],
        newVals: [],
        targetIDs: [],
      );

      final tuple = push.displayTuple();

      expect(tuple.length, 2);
      expect(tuple[1], contains('Note Title'));
    });
  });

  group('PushInterpetation', () {
    test('enum has expected values', () {
      expect(PushInterpetation.values,
          contains(PushInterpetation.newAppointmentForYou));
      expect(
          PushInterpetation.values, contains(PushInterpetation.newNoteForYou));
      expect(PushInterpetation.values,
          contains(PushInterpetation.newNotification));
      expect(PushInterpetation.values,
          contains(PushInterpetation.appointmentIsNowDone));
      expect(PushInterpetation.values,
          contains(PushInterpetation.appointmentHasBeenCancelled));
      expect(PushInterpetation.values,
          contains(PushInterpetation.appointmentHasBeenAssignedToYou));
      expect(PushInterpetation.values,
          contains(PushInterpetation.noteHasBeenMarkedAsDone));
      expect(PushInterpetation.values,
          contains(PushInterpetation.noteHasBeenMarkedAsPending));
    });

    test('enum toString returns enum name', () {
      expect(
        PushInterpetation.newAppointmentForYou.toString(),
        contains('newAppointmentForYou'),
      );
    });

    test('enum values are unique', () {
      const values = PushInterpetation.values;
      final names = values.map((e) => e.name).toList();
      expect(names.length, names.toSet().length);
      expect(names.length, 19);
    });
  });
}
