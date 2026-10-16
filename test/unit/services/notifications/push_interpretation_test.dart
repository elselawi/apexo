import 'dart:io';

import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  late int originalLocale;
  late String originalEmail;
  late String originalPatientId;
  late List<RecordModel> originalAccounts;

  setUp(() {
    originalLocale = localSettings.selectedLocale;
    originalEmail = login.email;
    originalPatientId = patientSide.patientID;
    originalAccounts = accounts.list();
    localSettings.selectedLocale = 0; // English
    login.email = '';
    patientSide.patientID = '';
    accounts.list([]);
  });

  tearDown(() {
    localSettings.selectedLocale = originalLocale;
    login.email = originalEmail;
    patientSide.patientID = originalPatientId;
    accounts.list(originalAccounts);
  });

  void signInStaff(String accountId) {
    login.email = '$accountId@clinic.test';
    accounts.list([
      RecordModel({
        'id': accountId,
        'email': '$accountId@clinic.test',
        'name': accountId,
        'type': 'user',
      }),
    ]);
    expect(login.currentAccountID, accountId);
  }

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

  group('Locale coverage & JS parity', () {
    test('supports all 10 application locales', () {
      final appLocaleCodes = locale.list.map((l) => l.$code).toSet();
      final pushLocaleCodes = supportedPushLanguageCodes.toSet();
      expect(pushLocaleCodes, equals(appLocaleCodes));
      expect(pushLocaleCodes.length, 10);
    });

    test('every locale has non-empty [title, body] for every interpretation',
        () {
      for (var i = 0; i < locale.list.length; i++) {
        localSettings.selectedLocale = i;
        final code = locale.s.$code;
        for (final interp in PushInterpretation.values) {
          final pair = pushTranslationFor(code, interp);
          expect(pair.length, 2, reason: 'locale $code / $interp');
          expect(pair[0].trim(), isNotEmpty,
              reason: 'title empty for $code / $interp');
          expect(pair[1].trim(), isNotEmpty,
              reason: 'body empty for $code / $interp');
        }
      }
    });

    test('unknown language code falls back to English', () {
      for (final interp in PushInterpretation.values) {
        expect(
          pushTranslationFor('unknown-lang', interp),
          equals(pushTranslationFor('en', interp)),
        );
      }
    });

    test('web/fcm/push_data.js defines all 10 locales and all 19 keys', () {
      final jsFile = File('web/fcm/push_data.js');
      expect(jsFile.existsSync(), isTrue);
      final jsSource = jsFile.readAsStringSync();

      for (final code in supportedPushLanguageCodes) {
        expect(jsSource, contains('[Langs.$code]:'),
            reason: 'web/fcm/push_data.js missing Langs.$code section');
      }
      for (final interp in PushInterpretation.values) {
        expect(jsSource, contains('PushInterpretation.${interp.name}'),
            reason: 'web/fcm/push_data.js missing ${interp.name}');
      }
    });

    test('web/fcm/fcm.js defines prompt translations for all 10 locales', () {
      final fcmJsFile = File('web/fcm/fcm.js');
      expect(fcmJsFile.existsSync(), isTrue);
      final fcmSource = fcmJsFile.readAsStringSync();

      for (final code in supportedPushLanguageCodes) {
        expect(
          RegExp('\\b$code\\s*:\\s*\\{').hasMatch(fcmSource),
          isTrue,
          reason: 'web/fcm/fcm.js missing prompt translation for $code',
        );
      }
    });
  });

  group('interpret() & displayTuple()', () {
    test('returns non-empty strings for appointment creation', () {
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

      expect(push.interpret(), PushInterpretation.newAppointmentForYou);
      final tuple = push.displayTuple();
      expect(tuple.length, 2);
      expect(tuple[0], 'Appointments');
      expect(tuple[1], 'You have a new appointment: Patient');
    });

    test('omits trailing colon when readableIdentifier is blank', () {
      final push = PushData(
        store: 'appointments',
        id: 'test',
        readableIdentifier: '  ',
        isCreation: true,
        isUpdate: false,
        updatedFields: [],
        oldVals: [],
        newVals: [],
        targetIDs: [],
      );

      final tuple = push.displayTuple();
      expect(tuple[1], 'You have a new appointment');
    });

    test('appointment date moved earlier vs later', () {
      final earlier = PushData(
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
      expect(
        earlier.interpret(),
        PushInterpretation.appointmentDateHasBeenMovedEarlier,
      );
      expect(earlier.displayTuple()[1], contains('Patient'));

      final later = PushData(
        store: 'appointments',
        id: 'test',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['date'],
        oldVals: [1000],
        newVals: [2000],
        targetIDs: [],
      );
      expect(
        later.interpret(),
        PushInterpretation.appointmentDateHasBeenMovedLater,
      );
    });

    test('appointment isDone true vs false', () {
      final done = PushData(
        store: 'appointments',
        id: 'a1',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['isDone'],
        oldVals: [false],
        newVals: [true],
        targetIDs: [],
      );
      expect(done.interpret(), PushInterpretation.appointmentIsNowDone);

      final undone = PushData(
        store: 'appointments',
        id: 'a1',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['isDone'],
        oldVals: [true],
        newVals: [false],
        targetIDs: [],
      );
      expect(
        undone.interpret(),
        PushInterpretation.appointmentStatusBeenChanged,
      );
    });

    test('appointment archived true (cancelled) vs false (restored)', () {
      final cancelled = PushData(
        store: 'appointments',
        id: 'a1',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['archived'],
        oldVals: [false],
        newVals: [true],
        targetIDs: [],
      );
      expect(
        cancelled.interpret(),
        PushInterpretation.appointmentHasBeenCancelled,
      );

      final restored = PushData(
        store: 'appointments',
        id: 'a1',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['archived'],
        oldVals: [true],
        newVals: [false],
        targetIDs: [],
      );
      expect(
        restored.interpret(),
        PushInterpretation.appointmentStatusBeenChanged,
      );
    });

    test('appointment operatorsIDs checks current staff or patient account',
        () {
      signInStaff('doc1');
      final assignedToMe = PushData(
        store: 'appointments',
        id: 'a1',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['operatorsIDs'],
        oldVals: [
          ['doc2']
        ],
        newVals: [
          ['doc1', 'doc2']
        ],
        targetIDs: [],
      );
      expect(
        assignedToMe.interpret(),
        PushInterpretation.appointmentHasBeenAssignedToYou,
      );

      final assignedToOther = PushData(
        store: 'appointments',
        id: 'a1',
        readableIdentifier: 'Patient',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['operatorsIDs'],
        oldVals: [
          ['doc1']
        ],
        newVals: [
          ['doc2']
        ],
        targetIDs: [],
      );
      expect(
        assignedToOther.interpret(),
        PushInterpretation.appointmentStatusBeenChanged,
      );
    });

    test('note creation and updates', () {
      signInStaff('doc1');

      final created = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: true,
        isUpdate: false,
        updatedFields: [],
        oldVals: [],
        newVals: [],
        targetIDs: [],
      );
      expect(created.interpret(), PushInterpretation.newNoteForYou);
      expect(created.displayTuple()[1], contains('Note Title'));

      final commentAdded = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['comments'],
        oldVals: [<List<String>>[]],
        newVals: [
          [
            ['doc2', 'hello']
          ]
        ],
        targetIDs: [],
      );
      expect(
        commentAdded.interpret(),
        PushInterpretation.newCommentAddedToYourNote,
      );

      final attachmentAdded = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['attachments'],
        oldVals: [<String>[]],
        newVals: [
          ['file.png']
        ],
        targetIDs: [],
      );
      expect(
        attachmentAdded.interpret(),
        PushInterpretation.newAttachmentsAddedToYourNote,
      );

      final markedDone = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['done'],
        oldVals: [false],
        newVals: [true],
        targetIDs: [],
      );
      expect(markedDone.interpret(), PushInterpretation.noteHasBeenMarkedAsDone);

      final markedPending = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['done'],
        oldVals: [true],
        newVals: [false],
        targetIDs: [],
      );
      expect(
        markedPending.interpret(),
        PushInterpretation.noteHasBeenMarkedAsPending,
      );

      final assignedToMe = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['assignedTo'],
        oldVals: ['doc2'],
        newVals: ['doc1'],
        targetIDs: [],
      );
      expect(
        assignedToMe.interpret(),
        PushInterpretation.aNewNoteHasBeenAssignedToYou,
      );

      final assignedToOther = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['assignedTo'],
        oldVals: ['doc1'],
        newVals: ['doc2'],
        targetIDs: [],
      );
      expect(
        assignedToOther.interpret(),
        PushInterpretation.assigneeOnYourNoteHasChanged,
      );

      final dueEarlier = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['dueDate'],
        oldVals: [500],
        newVals: [400],
        targetIDs: [],
      );
      expect(
        dueEarlier.interpret(),
        PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier,
      );

      final dueLater = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['dueDate'],
        oldVals: [400],
        newVals: [500],
        targetIDs: [],
      );
      expect(
        dueLater.interpret(),
        PushInterpretation.dueDateOnYourNoteHasBeenMovedLater,
      );

      final archived = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['archived'],
        oldVals: [false],
        newVals: [true],
        targetIDs: [],
      );
      expect(archived.interpret(), PushInterpretation.yourNoteHasBeenArchived);

      final unarchived = PushData(
        store: 'notes',
        id: 'n1',
        readableIdentifier: 'Note Title',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['archived'],
        oldVals: [true],
        newVals: [false],
        targetIDs: [],
      );
      expect(
        unarchived.interpret(),
        PushInterpretation.yourNoteHasBeenUnarchived,
      );
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
