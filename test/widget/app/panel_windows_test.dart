import 'dart:async';

import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_defaults.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/window_defaults.dart';

/// Puts a store's records back as they were.
///
/// The stores are the app's own: a test that adds a patient and leaves it
/// behind changes what the next test sees — and what the app itself would
/// show.
void _restore<T extends Model>(
    ObservableDict<T> store, Map<String, T> records) {
  store.silently(() {
    store.clear();
    store.setAll(records.values.toList());
  });
  store.notifyView();
}

/// A row's context menu offers one item per window of the panel it opens, and
/// both the menu and the panel read the same list (`patientWindows`,
/// `appointmentWindows`, `expenseWindows`). These tests open the real panels and
/// compare the windows they build with that list, so a window cannot be added
/// to one side and silently missing from the other.
void main() {
  late List<int> originalPerms;
  late Map<String, Patient> originalPatients;
  late Map<String, Appointment> originalAppointments;

  setUp(() async {
    originalPerms = login.savedPermissions;
    originalPatients = {...patients.observableMap.docs};
    originalAppointments = {...appointments.observableMap.docs};
    // Full permissions so the conditional windows (appointments, post-op) exist
    // and are covered by the comparison.
    login.savedPermissions = Perm.full;
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    WindowOrigin.clear();
    await resetWindowDefaults();
  });

  tearDown(() async {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    login.savedPermissions = originalPerms;
    // The stores are the app's own: a record a test added must not be left
    // behind for the next test to find.
    _restore(patients.observableMap, originalPatients);
    _restore(appointments.observableMap, originalAppointments);
    await resetWindowDefaults();
  });

  /// The titles of the windows the open panel offers, in order.
  List<String> windowsOf(String itemId) {
    final panel = PanelsManager.active().firstWhere(
      (panel) => panel.itemId == itemId || panel.identifier == itemId,
      orElse: () => fail('no open panel for $itemId'),
    );
    return panel.windows.map((window) => window.id).toList();
  }

  testWidgets('the patient panel offers the windows its menus offer',
      (tester) async {
    final patient = Patient.fromJson({
      'id': 'windows-patient',
      'title': 'Windows Patient',
    });

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();

    expect(
      windowsOf('windows-patient'),
      patientWindows().map((window) => window.id).toList(),
    );
  });

  testWidgets('the appointment panel offers the windows its menus offer',
      (tester) async {
    final appointment = testAppointment(id: 'windows-appointment');

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointment(appointment);
    await tester.pumpAndSettle();

    expect(
      windowsOf('windows-appointment'),
      appointmentWindows(appointment).map((window) => window.id).toList(),
    );
  });

  testWidgets('a window of a visit whose panel is open is that panel\'s window',
      (tester) async {
    final appointment = testAppointment(id: 'windows-appointment-open');

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointment(appointment);
    await tester.pumpAndSettle();

    // Asking for one of its windows must not start a second draft of the visit:
    // the panel already holds it, and the two would overwrite each other.
    openAppointment(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the open panel holds the visit; nothing stands on its own',
    );
    expect(PanelsManager.active(), hasLength(1));
    expect(
      PanelsManager.active().single.workspace
          .isOpen(AppointmentWindow.labwork.id),
      isTrue,
      reason: 'the panel was asked for the window, and opened it',
    );
  });

  testWidgets('a window with unsaved work moves into the panel that opens',
      (tester) async {
    final patient = Patient.fromJson({'id': 'p-carried', 'title': 'Carried'});
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await openPatient(patient, PatientWindow.dentalChart);
    await tester.pumpAndSettle();

    final floating = WindowsManager.open().single;
    (floating.window.body as DentalChartBody).session.teeth['11'] = 'crown';
    expect(floating.hasChanges!(), isTrue);

    // The record's panel opens: the window's work comes with it, as one draft.
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsNothing,
        reason: 'there is nothing to ask: the work moves, it is not lost');
    expect(WindowsManager.open(), isEmpty,
        reason: 'the window moved into the panel');

    final panel = PanelsManager.active().single;
    expect(panel.hasPendingEdits, isTrue,
        reason: 'the panel opens dirty on the work it adopted');
    expect(
      (panel.windows.firstWhere((w) => w.id == PatientWindow.dentalChart.id).body
              as DentalChartBody)
          .session
          .teeth['11'],
      'crown',
      reason: 'the panel shows the work, and nothing else',
    );
    expect(patients.get('p-carried')!.teeth['11'], isNull,
        reason: 'nothing is written until the panel saves');
  });

  testWidgets('a labwork window moves into the visit panel', (tester) async {
    final appointment = testAppointment(id: 'a-carried');
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointment(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();

    final floating = WindowsManager.open().single;
    (floating.window.body as AppointmentLabworkSection)
        .appointment
        .hasLabwork = true;

    openAppointment(appointment);
    await tester.pumpAndSettle();

    expect(WindowsManager.open(), isEmpty,
        reason: 'the window moved into the panel');
    expect(PanelsManager.active().single.hasPendingEdits, isTrue,
        reason: 'the visit panel opens dirty on the order it adopted');
    expect(appointments.get('a-carried')!.hasLabwork, isFalse,
        reason: 'nothing is written until the panel saves');
  });

  testWidgets('the orders panel offers the windows its menus offer',
      (tester) async {
    final order = testExpense(id: 'windows-order');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses([order], 'Windows Supplier', 'windows-supplier'));
    await tester.pumpAndSettle();

    expect(
      windowsOf('windows-supplier'),
      [
        expenseSummaryWindowId,
        ...expenseWindows().map((window) => window.id),
      ],
      reason: 'the panel leads with the supplier\'s figures',
    );
  });

  testWidgets('an archived order panel offers only its own window',
      (tester) async {
    final order = testExpense(id: 'windows-archived-order');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(
        openExpenses([order], 'Windows Archived', 'windows-supplier', true));
    await tester.pumpAndSettle();

    expect(
      windowsOf('windows-supplier'),
      [
        expenseSummaryWindowId,
        ...expenseWindows(singleArchived: true).map((window) => window.id),
      ],
      reason: 'the panel leads with the order\'s figures',
    );
  });

  // The menus label their items with `txt(window.titleKey)`, which the audit
  // tool cannot check statically — so check it here, against the reference
  // dictionary rather than the one the app happens to be in.
  test('every window title key exists in the dictionary', () {
    final dictionary = En().dictionary;
    final keys = [
      ...PatientWindow.values.map((window) => window.titleKey),
      ...AppointmentWindow.values.map((window) => window.titleKey),
      ...ExpenseWindow.values.map((window) => window.titleKey),
    ];
    for (final key in keys) {
      expect(dictionary.containsKey(key), isTrue, reason: key);
    }
  });

  // A window is named by its id, and the dock, the opener and the menu all
  // name it by that: two windows sharing one id would share one button.
  test('every kind of record names its windows apart', () {
    final idLists = <List<String>>[
      patientWindows().map((window) => window.id).toList(),
      appointmentWindows(null).map((window) => window.id).toList(),
      expenseWindows().map((window) => window.id).toList(),
    ];
    for (final ids in idLists) {
      expect(ids.toSet().length, ids.length, reason: ids.join(', '));
    }
  });

  testWidgets('asking for a window of an open panel shows it in that panel',
      (tester) async {
    final patient = Patient.fromJson({
      'id': 'windows-record-patient',
      'title': 'Record Patient',
    });

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    PanelsManager.active().single.workspace
      ..minimize(PatientWindow.dentalChart.id)
      ..minimize(PatientWindow.appointments.id);

    // The record's panel is up, so the chart is that panel's window: a second
    // editor for the same teeth would give the record two drafts to save.
    unawaited(openPatient(patient, PatientWindow.dentalChart));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(WindowsManager.open(), isEmpty);
    expect(panel.workspace.isOpen(PatientWindow.dentalChart.id), isTrue);
  });

  testWidgets('a window of another patient still opens on its own',
      (tester) async {
    final open = Patient.fromJson({
      'id': 'windows-open-patient',
      'title': 'Open Patient',
    });
    final asked = Patient.fromJson({
      'id': 'windows-asked-patient',
      'title': 'Asked Patient',
    });

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(open));
    await tester.pumpAndSettle();

    // A panel for someone else is not an editor for these teeth: asking for the
    // chart opens the chart, not a second panel.
    unawaited(openPatient(asked, PatientWindow.dentalChart));
    await tester.pumpAndSettle();

    expect(PanelsManager.active().single.itemId, open.id);
    expect(WindowsManager.open(), hasLength(1));
    expect(WindowsManager.open().single.scope, 'patient:${asked.id}');
  });

  testWidgets('the patient record can open without its windows',
      (tester) async {
    final patient = Patient.fromJson({
      'id': 'windows-record-only',
      'title': 'Record Only',
    });
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const layer =
        Stack(children: [WindowsLayer(visible: true, screenWidth: 1600)]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    // The same panel opened the usual way fills the screen with the windows it
    // has room for — which is what the record on its own must not do.
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);
    expect(PanelsManager.active().single.workspace.open, isNotEmpty);
    PanelsManager.closeAll();

    unawaited(openPatientRecord(patient));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);

    final panel = PanelsManager.active().single;
    expect(panel.workspace.open, isEmpty, reason: 'the record came alone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the work in a window moves into the record it belongs to',
      (tester) async {
    final patient = Patient.fromJson({'id': 'p-record-work', 'title': 'Work'});
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient, PatientWindow.dentalChart));
    await tester.pumpAndSettle();

    final floating = WindowsManager.open().single;
    (floating.window.body as DentalChartBody).session.teeth['11'] = 'crown';

    // The user asks for the record itself, from the window that holds the work.
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1600)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowOpenRecord));
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the record holds the work now; the window has nothing to show',
    );
    final panel = PanelsManager.active().single;
    expect(
      panel.hasPendingEdits,
      isTrue,
      reason: 'the panel opens dirty on the work the window was holding',
    );
    expect(
      patients.get('p-record-work')!.teeth['11'],
      isNull,
      reason: 'nothing is written until the panel saves',
    );
  });

  testWidgets('asking for a window does not rewrite the windows left open',
      (tester) async {
    final patient = testPatient(id: 'windows-asked-record', name: 'Asked');
    patients.set(patient);
    tester.view.physicalSize = const Size(2200, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const layer =
        Stack(children: [WindowsLayer(visible: true, screenWidth: 2200)]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);
    await tester.pumpAndSettle();

    // The user leaves one window open and puts the rest away.
    final workspace = PanelsManager.active().single.workspace;
    for (final id in workspace.open.toList()) {
      workspace.minimize(id);
    }
    workspace.toggle(PatientWindow.appointments.id);
    expect(windowDefaults.of('patient'), [PatientWindow.appointments.id]);

    // Asking for another window is the opener's own request: it must not
    // become the next panel's default, or the window the user left alone
    // would quietly disappear.
    unawaited(openPatient(patient, PatientWindow.dentalChart));
    await tester.pumpAndSettle();

    expect(
      windowDefaults.of('patient'),
      [PatientWindow.appointments.id],
      reason: 'the windows the user left open are theirs to change',
    );
  });

  testWidgets('a window leads back to the record it belongs to',
      (tester) async {
    final patient = Patient.fromJson({
      'id': 'windows-back-patient',
      'title': 'Back Patient',
    });
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient, PatientWindow.appointments));
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), isEmpty);

    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1600)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowOpenRecord));
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the window makes way for the panel that holds the record',
    );
    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id);
    expect(
      panel.workspace.isOpen(PatientWindow.appointments.id),
      isTrue,
      reason: 'the panel opens on the window the user was looking at',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a panel opens with the windows the last one was left with',
      (tester) async {
    final first = testPatient(id: 'windows-remember-a', name: 'Remember A');
    final second = testPatient(id: 'windows-remember-b', name: 'Remember B');
    patients.setAll([first, second]);
    // Wide enough for every window of this panel, so what is on screen is the
    // user's choice and nothing else.
    tester.view.physicalSize = const Size(2200, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const layer =
        Stack(children: [WindowsLayer(visible: true, screenWidth: 2200)]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(first));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);
    await tester.pumpAndSettle();

    // The panel opens a screenful by itself; the user keeps one of them and
    // closes the record.
    final workspace = PanelsManager.active().single.workspace;
    expect(workspace.open, hasLength(greaterThan(1)));
    for (final id in workspace.open.toList()) {
      workspace.minimize(id);
    }
    workspace.toggle(PatientWindow.appointments.id);
    PanelsManager.closeAll();

    unawaited(openPatient(second));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);
    await tester.pumpAndSettle();

    expect(
      PanelsManager.active().single.workspace.open,
      [PatientWindow.appointments.id],
      reason: 'the next patient\'s record opens the way this one was left',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a panel the user emptied comes back with no windows',
      (tester) async {
    final first = testPatient(id: 'windows-emptied-a', name: 'Emptied A');
    final second = testPatient(id: 'windows-emptied-b', name: 'Emptied B');
    patients.setAll([first, second]);
    tester.view.physicalSize = const Size(2200, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const layer =
        Stack(children: [WindowsLayer(visible: true, screenWidth: 2200)]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(first));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);
    await tester.pumpAndSettle();

    final workspace = PanelsManager.active().single.workspace;
    expect(workspace.open, isNotEmpty);
    for (final id in workspace.open.toList()) {
      workspace.minimize(id);
    }
    PanelsManager.closeAll();

    unawaited(openPatient(second));
    await tester.pumpAndSettle();
    await pumpApexoApp(tester, layer);
    await tester.pumpAndSettle();

    expect(
      PanelsManager.active().single.workspace.open,
      isEmpty,
      reason: 'leaving none open is a choice the next panel keeps',
    );
  });

  testWidgets('a window a panel no longer offers is not put on screen',
      (tester) async {
    final patient = testPatient(id: 'windows-stale-patient', name: 'Stale');
    patients.set(patient);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Remembered by a build that had a window this one does not: permissions
    // change, and a remembered id must not become a blank window.
    windowDefaults.remember('patient', ['aWindowThatIsGone']);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1600)]),
    );
    await tester.pumpAndSettle();

    expect(PanelsManager.active().single.workspace.open, isEmpty);
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window with no record behind it offers no way back',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    WindowsManager.showStandalone(
      const PanelWindow(
        id: 'plain',
        title: 'appointments',
        icon: FluentIcons.calendar,
        body: SizedBox(height: 40),
      ),
    );
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1600)]),
    );

    expect(find.byKey(WK.windowOpenRecord), findsNothing);
  });
}
