@Tags(['serial'])
library;

import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  final injectedApptIds = <String>{};
  final injectedPatientIds = <String>{};
  late List<int> originalPerms;

  void cleanUp() {
    for (final id in injectedApptIds) {
      if (appointments.has(id)) appointments.archive(id);
    }
    for (final id in injectedPatientIds) {
      if (patients.has(id)) patients.archive(id);
    }
    injectedApptIds.clear();
    injectedPatientIds.clear();
  }

  setUpAll(() {
    // Grant full permissions so Model.locked returns false
    // (otherwise present/filtered getters exclude everything).
    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });

  tearDownAll(() {
    login.savedPermissions = originalPerms;
  });

  setUp(() {
    appointments.nullifyAppointmentsCache(null);
    // Other test files may have changed savedPermissions; ensure full perms
    // so Model.locked returns false (items show up in present).
    login.savedPermissions = Perm.full;
  });

  tearDown(cleanUp);

  group('Dashboard controller — singleton', () {
    test('dashboardCtrl singleton exists', () {
      expect(dashboardCtrl, isNotNull);
    });

    test('thisMonthAppointments delegates to appointments store', () {
      final expected = appointments.thisMonthAppointments;
      expect(dashboardCtrl.thisMonthAppointments, expected);
    });

    test('todayAppointments filters archived out', () {
      final result = dashboardCtrl.todayAppointments;
      expect(result, isA<List<Appointment>>());
      for (final a in result) {
        expect(a.archived, isNot(true));
      }
    });

    test('currentOpenTab is ObservableState defaulting to 0', () {
      expect(dashboardCtrl.currentOpenTab, isA<ObservableState<int>>());
      expect(dashboardCtrl.currentOpenTab(), 0);
    });

    test('currentOpenTab is settable', () {
      final prev = dashboardCtrl.currentOpenTab();
      dashboardCtrl.currentOpenTab(2);
      expect(dashboardCtrl.currentOpenTab(), 2);
      dashboardCtrl.currentOpenTab(prev);
    });
  });

  group('Dashboard controller — payments today', () {
    test('paymentsToday equals sum of paid for today appointments', () {
      final sum = appointments.todayAppointments
          .fold<double>(0.0, (sum, a) => sum + a.paid);
      expect(dashboardCtrl.paymentsToday, sum);
    });

    test('paymentsToday reflects an injected appointment', () {
      final p = testPatient(id: 'test-dash-paid');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final appt = testAppointment(
        id: 'appt-dash-paid',
        patientID: p.id,
        date: DateTime.now(),
        price: 200.0,
        paid: 75.0,
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      expect(
          dashboardCtrl.todayAppointments.any((a) => a.id == appt.id), isTrue);
      final expected = dashboardCtrl.todayAppointments
          .fold<double>(0.0, (sum, a) => sum + a.paid);
      expect(dashboardCtrl.paymentsToday, expected);
      expect(expected, greaterThanOrEqualTo(75.0));
    });

    test('paymentsToday excludes archived appointments', () {
      final archived = testAppointment(
        id: 'appt-dash-archived-payment',
        date: DateTime.now(),
        paid: 999,
        archived: true,
      );
      appointments.set(archived);
      injectedApptIds.add(archived.id);

      expect(dashboardCtrl.todayAppointments.any((a) => a.id == archived.id),
          isFalse);
      expect(dashboardCtrl.paymentsToday, isNot(999.0));
    });
  });

  group('Dashboard controller — new patients today', () {
    test('newPatientsToday includes injected first-time patient for today', () {
      final p = testPatient(id: 'test-dash-new');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final appt = testAppointment(
        id: 'appt-dash-new',
        patientID: p.id,
        date: DateTime.now(),
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      final result = dashboardCtrl.newPatientsToday;
      expect(result, isA<List<Patient>>());
      expect(result.any((pat) => pat.id == p.id), isTrue);
    });

    test('newPatientsToday returns a list type', () {
      final result = dashboardCtrl.newPatientsToday;
      expect(result, isA<List<Patient>>());
    });
  });

  group('Dashboard controller — archived filtering', () {
    test('todayAppointments excludes archived appointments', () {
      final p = testPatient(id: 'test-dash-arch');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final archivedAppt = testAppointment(
        id: 'appt-dash-arch',
        patientID: p.id,
        date: DateTime.now(),
        archived: true,
      );
      appointments.set(archivedAppt);
      injectedApptIds.add(archivedAppt.id);

      expect(
          dashboardCtrl.todayAppointments.any((a) => a.id == archivedAppt.id),
          isFalse);
    });

    test('todayAppointments is sorted and excludes missing-patient concerns',
        () {
      final later = testAppointment(
        id: 'dash-later',
        date: DateTime.now().add(const Duration(hours: 1)),
      );
      final earlier = testAppointment(
        id: 'dash-earlier',
        date: DateTime.now().subtract(const Duration(hours: 1)),
      );
      appointments.setAll([later, earlier]);
      injectedApptIds.addAll([later.id, earlier.id]);

      final ids = dashboardCtrl.todayAppointments.map((a) => a.id).toList();
      expect(ids.indexOf(earlier.id), lessThan(ids.indexOf(later.id)));
      expect(dashboardCtrl.newPatientsToday, isNot(contains(isNull)));
    });
  });
}
