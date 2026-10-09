import 'package:apexo/app/panels/row_panel.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email permits empty and ordinary addresses, rejects malformed values',
      () {
    for (final email in [
      '',
      'person@example.com',
      'first.last+tag@clinic.co.uk'
    ]) {
      expect(Patient.isValidEmail(email), isTrue, reason: email);
    }
    for (final email in [
      'no-at-sign',
      'a@@example.com',
      'a@',
      '@example.com',
      'a@localhost',
      '.a@example.com',
      'a..b@example.com',
      'a@-bad.com',
      'a b@example.com',
      'a<b>@example.com',
      'a:b@example.com',
      'a,b@example.com',
      'a"b@example.com'
    ]) {
      expect(Patient.isValidEmail(email), isFalse, reason: email);
    }
  });

  test('invalid patient cannot be persisted and keeps its draft dirty',
      () async {
    final store = Store<Patient>(modeling: Patient.fromJson);
    final patient = Patient.fromJson({'title': 'Test Patient'});
    final panel = RowPanel<Patient>(
      item: patient,
      store: store,
      title: 'patient',
      tabs: const [],
      icon: FluentIcons.contact,
      singularName: 'patient',
      unicodeSymbol: '',
      validate: () =>
          Patient.isValidEmail(patient.email) ? null : 'invalid email',
    );
    patient.email = 'invalid';
    await expectLater(panel.persist(), throwsFormatException);
    expect(store.get(patient.id), isNull);
    expect(panel.hasPendingEdits, isTrue);
    await expectLater(panel.setArchived(true), throwsFormatException);
    expect(patient.archived, isNot(isTrue));
    expect(store.get(patient.id), isNull);
    patient.email = 'person@example.com';
    await panel.persist();
    expect(store.get(patient.id)!.email, 'person@example.com');
    expect(panel.hasPendingEdits, isFalse);
  });

  test('immediately saved fields preserve unrelated pending edits', () {
    final store = Store<Patient>(modeling: Patient.fromJson);
    final patient = Patient.fromJson({'title': 'Before'});
    store.set(patient.copy(false));
    final panel = RowPanel<Patient>(
      item: patient,
      store: store,
      title: 'patient',
      tabs: const [],
      icon: FluentIcons.contact,
      singularName: 'patient',
      unicodeSymbol: '',
    );
    patient.portalAccessRevoked = true;
    panel.markFieldsSaved(['portalAccessRevoked']);
    expect(panel.hasPendingEdits, isFalse);
    patient.title = 'Edited';
    patient.portalAccessRevoked = false;
    panel.markFieldsSaved(['portalAccessRevoked']);
    expect(panel.hasPendingEdits, isTrue);
    patient.title = 'Before';
    expect(panel.hasPendingEdits, isFalse);
  });

  test('archiving persists pending edits and clears dirty state', () async {
    final store = Store<Patient>(modeling: Patient.fromJson);
    final patient = Patient.fromJson({'title': 'Before'});
    store.set(patient.copy(false));
    final panel = RowPanel<Patient>(
      item: patient,
      store: store,
      title: 'patient',
      tabs: const [],
      icon: FluentIcons.contact,
      singularName: 'patient',
      unicodeSymbol: '',
    );
    patient.title = 'Edited';
    await panel.setArchived(true);
    expect(store.get(patient.id)!.title, 'Edited');
    expect(store.get(patient.id)!.archived, isTrue);
    expect(panel.hasPendingEdits, isFalse);
    await panel.setArchived(false);
    expect(store.get(patient.id)!.archived, isFalse);
    expect(panel.hasPendingEdits, isFalse);
  });

  test(
      'portal revocation survives serialization without changing legacy defaults',
      () {
    final patient =
        Patient.fromJson({'title': 'Test', 'portalAccessRevoked': true});
    expect(patient.copy(false).portalAccessRevoked, isTrue);
    expect(Patient.fromJson({}).portalAccessRevoked, isFalse);
    expect(Patient.fromJson({}).toJson().containsKey('portalAccessRevoked'),
        isFalse);
    expect(publicCollectionImport.viewQuery, contains('portalAccessRevoked'));
    expect(schemaVersion, greaterThan(1));
  });
}
