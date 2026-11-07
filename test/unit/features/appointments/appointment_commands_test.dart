@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

/// Every local visit change goes through `appointmentCommand` so it reaches
/// both the open draft and the store.
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

  Appointment visit() => testAppointment(
        id: 'command-visit',
        patientID: 'command-patient',
        date: DateTime(2026, 5, 6, 9, 0),
        duration: 30,
      );

  test('with no draft open, a change is written to the store at once', () {
    appointments.set(visit());

    appointmentCommand(
        'command-visit', (draft) => draft.date = DateTime(2026, 5, 7, 14));

    final stored = appointments.get('command-visit')!;
    expect(stored.date, DateTime(2026, 5, 7, 14));
    expect(appointmentSessions.isOpen('command-visit'), isFalse,
        reason: 'a command is not an opener');
  });

  test('with a draft open, a drag edits the draft and is stored at once', () {
    appointments.set(visit());
    final session = appointmentSessions.getOrCreate(visit());

    appointmentCommand(
        'command-visit', (draft) => draft.date = DateTime(2026, 5, 7, 14));

    expect(session.item.date, DateTime(2026, 5, 7, 14),
        reason: 'the drag landed in the draft the user is looking at');
    expect(session.hasPendingEdits, isFalse,
        reason: 'the store already holds it: the visit did not become dirty');
    expect(appointments.get('command-visit')!.date, DateTime(2026, 5, 7, 14),
        reason: 'the calendar, the list and the band all read the store');
  });

  test('a command stores only what it changed, and leaves the draft\'s work',
      () async {
    appointments.set(visit());
    final session = appointmentSessions.getOrCreate(visit());

    // The user types into the visit's own form; the form's work is unsaved.
    session.item.preOpNotes = 'crown prepared';
    session.refreshDirty();
    expect(session.hasPendingEdits, isTrue);

    // A checkbox outside the visit's windows completes it.
    appointmentCommand('command-visit', (draft) => draft.isDone = true);

    expect(appointments.get('command-visit')!.isDone, isTrue);
    expect(appointments.get('command-visit')!.preOpNotes, isEmpty,
        reason: 'a tick does not store the note beside it');
    expect(session.hasPendingEdits, isTrue,
        reason: 'the note is still the user\'s, unsaved');
    expect(session.item.isDone, isTrue,
        reason: 'the draft agrees with the store');

    // The visit's own Save still writes the note, and nothing else.
    await session.save();
    expect(appointments.get('command-visit')!.preOpNotes, 'crown prepared');
    expect(appointments.get('command-visit')!.isDone, isTrue);
    expect(session.hasPendingEdits, isFalse);
  });

  test('the drag and the form are one draft, so one Save writes both',
      () async {
    appointments.set(visit());
    final session = appointmentSessions.getOrCreate(visit());

    appointmentCommand(
        'command-visit', (draft) => draft.date = DateTime(2026, 5, 7, 14));
    session.item.preOpNotes = 'dragged into the afternoon';

    await session.save();

    final stored = appointments.get('command-visit')!;
    expect(stored.date, DateTime(2026, 5, 7, 14));
    expect(stored.preOpNotes, 'dragged into the afternoon');
    expect(stored.duration, 30, reason: 'nothing else was written');
  });

  test('a command for a visit that is not stored is a programming error', () {
    expect(
      () => appointmentCommand('missing', (draft) => draft.isDone = true),
      throwsStateError,
    );
  });

  test('a disposed session is not a draft: the write goes to the store', () {
    appointments.set(visit());
    final session = appointmentSessions.getOrCreate(visit());
    session.item.isDone = true;
    appointmentSessions.dispose('command-visit');

    appointmentCommand('command-visit', (draft) => draft.isDone = false);

    expect(appointments.get('command-visit')!.isDone, isFalse,
        reason: 'the finished session cannot hold the change any more');
    expect(session.isDisposed, isTrue);
  });
}
