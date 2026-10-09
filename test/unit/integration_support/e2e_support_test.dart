@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../integration_test/support/e2e.dart';
import '../../../integration_test/support/fixtures.dart';
import '../../../integration_test/support/store_ext.dart';

void main() {
  group('integration support helpers', () {
    testWidgets('readText reads rendered and editable text', (tester) async {
      await tester.pumpWidget(
        const FluentApp(
          home: NavigationView(
            content: Column(
              children: [
                Text.rich(TextSpan(text: 'rich value')),
                TextBox(key: Key('editor')),
              ],
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('editor')), 'typed value');
      await tester.pump();

      expect(E2E.readText(tester, find.text('rich value')), 'rich value');
      expect(
          E2E.readText(tester, find.byKey(const Key('editor'))), 'typed value');
    });

    testWidgets('expectEventually waits for a text change', (tester) async {
      final status = ValueNotifier<String>('loading');
      unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
        status.value = 'ready';
      }));

      await tester.pumpWidget(
        FluentApp(
          home: NavigationView(
            content: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, value, __) => Text(value, key: const Key('status')),
            ),
          ),
        ),
      );

      final value = await E2E.expectEventually(
        tester,
        find.byKey(const Key('status')),
        equals('ready'),
      );
      expect(value, 'ready');
    });

    testWidgets('acceptUnsavedChanges closes an already open prompt',
        (tester) async {
      await tester.pumpWidget(
        const _DraftHarness(promptInitiallyOpen: true),
      );

      await E2E.acceptUnsavedChanges(tester);

      expect(find.byKey(WK.panelSave), findsNothing);
      expect(find.text('panel open'), findsNothing);
    });

    testWidgets('discardDraft closes the panel through the prompt',
        (tester) async {
      await tester.pumpWidget(
        const _DraftHarness(promptInitiallyOpen: false),
      );

      await E2E.discardDraft(tester);

      expect(find.byKey(WK.panelSave), findsNothing);
      expect(find.text('panel open'), findsNothing);
    });
  });

  group('fixture store helpers', () {
    late _StoreSnapshot snapshot;

    setUp(() {
      snapshot = _StoreSnapshot.capture();
      _clearStores();
    });

    tearDown(() {
      _clearStores();
      snapshot.restore();
    });

    test('deleteEverything only removes harness-owned local rows', () async {
      const ownedPatientId = 'ownpatient000001';
      const keepPatientId = 'keeppatient0001';
      patients.setAll([
        Patient.fromJson(
            {'id': ownedPatientId, 'title': 'e2e baseline patient'}),
        Patient.fromJson({'id': keepPatientId, 'title': 'clinic patient'}),
      ]);

      appointments.setAll([
        Appointment.fromJson({
          'id': 'ownappt00000001',
          'patientID': ownedPatientId,
          'date': dateToWire(DateTime.now()),
        }),
        Appointment.fromJson({
          'id': 'keepappt0000001',
          'patientID': keepPatientId,
          'date': dateToWire(DateTime.now()),
        }),
      ]);

      expenses.setAll([
        Expense.fromJson({
          'id': 'ownsupp00000001',
          'isSupplier': true,
          'supplierName': 'e2e baseline supplier',
        }),
        Expense.fromJson({
          'id': 'ownorder0000001',
          'supplierId': 'ownsupp00000001',
          'cost': 40,
        }),
        Expense.fromJson({
          'id': 'keepsupp0000001',
          'isSupplier': true,
          'supplierName': 'clinic supplier',
        }),
      ]);

      notes.setAll([
        Note.fromJson({'id': 'ownnote00000001', 'title': 'e2e baseline note'}),
        Note.fromJson({'id': 'keepnote0000001', 'title': 'clinic note'}),
      ]);

      final report =
          await Fixtures.deleteEverything(null, scopes: ['e2e baseline']);

      expect(report, (patients: 1, appointments: 1, expenses: 2, notes: 1));
      expect(patients.docs.keys, {keepPatientId});
      expect(appointments.docs.keys, {'keepappt0000001'});
      expect(expenses.docs.keys, {'keepsupp0000001'});
      expect(notes.docs.keys, {'keepnote0000001'});
    });

    test('seedBaseline creates one scoped baseline and replaces its prior copy',
        () async {
      const scope = 'e2e baseline unit';

      final first = await Fixtures.seedBaseline(null, scope: scope);
      expect(first.patientIDs, hasLength(3));
      expect(first.patientNames, everyElement(startsWith(scope)));
      expect(
        appointments.docs.values
            .where((row) => first.patientIDs.contains(row.patientID)),
        hasLength(5),
      );
      expect(
        appointments.docs.values
            .where((row) => row.labName == '$scope lab' && row.hasLabwork),
        hasLength(1),
      );
      expect(
        expenses.docs.values.where(
            (row) => row.isSupplier && row.supplierName == first.supplierName),
        hasLength(1),
      );
      expect(
        notes.docs.values.where((row) => row.title == first.noteTitle),
        hasLength(1),
      );

      await Fixtures.seedBaseline(null, scope: scope);

      expect(
        patients.docs.values.where((row) => row.title.startsWith(scope)),
        hasLength(3),
      );
      expect(
        appointments.docs.values
            .where((row) => first.patientNames.contains(row.patient?.title)),
        hasLength(5),
      );
      expect(
        expenses.docs.values
            .where((row) => row.supplierName == '$scope supplier'),
        hasLength(1),
      );
      expect(
        notes.docs.values.where((row) => row.title == '$scope note'),
        hasLength(1),
      );
    });
  });
}

class _DraftHarness extends StatefulWidget {
  const _DraftHarness({required this.promptInitiallyOpen});

  final bool promptInitiallyOpen;

  @override
  State<_DraftHarness> createState() => _DraftHarnessState();
}

class _DraftHarnessState extends State<_DraftHarness> {
  bool panelOpen = true;
  bool promptOpen = false;

  @override
  void initState() {
    super.initState();
    promptOpen = widget.promptInitiallyOpen;
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      home: NavigationView(
        content: Column(
          children: [
            if (panelOpen)
              IconButton(
                key: WK.panelClose,
                icon: const Icon(FluentIcons.clear),
                onPressed: () => setState(() => promptOpen = true),
              ),
            if (panelOpen)
              const IconButton(
                key: WK.panelSave,
                icon: Icon(FluentIcons.save),
                onPressed: null,
              ),
            if (panelOpen) const Text('panel open'),
            if (promptOpen)
              FlyoutContent(
                child: FilledButton(
                  onPressed: () => setState(() {
                    promptOpen = false;
                    panelOpen = false;
                  }),
                  child: const Text('discard'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoreSnapshot {
  _StoreSnapshot({
    required this.patientRows,
    required this.appointmentRows,
    required this.expenseRows,
    required this.noteRows,
  });

  factory _StoreSnapshot.capture() => _StoreSnapshot(
        patientRows: [
          for (final row in patients.docs.values)
            Patient.fromJson(row.toJson()),
        ],
        appointmentRows: [
          for (final row in appointments.docs.values)
            Appointment.fromJson(row.toJson()),
        ],
        expenseRows: [
          for (final row in expenses.docs.values)
            Expense.fromJson(row.toJson()),
        ],
        noteRows: [
          for (final row in notes.docs.values) Note.fromJson(row.toJson()),
        ],
      );

  final List<Patient> patientRows;
  final List<Appointment> appointmentRows;
  final List<Expense> expenseRows;
  final List<Note> noteRows;

  void restore() {
    patients.setAll(patientRows);
    appointments.setAll(appointmentRows);
    expenses.setAll(expenseRows);
    notes.setAll(noteRows);
  }
}

void _clearStores() {
  patients.observableMap.clear();
  appointments.observableMap.clear();
  expenses.observableMap.clear();
  notes.observableMap.clear();
}
