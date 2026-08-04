@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/model_factory.dart';

/// Verify that [Model.locked] correctly gates model visibility through
/// [Store.present] based on [login.perm] permission levels.
void main() {
  final injectedApptIds = <String>{};
  final injectedPatientIds = <String>{};
  final injectedExpenseIds = <String>{};
  final injectedNoteIds = <String>{};
  late List<int> originalPerms;

  setUp(() {
    originalPerms = login.savedPermissions;
  });

  tearDown(() {
    login.savedPermissions = originalPerms;
    for (final id in injectedApptIds) {
      if (appointments.has(id)) appointments.archive(id);
    }
    for (final id in injectedPatientIds) {
      if (patients.has(id)) patients.archive(id);
    }
    for (final id in injectedExpenseIds) {
      if (expenses.has(id)) expenses.archive(id);
    }
    for (final id in injectedNoteIds) {
      if (notes.has(id)) notes.archive(id);
    }
    injectedApptIds.clear();
    injectedPatientIds.clear();
    injectedExpenseIds.clear();
    injectedNoteIds.clear();
  });

  // ---------------------------------------------------------------------------
  // Appointment locking
  // ---------------------------------------------------------------------------
  group('Appointment.locked — permission-based', () {
    test('locked returns false when perm is full (2)', () {
      login.savedPermissions = Perm.full;
      final appt = testAppointment(id: 'lock-appt-full');
      expect(appt.locked, false);
    });

    test('locked returns true when perm is none (0)', () {
      login.savedPermissions = Perm.zeroes;
      final appt = testAppointment(id: 'lock-appt-none');
      expect(appt.locked, true);
    });

    test('locked returns false when perm is some (1) and user is an operator',
        () {
      login.savedPermissions = [0, 1, 0, 0, 0, 0, 0, 0, 0]; // appointments=1
      login.token = ''; // no PB
      // currentAccountID returns "" when no accounts — appointment
      // operator check uses operatorsIDs.contains(login.currentAccountID)
      final appt = testAppointment(
        id: 'lock-appt-operator',
        operatorsIDs: [''],
      );
      // operatorsIDs contains "" (currentAccountID) → locked = false
      expect(appt.locked, false);
    });

    test(
        'locked returns true when perm is some (1) and user is NOT an operator',
        () {
      login.savedPermissions = [0, 1, 0, 0, 0, 0, 0, 0, 0]; // appointments=1
      final appt = testAppointment(
        id: 'lock-appt-not-op',
        operatorsIDs: ['other-user'],
      );
      // operatorsIDs does not contain "" → locked = true
      expect(appt.locked, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Patient locking — Patient.locked = login.perm(Perm.patients).not(2) &&
  //   (allAppointments.isNotEmpty && no appointment has the current operator)
  // Perm.patients = 0. If perm is full(2), .not(2) is false → not locked.
  // If perm is some(1) or none(0), .not(2) is true → falls through to the
  // appointment-operator check. An empty allAppointments list means the
  // second clause is false → not locked regardless of perm.
  // ---------------------------------------------------------------------------
  group('Patient.locked — permission-based', () {
    test('locked returns false when perm is full (patients=2)', () {
      login.savedPermissions = Perm.full;
      final p = testPatient(id: 'lock-pt-full');
      expect(p.locked, false);
    });

    test('locked returns false when no appointments exist (some perm)', () {
      // patients=1 (not 2) → first clause true, but empty allAppointments
      // → second clause false → locked = false.
      final perms = Perm.zeroes;
      perms[Perm.patients] = 1;
      login.savedPermissions = perms;
      final p = testPatient(id: 'lock-pt-no-appts');
      expect(p.locked, false);
    });

    test('locked returns false when no appointments exist (none perm)', () {
      // patients=0 → first clause true, but empty allAppointments → false.
      login.savedPermissions = Perm.zeroes;
      final p = testPatient(id: 'lock-pt-no-appts-none');
      expect(p.locked, false);
    });

    test('locked returns false when any appointment has current operator', () {
      // patients=2 (full), appointments=2 (full) → first clause false.
      login.savedPermissions = Perm.full;
      final p = testPatient(id: 'lock-pt-with-op');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final appt = testAppointment(
        id: 'lock-pt-appt',
        patientID: p.id,
        operatorsIDs: [''],
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      // currentAccountID returns "" in tests, operatorsIDs contains "" →
      // appointment.operatorsIDs.contains(login.currentAccountID) is true.
      expect(p.locked, false);
    });

    test('locked returns true when personal perm and no operator matches', () {
      // patients=1 (not 2) and the patient's appointment has an operator
      // other than the current account → locked.
      final perms = Perm.full;
      perms[Perm.patients] = 1; // patients=some
      login.savedPermissions = perms;

      final p = testPatient(id: 'lock-pt-stranger-op');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final appt = testAppointment(
        id: 'lock-pt-stranger-appt',
        patientID: p.id,
        operatorsIDs: ['other-doctor-id'],
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      expect(p.locked, true);
    });

    test('locked returns false when one appt matches and another does not', () {
      // patients=1 (not full). The first appointment is owned by another
      // doctor, the second by the current account. Patient.locked should
      // be false because at least one appointment has the current operator.
      final perms = Perm.full;
      perms[Perm.patients] = 1;
      login.savedPermissions = perms;

      final p = testPatient(id: 'lock-pt-mixed-op');
      patients.set(p);
      injectedPatientIds.add(p.id);

      appointments.set(testAppointment(
        id: 'lock-pt-mixed-appt-other',
        patientID: p.id,
        operatorsIDs: ['someone-else'],
      ));
      injectedApptIds.add('lock-pt-mixed-appt-other');

      appointments.set(testAppointment(
        id: 'lock-pt-mixed-appt-mine',
        patientID: p.id,
        operatorsIDs: [''],
      ));
      injectedApptIds.add('lock-pt-mixed-appt-mine');

      expect(p.locked, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Expense locking — Expense.locked = login.perm(Perm.expenses).none
  // Perm.expenses = 4. So only the none(0)/some(>0) distinction matters.
  // ---------------------------------------------------------------------------
  group('Expense.locked — permission-based', () {
    test('locked returns false when expenses perm is full (2)', () {
      login.savedPermissions = Perm.full;
      final e = testExpense(id: 'lock-exp-full');
      expect(e.locked, false);
    });

    test('locked returns true when expenses perm is none (0)', () {
      login.savedPermissions = Perm.zeroes;
      final e = testExpense(id: 'lock-exp-none');
      expect(e.locked, true);
    });

    test('locked returns false when expenses perm is some (1)', () {
      // Perm.expenses = 4
      final perms = Perm.zeroes;
      perms[Perm.expenses] = 1;
      login.savedPermissions = perms;
      final e = testExpense(id: 'lock-exp-some');
      // Expense.locked = login.perm(Perm.expenses).none
      // .none means == 0 → 1 != 0 → locked = false
      expect(e.locked, false);
    });

    test('locked is independent of archived flag', () {
      login.savedPermissions = Perm.zeroes;
      final e = testExpense(id: 'lock-exp-archived', archived: true);
      // archived=true doesn't change locked (locked depends only on perm)
      expect(e.locked, true);
    });

    test('locked holds for supplier and order variants', () {
      login.savedPermissions = Perm.zeroes;
      final supplier = testExpense(
        id: 'lock-exp-supplier',
        isSupplier: true,
        supplierName: 'Acme',
      );
      final order = testExpense(id: 'lock-exp-order', isSupplier: false);
      expect(supplier.locked, true);
      expect(order.locked, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Note locking — Note.locked = login.perm(Perm.notes).none &&
  //   isColumn == false && login.currentAccountID != createdBy &&
  //   login.currentAccountID != assignedTo
  // Perm.notes = 7. Column notes and notes authored by/assigned to the
  // current user are always unlocked.
  // ---------------------------------------------------------------------------
  group('Note.locked — permission-based', () {
    test('locked returns false when notes perm is full (2)', () {
      login.savedPermissions = Perm.full;
      final n = testNote(id: 'lock-note-full');
      expect(n.locked, false);
    });

    test('locked returns false when note is a column (always unlocked)', () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(id: 'lock-col', isColumn: true);
      expect(n.locked, false);
    });

    test('locked returns false when current user is the creator', () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'lock-note-creator',
        createdBy: '', // currentAccountID returns "" in test
      );
      expect(n.locked, false);
    });

    test('locked returns false when current user is the assignee', () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'lock-note-assignee',
        assignedTo: '', // currentAccountID returns "" in test
      );
      expect(n.locked, false);
    });

    test('locked returns true when no perm, not creator, not assignee', () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'lock-note-stranger',
        createdBy: 'someone-else',
        assignedTo: 'another-person',
      );
      expect(n.locked, true);
    });

    test('locked returns false with notes perm = some(1) regardless of owner',
        () {
      final perms = Perm.zeroes;
      perms[Perm.notes] = 1;
      login.savedPermissions = perms;
      final n = testNote(
        id: 'lock-note-some-perm-stranger',
        createdBy: 'someone-else',
        assignedTo: 'another-person',
      );
      // some → .none is false → whole expression is false → not locked.
      expect(n.locked, false);
    });

    test('locked returns false when creator matches even if assignee differs',
        () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'lock-note-creator-match',
        createdBy: '', // matches currentAccountID
        assignedTo: 'someone-else',
      );
      // currentAccountID == createdBy → expression false → not locked.
      expect(n.locked, false);
    });

    test('locked is false for column even when creator & assignee are others',
        () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'lock-col-strangers',
        isColumn: true,
        createdBy: 'other',
        assignedTo: 'other2',
      );
      // isColumn short-circuits → locked = false.
      expect(n.locked, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Store.present filtering with locking
  // ---------------------------------------------------------------------------
  group('Store.present — filters locked items', () {
    test('present includes unlocked items when permission is full', () {
      login.savedPermissions = Perm.full;

      final p = testPatient(id: 'present-pt');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final appt = testAppointment(id: 'present-appt', patientID: p.id);
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      expect(appointments.present.containsKey(appt.id), isTrue);
    });

    test('present excludes items when locked (no permission)', () {
      login.savedPermissions = Perm.zeroes;

      final p = testPatient(id: 'present-locked-pt');
      patients.set(p);
      injectedPatientIds.add(p.id);

      final appt = testAppointment(
        id: 'present-locked-appt',
        patientID: p.id,
        operatorsIDs: ['other-op'],
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      // With zeroes, Appointment.locked is true → present excludes it.
      expect(appointments.present.containsKey(appt.id), isFalse);
    });

    test('present excludes archived items even when unlocked', () {
      login.savedPermissions = Perm.full;
      final appt = testAppointment(
        id: 'present-archived',
        archived: true,
      );
      appointments.set(appt);
      injectedApptIds.add(appt.id);

      // archived=true → filtered out by present.
      expect(appointments.present.containsKey(appt.id), isFalse);
      // But still present in docs.
      expect(appointments.docs.containsKey(appt.id), isTrue);
    });

    test('present excludes locked expenses (perm=none)', () {
      login.savedPermissions = Perm.zeroes;
      final e = testExpense(id: 'present-locked-exp');
      expenses.set(e);
      injectedExpenseIds.add(e.id);

      // Expense.locked = perm.expenses.none → true → excluded.
      expect(expenses.present.containsKey(e.id), isFalse);
      expect(expenses.docs.containsKey(e.id), isTrue);
    });

    test('present includes unlocked expenses (perm=full)', () {
      login.savedPermissions = Perm.full;
      final e = testExpense(id: 'present-unlocked-exp');
      expenses.set(e);
      injectedExpenseIds.add(e.id);

      expect(expenses.present.containsKey(e.id), isTrue);
    });

    test('present excludes locked notes (perm=none, stranger)', () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'present-locked-note',
        createdBy: 'someone-else',
        assignedTo: 'another-person',
      );
      notes.set(n);
      injectedNoteIds.add(n.id);

      // Note.locked = perm.notes.none && not column && not creator/assignee
      expect(notes.present.containsKey(n.id), isFalse);
      expect(notes.docs.containsKey(n.id), isTrue);
    });

    test('present includes unlocked notes (creator match)', () {
      login.savedPermissions = Perm.zeroes;
      final n = testNote(
        id: 'present-unlocked-note',
        createdBy: '', // matches currentAccountID
      );
      notes.set(n);
      injectedNoteIds.add(n.id);

      // creator matches → Note.locked = false → included.
      expect(notes.present.containsKey(n.id), isTrue);
    });
  });
}
