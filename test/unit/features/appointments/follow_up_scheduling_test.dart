@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show globalSettings;
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/row_panel.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

/// A follow-up is a promise about a **day**, and it belongs to the **patient**.
/// These tests are that sentence, once per case — including the two surfaces
/// that edit it.
void main() {
  late List<Patient> originalPatients;
  late List<Appointment> originalAppointments;
  late List<int> originalPermissions;
  late int originalRevision;
  late bool originalFollowUps;

  setUp(() {
    originalPermissions = login.savedPermissions;
    originalRevision = followUpRevision();
    originalFollowUps = globalSettings.followUpsEnabled;
    login.savedPermissions = Perm.full;
    // Follow-ups are an optional feature; these tests are what it does when on.
    globalSettings.followUpsEnabled = true;
    originalPatients = patients.docs.values.toList();
    originalAppointments = appointments.docs.values.toList();
    appointmentSessions.clear();
    PanelsManager.closeAll();
    appointments.observableMap.clear();
    patients.observableMap.clear();
    patients.set(testPatient(id: 'follow-patient', name: 'Follow Patient'));
    patients.set(testPatient(id: 'other-patient', name: 'Other Patient'));
  });

  tearDown(() {
    PanelsManager.closeAll();
    appointmentSessions.clear();
    appointments.observableMap.clear();
    appointments.setAll(originalAppointments);
    patients.observableMap.clear();
    patients.setAll(originalPatients);
    login.savedPermissions = originalPermissions;
    followUpRevision(originalRevision);
    globalSettings.followUpsEnabled = originalFollowUps;
  });

  group('the stored day', () {
    test('travels in the patient record and comes back as the same day', () {
      final patient = patients.get('follow-patient')!
        ..followUpDate = DateTime(2026, 3, 24);
      final again = patients.modeling(patient.toJson());

      expect(again.followUpDay, DateTime(2026, 3, 24));
      expect(again.hasFollowUp, isTrue);
    });

    test('is absent from the JSON when no follow-up is planned', () {
      final patient = patients.get('follow-patient')!;
      expect(patient.toJson().containsKey('followUp'), isFalse);
      expect(patient.followUpDay, isNull);
    });

    test('is a day, not an hour', () {
      final patient = patients.get('follow-patient')!
        ..followUpDate = DateTime(2026, 3, 24, 17, 45);
      expect(patient.followUpDay, DateTime(2026, 3, 24));
    });

    test('serialization drops the hour without rounding into the next day', () {
      final patient = patients.get('follow-patient')!
        ..followUpDate = DateTime(2026, 3, 24, 23, 59, 59);
      final again = patient.copy(false);

      expect(again.followUpDate, DateTime(2026, 3, 24));
      expect(again.followUpDay, patient.followUpDay);
      expect(patient.followUpDate, DateTime(2026, 3, 24, 23, 59, 59),
          reason: 'serializing must not mutate the source');
    });

    test('adopting a snapshot without a follow-up clears the previous day', () {
      final patient = patients.get('follow-patient')!;
      final withoutFollowUp = patient.toJson();
      patient.followUpDate = DateTime(2026, 3, 24);

      patient.fromJson(withoutFollowUp);

      expect(patient.followUpDay, isNull);
      expect(patient.hasFollowUp, isFalse);
      expect(patient.toJson().containsKey('followUp'), isFalse);
    });

    test('an explicit null takes the promise back', () {
      final patient = patients.get('follow-patient')!
        ..followUpDate = DateTime(2026, 3, 24);
      patient.fromJson({...patient.toJson(), 'followUp': null});
      expect(patient.followUpDay, isNull);
    });
  });

  group('presets', () {
    test('count days, weeks and calendar months', () {
      final day = DateTime(2026, 1, 20);
      expect(kFollowUpPresets[0].from(day), DateTime(2026, 1, 27)); // 1w
      expect(kFollowUpPresets[1].from(day), DateTime(2026, 1, 30)); // 10d
      expect(kFollowUpPresets[2].from(day), DateTime(2026, 2, 3)); // 2w
      expect(kFollowUpPresets[4].from(day), DateTime(2026, 2, 17)); // 4w
      expect(kFollowUpPresets[5].from(day), DateTime(2026, 3, 20)); // 2m
      expect(kFollowUpPresets[6].from(day), DateTime(2026, 4, 20)); // 3m
    });

    test('calendar months clamp to the last valid day of the target month', () {
      const oneMonth = FollowUpPreset(1, FollowUpUnit.month);
      const twoMonths = FollowUpPreset(2, FollowUpUnit.month);
      const threeMonths = FollowUpPreset(3, FollowUpUnit.month);

      expect(oneMonth.from(DateTime(2026, 1, 31, 17)), DateTime(2026, 2, 28));
      expect(oneMonth.from(DateTime(2024, 1, 31)), DateTime(2024, 2, 29));
      expect(twoMonths.from(DateTime(2026, 12, 31)), DateTime(2027, 2, 28));
      expect(threeMonths.from(DateTime(2026, 1, 31)), DateTime(2026, 4, 30));
      expect(
          oneMonth.fits(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), isTrue);
    });

    test('recognizes its own day as the one it makes', () {
      final day = DateTime(2026, 1, 20);
      final tenDays = kFollowUpPresets[1];
      expect(tenDays.fits(day, DateTime(2026, 1, 30)), isTrue);
      expect(tenDays.fits(day, DateTime(2026, 1, 31)), isFalse);
    });
  });

  group('setting one by hand', () {
    test('stores the day on the patient, not on a visit', () {
      setFollowUp('follow-patient', DateTime(2026, 3, 24, 16));

      expect(
          patients.get('follow-patient')!.followUpDay, DateTime(2026, 3, 24));
    });

    test('writes the note with the day, and takes it back with the day', () {
      setFollowUp('follow-patient', DateTime(2026, 3, 24),
          note: '  Bring the X-ray  ');
      final patient = patients.get('follow-patient')!;
      expect(patient.followUpNote, 'Bring the X-ray',
          reason: 'a note is text, and text is stored trimmed');
      expect(patient.toJson()['followUpNote'], 'Bring the X-ray');

      setFollowUp('follow-patient', patient.followUpDay);
      expect(patients.get('follow-patient')!.followUpNote, 'Bring the X-ray',
          reason: 'a day written without a note keeps the one it carries');

      setFollowUp('follow-patient', null);
      expect(patients.get('follow-patient')!.followUpNote, isEmpty,
          reason: 'no day, no promise, nothing to say about it');
      expect(
          patients.get('follow-patient')!.toJson().containsKey('followUpNote'),
          isFalse);
    });

    test('the note travels in the patient record', () {
      final patient = patients.get('follow-patient')!
        ..followUpDate = DateTime(2026, 3, 24)
        ..followUpNote = 'Bring the X-ray';

      final again = patients.modeling(patient.toJson());

      expect(again.followUpDay, DateTime(2026, 3, 24));
      expect(again.followUpNote, 'Bring the X-ray');
      expect(patient.toJson().containsKey('followUpNote'), isTrue);
    });

    test('clears it', () {
      setFollowUp('follow-patient', DateTime(2026, 3, 24));
      setFollowUp('follow-patient', null);

      expect(patients.get('follow-patient')!.followUpDay, isNull);
      expect(patients.get('follow-patient')!.toJson().containsKey('followUp'),
          isFalse);
    });

    test('writes the patient panel\'s draft, and does not make it dirty', () {
      final stored = patients.get('follow-patient')!;
      final draft = Patient.fromJson(stored.toJson());
      final panel = RowPanel<Patient>(
        item: draft,
        store: patients,
        title: 'newPatient',
        singularName: 'patient',
        unicodeSymbol: '',
        icon: FluentIcons.medication_admin,
        windows: const <PanelWindow>[],
      );
      PanelsManager.active([panel]);

      setFollowUp('follow-patient', DateTime(2026, 3, 24),
          note: 'Bring the X-ray');

      expect(draft.followUpDay, DateTime(2026, 3, 24),
          reason: 'the draft the panel saves is the same promise');
      expect(draft.followUpNote, 'Bring the X-ray');
      expect(panel.hasPendingEdits, isFalse,
          reason: 'the write the panel did not make is already stored');
      expect(
          patients.get('follow-patient')!.followUpDay, DateTime(2026, 3, 24));
    });

    test('clearing keeps unrelated edits dirty and cannot be undone by Save',
        () async {
      setFollowUp('follow-patient', DateTime(2026, 3, 24));
      final stored = patients.get('follow-patient')!;
      final draft = stored.copy(false);
      final panel = RowPanel<Patient>(
        item: draft,
        store: patients,
        title: 'newPatient',
        singularName: 'patient',
        unicodeSymbol: '',
        icon: FluentIcons.medication_admin,
        windows: const <PanelWindow>[],
      );
      PanelsManager.active([panel]);
      draft.notes = 'Unsaved patient notes';
      draft.teeth['11'] = 'filling';

      setFollowUp('follow-patient', DateTime(2026, 4, 5));
      expect(draft.followUpDay, DateTime(2026, 4, 5));
      expect(panel.hasPendingEdits, isTrue);
      expect(patients.get(draft.id)!.notes, isEmpty);
      expect(patients.get(draft.id)!.teeth, isEmpty);

      setFollowUp('follow-patient', null);
      expect(draft.followUpDay, isNull);
      expect(panel.hasPendingEdits, isTrue);
      expect(draft.notes, 'Unsaved patient notes');
      expect(draft.teeth, {'11': 'filling'});

      draft.notes = stored.notes;
      draft.teeth.clear();
      expect(panel.hasPendingEdits, isFalse,
          reason: 'only the unrelated edits should remain unacknowledged');
      draft.notes = 'Saved patient notes';
      await panel.persist();
      expect(patients.get(draft.id)!.followUpDay, isNull);
      expect(patients.get(draft.id)!.notes, 'Saved patient notes');
    });

    test('cannot set or clear a follow-up without appointment permission', () {
      final day = DateTime(2026, 3, 24);
      setFollowUp('follow-patient', day);
      final revision = followUpRevision();
      login.savedPermissions = Perm.zeroes;

      setFollowUp('follow-patient', DateTime(2026, 4, 5));
      expect(patients.get('follow-patient')!.followUpDay, day);
      setFollowUp('follow-patient', null);
      expect(patients.get('follow-patient')!.followUpDay, day);
      expect(followUpRevision(), revision);
    });

    test('limited appointment permission can set and clear a follow-up', () {
      login.savedPermissions = Perm.zeroes..[Perm.appointments] = 1;
      setFollowUp('follow-patient', DateTime(2026, 3, 24));
      expect(
          patients.get('follow-patient')!.followUpDay, DateTime(2026, 3, 24));

      setFollowUp('follow-patient', null);
      expect(patients.get('follow-patient')!.followUpDay, isNull);
    });

    test('nothing is written for a patient that is not stored', () {
      setFollowUp('ghost-patient', DateTime(2026, 3, 24));
      expect(patients.get('ghost-patient'), isNull);
    });
  });

  group('when a visit is created', () {
    test('on the follow-up day, the promise is kept and cleared', () {
      setFollowUp('follow-patient', DateTime(2026, 1, 15));
      appointments.set(testAppointment(
        id: 'new',
        patientID: 'follow-patient',
        date: DateTime(2026, 1, 15, 9),
      ));

      applyFollowUpsForNewVisit('new');

      expect(patients.get('follow-patient')!.followUpDay, isNull,
          reason: 'the patient came back that day');
    });

    test('after the follow-up day, the promise is kept and cleared', () {
      setFollowUp('follow-patient', DateTime(2026, 1, 15));
      appointments.set(testAppointment(
        id: 'new',
        patientID: 'follow-patient',
        date: DateTime(2026, 1, 20, 9),
      ));

      applyFollowUpsForNewVisit('new');

      expect(patients.get('follow-patient')!.followUpDay, isNull);
    });

    test('before it, the promise still stands', () {
      setFollowUp('follow-patient', DateTime(2026, 2, 1));
      appointments.set(testAppointment(
        id: 'new',
        patientID: 'follow-patient',
        date: DateTime(2026, 1, 10, 9),
      ));

      applyFollowUpsForNewVisit('new');

      expect(patients.get('follow-patient')!.followUpDay, DateTime(2026, 2, 1),
          reason: 'the patient has not reached that day yet');
    });

    test('an archived visit cannot fulfill a follow-up', () {
      final day = DateTime(2026, 2, 1);
      setFollowUp('follow-patient', day);
      appointments.set(testAppointment(
        id: 'archived',
        patientID: 'follow-patient',
        date: day,
      )..archived = true);

      applyFollowUpsForNewVisit('archived');

      expect(patients.get('follow-patient')!.followUpDay, day);
      expect(followUpsOn(day).map((due) => due.patient.id),
          contains('follow-patient'));
    });

    test('never touches another patient\'s promise', () {
      setFollowUp('other-patient', DateTime(2026, 2, 1));
      appointments.set(testAppointment(
        id: 'mine',
        patientID: 'follow-patient',
        date: DateTime(2026, 3, 10),
      ));

      applyFollowUpsForNewVisit('mine');

      expect(patients.get('other-patient')!.followUpDay, DateTime(2026, 2, 1));
    });
  });

  group('the day\'s follow-ups', () {
    test('are the patients whose promise falls on that day', () {
      setFollowUp('follow-patient', DateTime(2026, 2, 1));
      setFollowUp('other-patient', DateTime(2026, 2, 1));
      patients.set(testPatient(id: 'elsewhere', name: 'Elsewhere'));
      setFollowUp('elsewhere', DateTime(2026, 2, 2));

      final due = followUpsOn(DateTime(2026, 2, 1, 15));

      expect(due.map((d) => d.patient.id),
          containsAll(['follow-patient', 'other-patient']));
      expect(due.any((d) => d.patient.id == 'elsewhere'), isFalse);
    });

    test('skip a patient who is already booked that day', () {
      setFollowUp('follow-patient', DateTime(2026, 2, 1));
      appointments.set(testAppointment(
        id: 'booked',
        patientID: 'follow-patient',
        date: DateTime(2026, 2, 1, 9),
      ));

      expect(followUpsOn(DateTime(2026, 2, 1)), isEmpty);
    });

    test('ignore archived patients', () {
      setFollowUp('follow-patient', DateTime(2026, 2, 1));
      patients.archive('follow-patient');

      expect(followUpsOn(DateTime(2026, 2, 1)), isEmpty);
    });
  });

  group('while the feature is turned off', () {
    test('a day has no inbox and a visit rewrites no promise', () {
      setFollowUp('follow-patient', DateTime(2026, 2, 1));
      globalSettings.followUpsEnabled = false;

      expect(followUpsOn(DateTime(2026, 2, 1)), isEmpty,
          reason: 'nothing to offer a clinic that does not chase recalls');
      expect(globalSettings.get('follow_ups_enab').value, '0',
          reason: 'the flag is read from its own setting id');

      appointments.set(testAppointment(
        id: 'off-visit',
        patientID: 'follow-patient',
        date: DateTime(2026, 3, 1),
      ));
      applyFollowUpsForNewVisit('off-visit');

      expect(patients.get('follow-patient')!.followUpDay, DateTime(2026, 2, 1),
          reason: 'a hidden promise is not silently rewritten by a visit');
    });
  });
}
