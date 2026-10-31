@Tags(['serial'])
library;

import 'package:apexo/features/patients/new_patient_dialog.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_screen.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

void main() {
  late List<Patient> previousPatients;

  setUp(() {
    previousPatients = patients.docs.values.toList();
    patients.observableMap.clear();
  });

  tearDown(() {
    patients.observableMap.clear();
    patients.setAll(previousPatients);
  });

  /// The sheet as the app shows it: asked for by a control, closed by its own
  /// Save.
  Future<void> openSheet(
    WidgetTester tester, {
    required void Function(Patient) onSave,
  }) async {
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          key: const Key('openPatientSheet'),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => NewPatientDialog(onSave: onSave),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openPatientSheet')));
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(WK.btnCreatePatient));

  testWidgets('the sheet waits for a name before it can save', (tester) async {
    await openSheet(tester, onSave: (_) {});

    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(WK.fieldNewPatientName), 'Ada');
    await tester.pump();

    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('a name and a phone become the patient', (tester) async {
    Patient? created;
    await openSheet(tester, onSave: (patient) => created = patient);

    await tester.enterText(find.byKey(WK.fieldNewPatientName), '  Ada Lovelace ');
    await tester.enterText(find.byKey(WK.fieldNewPatientPhone), '+964 770 123 4567');
    await tester.pump();
    await tester.tap(find.byKey(WK.btnCreatePatient));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.title, 'Ada Lovelace');
    expect(created!.phonesString, isNotEmpty);
    // The sheet is gone: nothing is left on screen to be filled in later.
    expect(find.byKey(WK.fieldNewPatientName), findsNothing);
  });

  testWidgets('without a phone the patient is still created', (tester) async {
    Patient? created;
    await openSheet(tester, onSave: (patient) => created = patient);

    await tester.enterText(find.byKey(WK.fieldNewPatientName), 'Grace');
    await tester.pump();
    await tester.tap(find.byKey(WK.btnCreatePatient));
    await tester.pumpAndSettle();

    expect(created!.title, 'Grace');
    expect(created!.phone, isEmpty);
  });

  testWidgets('addPatient stores the patient before returning it',
      (tester) async {
    late Future<Patient?> pending;
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          key: const Key('openPatientSheet'),
          onPressed: () => pending = addPatient(context),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openPatientSheet')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(WK.fieldNewPatientName), 'Stored Patient');
    await tester.pump();
    await tester.tap(find.byKey(WK.btnCreatePatient));
    await tester.pumpAndSettle();

    final created = await pending;
    expect(created, isNotNull);
    expect(patients.get(created!.id)?.title, 'Stored Patient');
  });

  testWidgets('dismissing the sheet stores nothing', (tester) async {
    Patient? created;
    await openSheet(tester, onSave: (patient) => created = patient);

    await tester.enterText(find.byKey(WK.fieldNewPatientName), 'Never Saved');
    await tester.pump();
    await tester.tap(find.byIcon(WindowsIcons.cancel));
    await tester.pumpAndSettle();

    expect(created, isNull);
    expect(patients.docs.values.where((p) => p.title == 'Never Saved'), isEmpty);
  });

  testWidgets('the patients screen asks before it opens the record',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    login.savedPermissions = Perm.full;
    addTearDown(PanelsManager.closeAll);
    addTearDown(WindowsManager.closeAll);

    await pumpApexoApp(tester, const PatientsScreen());
    await tester.tap(find.byKey(WK.btnNewPatient));
    await tester.pumpAndSettle();

    // Nothing is open while the sheet is asking: there is no record to show.
    expect(find.byKey(WK.fieldNewPatientName), findsOneWidget);
    expect(PanelsManager.active(), isEmpty);

    await tester.enterText(find.byKey(WK.fieldNewPatientName), 'Sheet Patient');
    await tester.pump();
    await tester.tap(find.byKey(WK.btnCreatePatient));
    await tester.pumpAndSettle();

    expect(patients.docs.values.where((p) => p.title == 'Sheet Patient'),
        hasLength(1));
    expect(PanelsManager.active().single.isNew, isFalse,
        reason: 'the sheet stored the patient before its record opened');
  });
}
