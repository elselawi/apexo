import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/utils/demo_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  group('demoAccounts', () {
    test('returns correct number of accounts', () {
      final accounts = demoAccounts(5);
      expect(accounts.length, 5);
    });

    test('each account is a non-null RecordModel', () {
      final accounts = demoAccounts(3);
      for (final a in accounts) {
        expect(a, isA<RecordModel>());
        expect(a.id, isNotEmpty);
      }
    });

    test('first account has id set', () {
      final accounts = demoAccounts(3);
      expect(accounts.first.id, isNotEmpty);
    });

    test('accounts have unique IDs', () {
      final accounts = demoAccounts(10);
      final ids = accounts.map((a) => a.id).toSet();
      expect(ids.length, 10);
    });

    test('zero length returns no accounts', () {
      expect(demoAccounts(0), isEmpty);
    });
  });

  group('demoPatients', () {
    test('returns correct number of patients', () {
      final patients = demoPatients(5);
      expect(patients.length, 5);
    });

    test('each patient is a Patient', () {
      final patients = demoPatients(3);
      for (final p in patients) {
        expect(p, isA<Patient>());
        expect(p.title, isNotEmpty);
        expect(p.id.length, 15);
      }
    });

    test('patients have unique IDs', () {
      final patients = demoPatients(20);
      final ids = patients.map((p) => p.id).toSet();
      expect(ids.length, 20);
    });

    test('phones start with "+"', () {
      final patients = demoPatients(10);
      for (final p in patients) {
        expect(p.phone, anyOf(isEmpty, startsWith('+')));
      }
    });

    test('birth years and IDs follow the expected domain ranges', () {
      final currentYear = DateTime.now().year;
      final patients = demoPatients(100);

      expect(patients.map((patient) => patient.id).toSet().length, 100);
      for (final patient in patients) {
        expect(
            patient.birth, inInclusiveRange(currentYear - 59, currentYear - 5));
      }
    });
  });

  group('demoAppointments', () {
    test('returns correct number of appointments', () {
      final appts = demoAppointments(5);
      expect(appts.length, 5);
    });

    test('each appointment is an Appointment', () {
      final appts = demoAppointments(3);
      for (final a in appts) {
        expect(a, isA<Appointment>());
        expect(a.id.length, 15);
      }
    });

    test('appointments reference generated patients', () {
      final patients = demoPatients(10);
      final appts = demoAppointments(5);
      for (final a in appts) {
        expect(patients.map((patient) => patient.id), contains(a.patientID));
        if (a.date.isAfter(DateTime.now())) {
          expect(a.isDone, isFalse);
          // The model normalizes the generator's null payment to zero.
          expect(a.paid, 0);
        }
      }
    });

    test('zero appointments needs no patient dependency', () {
      demoPatients(0);
      expect(demoAppointments(0), isEmpty);
    });
  });

  group('demoExpenses', () {
    test('returns at least the number of suppliers plus requested', () {
      final result = demoExpenses(5);
      // Returns _demoSuppliers() + 5 expenses
      expect(result.length, greaterThanOrEqualTo(5));
    });

    test('includes supplier entries with isSupplier: true', () {
      final result = demoExpenses(3);
      final suppliers = result.where((e) => e.isSupplier).toList();
      expect(suppliers, isNotEmpty);
      for (final s in suppliers) {
        expect(s.isSupplier, isTrue);
        expect(s.supplierName, isNotEmpty);
      }
    });

    test('includes order entries with isSupplier: false', () {
      final result = demoExpenses(3);
      final orders = result.where((e) => !e.isSupplier).toList();
      expect(orders, isNotEmpty);
    });

    test('orders reference one of the returned supplier IDs', () {
      final result = demoExpenses(20);
      final supplierIds = result
          .where((expense) => expense.isSupplier)
          .map((expense) => expense.id)
          .toSet();
      final orders = result.whereType<Expense>().where((e) => !e.isSupplier);

      for (final order in orders) {
        expect(supplierIds, contains(order.supplierId));
        expect(order.items, isNotEmpty);
      }
    });
  });

  group('demoNotes', () {
    test('returns at least 3 columns + requested notes', () {
      final result = demoNotes(5);
      // 3 columns + 5 notes
      expect(result.length, 8);
    });

    test('first 3 entries are columns with isColumn: true', () {
      final result = demoNotes(3);
      final columns = result.where((n) => n.isColumn).toList();
      expect(columns.length, 3);
      for (final c in columns) {
        expect(c.isColumn, isTrue);
        expect(c.columnName, isNotEmpty);
      }
    });

    test('non-column notes have a columnID', () {
      final result = demoNotes(5);
      final notes = result.where((n) => !n.isColumn).toList();
      expect(notes.length, 5);
      for (final n in notes) {
        expect(n.columnID, isNotEmpty);
      }
    });

    test('each non-column note references a returned column', () {
      final result = demoNotes(20);
      final columnIds = result.where((note) => note.isColumn).map((n) => n.id);

      for (final note in result.whereType<Note>().where((n) => !n.isColumn)) {
        expect(columnIds, contains(note.columnID));
        expect(note.dueDate.isAfter(note.date), isTrue);
      }
    });

    test('notes have unique IDs', () {
      final result = demoNotes(10);
      final ids = result.map((n) => n.id).toSet();
      expect(ids.length, result.length);
    });

    test('column order is consecutive (0, 1, 2)', () {
      final result = demoNotes(0);
      final columns = result.where((n) => n.isColumn).toList();
      expect(columns[0].order, 0);
      expect(columns[1].order, 1);
      expect(columns[2].order, 2);
    });
  });

  group('demo generator — large counts', () {
    test('demoPatients(100) does not crash', () {
      final patients = demoPatients(100);
      expect(patients.length, 100);
    });

    test('demoAppointments(500) does not crash', () {
      demoPatients(20);
      final appts = demoAppointments(500);
      expect(appts.length, 500);
    });
  });
}
