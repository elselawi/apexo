import 'package:apexo/services/notifications/push_data.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushInterpretation', () {
    test('enum has expected values', () {
      expect(PushInterpretation.values,
          contains(PushInterpretation.newAppointmentForYou));
      expect(PushInterpretation.values,
          contains(PushInterpretation.newNoteForYou));
      expect(PushInterpretation.values,
          contains(PushInterpretation.newNotification));
      expect(PushInterpretation.values,
          contains(PushInterpretation.appointmentIsNowDone));
      expect(PushInterpretation.values,
          contains(PushInterpretation.appointmentHasBeenCancelled));
      expect(PushInterpretation.values,
          contains(PushInterpretation.appointmentHasBeenAssignedToYou));
      expect(PushInterpretation.values,
          contains(PushInterpretation.noteHasBeenMarkedAsDone));
      expect(PushInterpretation.values,
          contains(PushInterpretation.noteHasBeenMarkedAsPending));
    });

    test('enum toString returns enum name', () {
      expect(
        PushInterpretation.newAppointmentForYou.toString(),
        contains('newAppointmentForYou'),
      );
    });

    test('enum values are unique', () {
      const values = PushInterpretation.values;
      final names = values.map((e) => e.name).toList();
      expect(names.length, names.toSet().length);
      expect(names.length, 19);
    });
  });

  group('displayTuple', () {
    test('returns non-empty strings', () {
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

    test('for update with date field', () {
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

    test('for note creation', () {
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

    test('falls back to the generic text for an uninterpretable payload', () {
      final push = PushData(
        store: 'appointments',
        id: 'test',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        // `date` is named but carries no value on either side: the short list
        // must degrade to the generic notice instead of throwing.
        updatedFields: ['date'],
        oldVals: [],
        newVals: [],
        targetIDs: [],
      );

      final tuple = push.displayTuple();

      expect(tuple.length, 2);
      expect(push.uninterpretableReported, isTrue);
    });
  });
}
