@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

/// One visit, one draft, one write (plan §2.2, I2 and I3).
///
/// The session is what makes a visit attachable to a patient panel without
/// becoming a second panel: its windows all edit this draft, its Save is this
/// write, and its registry makes a second opener return it rather than build a
/// rival.
void main() {
  late List<Appointment> originalAppointments;

  setUp(() {
    originalAppointments = appointments.docs.values.toList();
    appointments.observableMap.clear();
    appointmentSessions.clear();
  });

  tearDown(() {
    appointmentSessions.clear();
    appointments.observableMap.clear();
    appointments.setAll(originalAppointments);
  });

  Appointment stored({String notes = 'stored note', double price = 100}) =>
      testAppointment(
        id: 'visit-1',
        patientID: 'patient-1',
        date: DateTime(2026, 3, 4, 11, 0),
        preOpNotes: notes,
        price: price,
      );

  for (final archived in [false, true]) {
    test('limited accounts cannot set archive state to $archived', () async {
      final permissions = login.savedPermissions;
      addTearDown(() => login.savedPermissions = permissions);
      login.savedPermissions = List.of(Perm.full)..[Perm.appointments] = 1;
      appointments.set(stored()..archived = !archived);
      final session = appointmentSessions.getOrCreate(stored());
      session.item.preOpNotes = 'unsaved clinical note';

      expect(session.canArchive, isFalse);
      await expectLater(session.setArchived(archived), throwsStateError);
      expect(appointments.get(session.itemId)!.archived, !archived);
      expect(session.item.archived, !archived);
      expect(session.item.preOpNotes, 'unsaved clinical note');
      expect(session.hasPendingEdits, isTrue);
    });
  }

  test('a fresh session starts clean and in step with the store', () {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());

    expect(session.hasPendingEdits, isFalse);
    expect(session.savedId, isNull);
    expect(session.isNew, isFalse);
    expect(session.chart.hasChanges, isFalse);
  });

  test('two openers of one visit get one session', () {
    appointments.set(stored());
    final first = appointmentSessions.getOrCreate(stored());
    final second =
        appointmentSessions.getOrCreate(Appointment.fromJson(stored().toJson()));

    expect(identical(first, second), isTrue);
    expect(appointmentSessions.live, hasLength(1));
  });

  test('save writes the delta against the record as it is stored now', () async {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());
    session.item.preOpNotes = 'typed here';

    // Another writer touches a field this draft never opened: a calendar drag, a
    // sync, another window of the same visit.
    appointments.set(stored()..price = 250);

    await session.save();

    final result = appointments.get('visit-1')!;
    expect(result.preOpNotes, 'typed here', reason: 'the edit is written');
    expect(result.price, 250,
        reason: 'a field the draft never touched is not reverted by its save');
    expect(session.hasPendingEdits, isFalse);
    expect(session.savedId, 'visit-1');
  });

  test('the chart edits the same draft, and a save re-baselines it', () async {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());

    session.chart.teeth['11'] = 'filling';
    session.chart.changed();

    expect(session.hasPendingEdits, isTrue, reason: 'the chart edits the draft');
    expect(session.chart.hasChanges, isTrue);

    await session.save();

    expect(appointments.get('visit-1')!.teeth, {'11': 'filling'});
    expect(session.hasPendingEdits, isFalse);
    expect(session.chart.hasChanges, isFalse);
  });

  test('acknowledging a field does not acknowledge the draft', () async {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());
    session.item
      ..preOpNotes = 'typed here'
      ..imgs = ['photo.jpg'];

    session.markFieldsSaved(['imgs', 'drawings', 'dcmImgs']);

    expect(session.hasPendingEdits, isTrue,
        reason: 'the photos are stored outside the Save; the note is not');
    expect(appointments.get('visit-1')!.preOpNotes, 'stored note');
    expect(session.savedId, isNull);
  });

  test('a field acknowledged away is still reported once it is edited again',
      () async {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());
    session.item.imgs = ['photo.jpg'];
    session.markFieldsSaved(['imgs']);
    expect(session.hasPendingEdits, isFalse);

    session.item.imgs = ['photo.jpg', 'another.jpg'];
    expect(session.hasPendingEdits, isTrue);
  });

  test('the dirty signal follows the draft', () async {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());
    expect(session.hasUnsavedChanges(), isFalse);

    session.item.postOpNotes = 'typed';
    session.refreshDirty();
    expect(session.hasUnsavedChanges(), isTrue);

    await session.save();
    expect(session.hasUnsavedChanges(), isFalse);
  });

  test('dispose finishes the session and leaves the draft unsaved', () {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());
    session.item.preOpNotes = 'typed here';

    appointmentSessions.dispose('visit-1');

    expect(session.isDisposed, isTrue);
    expect(appointmentSessions.isOpen('visit-1'), isFalse);
    expect(appointments.get('visit-1')!.preOpNotes, 'stored note');
  });

  test('the result settles when the session is disposed', () async {
    appointments.set(stored());
    final session = appointmentSessions.getOrCreate(stored());
    var settled = false;
    unawaited(session.result.then((_) => settled = true));

    appointmentSessions.dispose('visit-1');
    await Future<void>.delayed(Duration.zero);

    expect(settled, isTrue);
  });

  test('clearing the registry disposes every session', () {
    appointments.set(stored());
    appointments.set(testAppointment(id: 'visit-2', patientID: 'patient-1'));
    final first = appointmentSessions.getOrCreate(stored());
    final second =
        appointmentSessions.getOrCreate(testAppointment(id: 'visit-2'));

    appointmentSessions.clear();

    expect(first.isDisposed, isTrue);
    expect(second.isDisposed, isTrue);
    expect(appointmentSessions.live, isEmpty);
  });
}
