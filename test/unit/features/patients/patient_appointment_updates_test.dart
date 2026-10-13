@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

void main() {
  setUp(() {
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
  });

  tearDown(() => appointments.observableMap.clear());

  PatientTableLabel label(Patient patient, String key) =>
      patient.tableLabels.firstWhere((label) => label.title == txt(key));

  test('saved appointment refreshes patient and draft labels immediately', () {
    final patient = testPatient(id: 'patient');
    final draft = patient.copy(false);
    final appointment = testAppointment(
      id: 'appointment',
      patientID: patient.id,
      date: DateTime.now().subtract(const Duration(days: 1)),
      isDone: true,
      price: 100,
      paid: 10,
    );
    appointments.set(appointment);
    for (final model in [patient, draft]) {
      expect(label(model, 'paid').value, 10);
      expect(model.searchString, contains(txt('underpaid').toLowerCase()));
    }

    appointments.set(appointment.copy(false)..paid = 100);

    for (final model in [patient, draft]) {
      expect(model.paymentsMade, 100);
      expect(label(model, 'paid').value, 100);
      expect(model.searchString, contains(txt('fullyPaid').toLowerCase()));
      expect(
          model.searchString, isNot(contains(txt('underpaid').toLowerCase())));
    }
  });

  test('reassignment invalidates labels for both patients', () {
    final first = testPatient(id: 'first');
    final second = testPatient(id: 'second');
    final appointment = testAppointment(
      id: 'appointment',
      patientID: first.id,
      date: DateTime.now().subtract(const Duration(days: 1)),
      isDone: true,
      paid: 25,
    );
    appointments.set(appointment);
    expect(label(first, 'appointments').value, 1);
    expect(label(second, 'appointments').value, 0);

    appointments.set(appointment.copy(false)..patientID = second.id);

    expect(label(first, 'appointments').value, 0);
    expect(label(first, 'paid').value, 0);
    expect(label(second, 'appointments').value, 1);
    expect(label(second, 'paid').value, 25);
  });

  test('bulk, archive, restore and silent reload update patient totals', () {
    final patient = testPatient(id: 'patient');
    final appointment = testAppointment(
      id: 'appointment',
      patientID: patient.id,
      date: DateTime.now().subtract(const Duration(days: 1)),
      isDone: true,
      paid: 20,
    );
    appointments.set(appointment);
    expect(label(patient, 'paid').value, 20);

    appointments.setAll([appointment.copy(false)..paid = 50]);
    expect(label(patient, 'paid').value, 50);

    appointments.archive(appointment.id);
    expect(label(patient, 'paid').value, 0);
    appointments.unarchive(appointment.id);
    expect(label(patient, 'paid').value, 50);

    final reloaded = appointment.copy(false)..paid = 80;
    appointments.observableMap.silently(() {
      appointments.observableMap.clear();
      appointments.observableMap.setAllWithJson(
        {reloaded.id: reloaded},
        {reloaded.id: reloaded.toJson()},
      );
    });
    expect(label(patient, 'paid').value, 80);
    expect(patient.paymentsMade, 80);
  });
}
