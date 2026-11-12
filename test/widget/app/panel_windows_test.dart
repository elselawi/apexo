@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_defaults.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
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
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/window_defaults.dart';

/// Restores the app's own store, which every test shares: a record left behind
/// changes what the next test sees.
void _restore<T extends Model>(
    ObservableDict<T> store, Map<String, T> records) {
  store.silently(() {
    store.clear();
    store.setAll(records.values.toList());
  });
  store.notifyView();
}

/// The panel and the row menu read the same window list (`patientWindows` and
/// friends), so these tests catch a window added to one side only.
void main() {
  late List<int> originalPerms;
  late Map<String, Patient> originalPatients;
  late Map<String, Appointment> originalAppointments;

  setUp(() async {
    originalPerms = login.savedPermissions;
    originalPatients = {...patients.observableMap.docs};
    originalAppointments = {...appointments.observableMap.docs};
    // Full permissions so the permission-gated windows are part of the comparison.
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

  testWidgets('a visit offers its windows beside its patient', (tester) async {
    final patient = Patient.fromJson({
      'id': 'windows-visit-patient',
      'title': 'Visit Patient',
    });
    patients.set(patient);
    final appointment = testAppointment(
      id: 'windows-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openAppointment(appointment));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id,
        reason: 'the patient is the panel; the visit is carried beside it');
    final visitWindows = panel.attached!.windows;
    expect(
      visitWindows.map((window) => window.id).toList(),
      [
        AppointmentWindow.dentalChart.id,
        AppointmentWindow.labwork.id,
        AppointmentWindow.gallery.id,
      ],
      reason: 'the chart, and the two editors the visit band offers',
    );
    expect(
      visitWindows.where((window) => window.attachedTo == null).length,
      1,
      reason: 'one row window: the visit\'s chart is its workspace',
    );
    expect(
      visitWindows
          .where((window) => window.attachedTo == PanelWindow.bandAttachment)
          .map((window) => window.id),
      [AppointmentWindow.labwork.id, AppointmentWindow.gallery.id],
      reason: 'labwork and photos hang off the band, which is always visible',
    );
  });

  testWidgets('a window of an attached visit is that visit\'s window',
      (tester) async {
    final patient = Patient.fromJson({
      'id': 'windows-open-patient',
      'title': 'Open Patient',
    });
    patients.set(patient);
    final appointment = testAppointment(
      id: 'windows-appointment-open',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openAppointment(appointment));
    await tester.pumpAndSettle();

    // Asking for a window must not start a second draft of the visit: the two
    // would overwrite each other.
    unawaited(openAppointment(appointment, AppointmentWindow.labwork));
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the panel holds the visit; nothing stands on its own',
    );
    expect(PanelsManager.active(), hasLength(1));
    expect(
      PanelsManager.active()
          .single
          .workspace
          .isOpen(AppointmentWindow.labwork.id, slot: kAttachedSlot),
      isTrue,
      reason: 'the visit was asked for the window, and opened it',
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
      (panel.windows
              .firstWhere((w) => w.id == PatientWindow.dentalChart.id)
              .body as DentalChartBody)
          .session
          .teeth['11'],
      'crown',
      reason: 'the panel shows the work, and nothing else',
    );
    expect(patients.get('p-carried')!.teeth['11'], isNull,
        reason: 'nothing is written until the panel saves');
  });

  testWidgets('a labwork window\'s work stays the visit\'s one draft',
      (tester) async {
    // No patient the account may see: the visit's windows stand on their own.
    final appointment = testAppointment(id: 'a-carried');
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openAppointment(appointment, AppointmentWindow.labwork));
    await tester.pumpAndSettle();

    final floating = WindowsManager.open().single;
    (floating.window.body as AppointmentLabworkSection).appointment.hasLabwork =
        true;

    // Reopening the visit reaches the same session, so the order typed in the
    // window is the visit's draft.
    unawaited(openAppointment(appointment));
    await tester.pumpAndSettle();

    final session = appointmentSessions.get('a-carried')!;
    expect(session.hasPendingEdits, isTrue,
        reason: 'the visit is dirty on the order typed in its window');
    expect(appointments.get('a-carried')!.hasLabwork, isFalse,
        reason: 'nothing is written until the visit\'s Save runs');
    expect(WindowsManager.open().single.hasChanges!(), isTrue);
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

  // `txt(window.titleKey)` cannot be checked by the audit tool, so check the
  // keys against the reference dictionary rather than the app's current locale.
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

  // A window is named by its id throughout, so two windows sharing one id
  // would share one button.
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

    // The chart is the open panel's own window; a second editor for the same
    // teeth would give the record two drafts.
    unawaited(openPatient(patient, PatientWindow.dentalChart));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(WindowsManager.open(), isEmpty);
    expect(panel.workspace.isOpen(PatientWindow.dentalChart.id), isTrue);
  });

  testWidgets('a window of another patient opens in that patient\'s panel',
      (tester) async {
    final open = Patient.fromJson({
      'id': 'windows-open-patient',
      'title': 'Open Patient',
    });
    final asked = Patient.fromJson({
      'id': 'windows-asked-patient',
      'title': 'Asked Patient',
    });
    patients.setAll([open, asked]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(open));
    await tester.pumpAndSettle();

    unawaited(openPatient(asked, PatientWindow.dentalChart));
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'a panel is on screen, so a record window joins its record there',
    );
    expect(PanelsManager.active(), hasLength(2),
        reason: 'the patient already open keeps its own panel');
    final panel =
        PanelsManager.active().firstWhere((panel) => panel.itemId == asked.id);

    // The layer plans the panel the opener just added; its plan opens the window
    // the caller asked for.
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1600)]),
    );
    await tester.pumpAndSettle();

    expect(panel.workspace.isOpen(PatientWindow.dentalChart.id), isTrue,
        reason: 'the asked-for window opens by default in the new panel');
    expect(tester.takeException(), isNull);
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

    // An opener's own request must not become the next panel's default, or the
    // window the user left alone would quietly disappear.
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
    // Wide enough for every window of this panel, so what is open is the user's
    // choice and nothing else.
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
    expect(workspace.open, [PatientWindow.dentalChart.id],
        reason: 'a record opens on its workspace, and nothing else');
    workspace.toggle(PatientWindow.appointments.id);
    workspace.minimize(PatientWindow.dentalChart.id);
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

    // A remembered id from a build that offered a window this one does not must
    // not become a blank window.
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

  testWidgets('a panel dirty only in its own record offers to discard it',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final patient = Patient.fromJson({
      'id': 'discard-own-record-patient',
      'title': 'Discard Own Record',
    });
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;

    PanelsManager.active([panel]);
    await pumpApexoApp(
      tester,
      Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: 350,
              height: double.infinity,
              child: PanelScreen(panel: panel, layoutWidth: 1600),
            ),
          ),
          const WindowsLayer(visible: true, screenWidth: 1600),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // No visit is carried, so the panel's own record is the only draft.
    expect(panel.owned, isEmpty);
    await tester.enterText(find.byKey(WK.fieldPatientYOB), '1990');
    await tester.pumpAndSettle();
    expect(panel.hasPendingEdits, isTrue);

    await tester.tap(find.byKey(WK.panelClose));
    await tester.pumpAndSettle();

    final prompt = find.byType(FlyoutContent);
    expect(prompt, findsOneWidget);
    final discard = find.descendant(
      of: prompt,
      matching: find.widgetWithText(
        FilledButton,
        txt('closePromptDiscardAll'),
      ),
    );
    expect(discard, findsWidgets,
        reason: 'a record dirty only in its own fields must still be '
            'dismissible without saving');

    await tester.tap(discard.first);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty);
    expect(patients.get('discard-own-record-patient')!.birth, isNot(1990),
        reason: 'discard loses the draft rather than writing it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a labwork order opens only its own window, not the visit panel',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final patient = testPatient(id: 'labwork-only-patient', name: 'Lab Only');
    patients.set(patient);
    final visit = testAppointment(
      id: 'labwork-only-visit',
      patientID: patient.id,
      hasLabwork: true,
      labName: 'Acme Dental Lab',
      labworkNotes: 'Zirconia crown',
    );
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());

    // A labwork row's task is the order itself, so its window opens on its own.
    await openAppointmentWindowOnItsOwn(visit, AppointmentWindow.labwork);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty,
        reason: 'the patient record is not the labwork order');
    final floating = WindowsManager.open().single;
    expect(floating.window.id, AppointmentWindow.labwork.id);
    expect(floating.window.id, isNot(AppointmentWindow.dentalChart.id));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a labwork order joins the visit panel once a panel is open',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final patient = testPatient(id: 'labwork-panel-patient', name: 'Lab Panel');
    final other = testPatient(id: 'labwork-other-patient', name: 'Other Panel');
    patients.setAll([patient, other]);
    final visit = testAppointment(
      id: 'labwork-panel-visit',
      patientID: patient.id,
      hasLabwork: true,
      labName: 'Acme Dental Lab',
      labworkNotes: 'Zirconia crown',
    );
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    // Another record's panel is on screen.
    unawaited(openPatient(other));
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), hasLength(1));

    // The labwork row still asks for the order, but beside a panel it belongs in
    // the visit's own panel instead of floating over someone else's record.
    await openAppointmentWindowOnItsOwn(visit, AppointmentWindow.labwork);
    await tester.pumpAndSettle();

    expect(WindowsManager.open(), isEmpty,
        reason: 'the visit panel holds the order now');
    final panel = PanelsManager.active()
        .firstWhere((panel) => panel.itemId == patient.id);
    expect(panel.attached?.itemId, visit.id);
    expect(
      panel.workspace.isOpen(AppointmentWindow.labwork.id, slot: kAttachedSlot),
      isTrue,
      reason: 'the window the row asked for is the one shown',
    );
    expect(tester.takeException(), isNull);
  });
}
