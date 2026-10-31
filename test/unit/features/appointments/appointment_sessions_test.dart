@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

/// The identity map: one visit id, one session, for the whole app session.
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

  Appointment visit(String id) => testAppointment(
        id: id,
        patientID: 'patient-1',
        date: DateTime(2026, 4, 5, 10),
        preOpNotes: 'stored',
      );

  test('asking twice, even from two records of the same visit, is one session',
      () {
    appointments.set(visit('v1'));
    final fromNotification = appointmentSessions.getOrCreate(visit('v1'));
    final fromCalendar = appointmentSessions
        .getOrCreate(Appointment.fromJson(visit('v1').toJson()));

    expect(identical(fromNotification, fromCalendar), isTrue);
    expect(appointmentSessions.get('v1'), same(fromNotification));
    expect(appointmentSessions.live, hasLength(1));
  });

  test('two visits are two sessions', () {
    appointments.set(visit('v1'));
    appointments.set(visit('v2'));
    final first = appointmentSessions.getOrCreate(visit('v1'));
    final second = appointmentSessions.getOrCreate(visit('v2'));

    expect(identical(first, second), isFalse);
    expect(appointmentSessions.live, hasLength(2));
  });

  test('a new session is published so the panel can hear about it', () async {
    appointments.set(visit('v1'));
    var changes = 0;
    void listener(_) => changes++;
    appointmentSessions.revision.observe(listener);
    addTearDown(() => appointmentSessions.revision.unObserve(listener));

    appointmentSessions.getOrCreate(visit('v1'));
    await Future<void>.delayed(Duration.zero);

    expect(changes, 1);
  });

  test('disposing a session directly publishes its removal once', () async {
    appointments.set(visit('v1'));
    final session = appointmentSessions.getOrCreate(visit('v1'));
    await Future<void>.delayed(Duration.zero);
    var changes = 0;
    void listener(_) => changes++;
    appointmentSessions.revision.observe(listener);
    addTearDown(() => appointmentSessions.revision.unObserve(listener));

    session.dispose();
    session.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(appointmentSessions.get('v1'), isNull);
    expect(changes, 1);
  });

  test('the dirty list names each visit with unsaved work', () {
    appointments.set(visit('v1'));
    appointments.set(visit('v2'));
    final clean = appointmentSessions.getOrCreate(visit('v1'));
    final dirty = appointmentSessions.getOrCreate(visit('v2'));
    dirty.item.preOpNotes = 'typed';

    expect(appointmentSessions.dirty, [dirty]);
    expect(appointmentSessions.dirty, isNot(contains(clean)));
  });

  test('clearing on logout drops every session and its draft', () {
    appointments.set(visit('v1'));
    final session = appointmentSessions.getOrCreate(visit('v1'));
    session.item.preOpNotes = 'typed';

    appointmentSessions.clear();

    expect(appointmentSessions.live, isEmpty);
    expect(session.isDisposed, isTrue);
    expect(appointments.get('v1')!.preOpNotes, 'stored',
        reason: 'logout is not a save');
  });
}
