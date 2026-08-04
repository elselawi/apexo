@Tags(['serial'])
library;

import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Appointments store', () {
    setUp(() {
      appointments.observableMap.clear();
      login.savedPermissions = Perm.full;
      appointments.filterByOperatorID('');
    });

    test('singleton is Appointments instance', () {
      expect(appointments, isA<Appointments>());
    });

    test('observableMap is ObservableDict', () {
      expect(appointments.observableMap, isA<ObservableDict<Appointment>>());
    });

    test('observableMap values returns list', () {
      expect(appointments.observableMap.values, isA<List<Appointment>>());
    });

    test('filterByOperatorID defaults to empty string', () {
      expect(appointments.filterByOperatorID(), isEmpty);
    });

    test('filterByOperatorID is ObservableState', () {
      expect(appointments.filterByOperatorID, isA<ObservableState<String>>());
    });

    test('filtered returns present when no filter', () {
      // Without init, present should be empty map
      expect(appointments.filtered, isA<Map<String, Appointment>>());
    });

    test('present returns a map', () {
      expect(appointments.present, isA<Map<String, Appointment>>());
    });

    test('todayAppointments returns a list', () {
      expect(appointments.todayAppointments, isA<List<Appointment>>());
    });

    test('thisMonthAppointments returns a list', () {
      expect(appointments.thisMonthAppointments, isA<List<Appointment>>());
    });

    test('allPrescriptions returns a list', () {
      expect(appointments.allPrescriptions, isA<List<String>>());
    });

    test('byPatient returns a map', () {
      expect(appointments.byPatient,
          isA<Map<String, Map<String, List<Appointment>>>>());
    });

    test('filterByOperatorID can be set and observed', () {
      appointments.filterByOperatorID('test-op');
      expect(appointments.filterByOperatorID(), 'test-op');
      appointments.filterByOperatorID('');
      expect(appointments.filterByOperatorID(), isEmpty);
    });

    test('present excludes archived appointments but keeps active ones', () {
      final active = testAppointment(id: 'active', archived: false);
      final archived = testAppointment(id: 'archived', archived: true);
      appointments.setAll([active, archived]);

      expect(appointments.present.keys, {'active'});
      expect(appointments.docs.keys, {'active', 'archived'});
    });

    test('filtered selects only appointments assigned to the operator', () {
      final mine = testAppointment(
        id: 'mine',
        operatorsIDs: ['op-1'],
      );
      final other = testAppointment(
        id: 'other',
        operatorsIDs: ['op-2'],
      );
      appointments.setAll([mine, other]);
      appointments.filterByOperatorID('op-1');

      expect(appointments.filtered.keys, {'mine'});
    });

    test('derived patient buckets classify upcoming, done, and past', () {
      final now = DateTime.now();
      final upcoming = testAppointment(
        id: 'upcoming',
        patientID: 'patient',
        date: now.add(const Duration(days: 1)),
      );
      final done = testAppointment(
        id: 'done',
        patientID: 'patient',
        date: now.subtract(const Duration(days: 2)),
        isDone: true,
      );
      final past = testAppointment(
        id: 'past',
        patientID: 'patient',
        date: now.subtract(const Duration(days: 3)),
      );
      appointments.setAll([upcoming, done, past]);

      final buckets = appointments.byPatient['patient']!;
      expect(buckets['all']!.map((x) => x.id),
          containsAll(['upcoming', 'done', 'past']));
      expect(buckets['upcoming']!.map((x) => x.id), ['upcoming']);
      expect(buckets['done']!.map((x) => x.id), ['done']);
      expect(buckets['past']!.map((x) => x.id), containsAll(['done', 'past']));
    });

    test('today/month/labs and prescriptions are derived exactly', () {
      final now = DateTime.now();
      appointments.setAll([
        testAppointment(
          id: 'today',
          date: now,
          hasLabwork: true,
          labName: 'Lab A',
          prescriptions: ['drug-a', 'drug-b'],
        ),
        testAppointment(
          id: 'month',
          date: DateTime(now.year, now.month, 15),
          prescriptions: ['drug-b', 'drug-c'],
        ),
        testAppointment(
          id: 'other-month',
          date: DateTime(now.year, now.month == 12 ? 1 : now.month + 1, 1),
        ),
      ]);

      expect(
          appointments.todayAppointments.map((x) => x.id), contains('today'));
      expect(appointments.thisMonthAppointments.map((x) => x.id),
          containsAll(['today', 'month']));
      expect(appointments.labs, {'Lab A'});
      expect(appointments.allPrescriptions.toSet(),
          {'drug-a', 'drug-b', 'drug-c'});
    });

    test('cache invalidation includes prescriptions and labs', () {
      appointments.set(testAppointment(id: 'first', prescriptions: ['old']));
      expect(appointments.allPrescriptions, ['old']);
      expect(appointments.labs, isEmpty);

      appointments.set(testAppointment(
        id: 'second',
        prescriptions: ['new'],
        hasLabwork: true,
        labName: 'New Lab',
      ));

      expect(appointments.allPrescriptions.toSet(), {'old', 'new'});
      // `labs` is populated while the appointment cache is rebuilt.
      appointments.todayAppointments;
      expect(appointments.labs, {'New Lab'});
    });
  });
}
