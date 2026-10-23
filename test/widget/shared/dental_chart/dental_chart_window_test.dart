@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/panel_window_card.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/common_widgets/teeth_selector/opg_dental_chart.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/patients/patient_dental_chart.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_owner_line.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/window_defaults.dart';

/// Windows, as the shell draws them: a panel's own windows sharing the screen
/// beside it, the same windows over the panel one at a time on a phone, and a
/// dental chart that has no panel behind it and brings its own Save and Close.
void main() {
  late List<Patient> previousPatients;
  late List<Appointment> previousAppointments;
  late List<int> previousPermissions;

  setUp(() async {
    previousPatients = patients.docs.values.toList();
    previousAppointments = appointments.docs.values.toList();
    previousPermissions = login.savedPermissions;
    patients.observableMap.clear();
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    // A window opened by a test with no tap behind it must not land at the last
    // position another test's tap recorded.
    WindowOrigin.clear();
    await resetWindowDefaults();
  });

  tearDown(() async {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    patients.observableMap.clear();
    patients.setAll(previousPatients);
    appointments.observableMap.clear();
    appointments.setAll(previousAppointments);
    login.savedPermissions = previousPermissions;
    // The windows a panel was left with are a device preference: they are put
    // back as they were, so the next test starts from the user's own.
    await resetWindowDefaults();
  });

  DentalChartSession sessionFor({
    String id = 'patient:window-test',
    Map<String, String>? teeth,
    Future<void> Function()? onSave,
  }) {
    return DentalChartSession(
      id: id,
      titleKey: kDentalChartTitleKey,
      subtitle: () => 'Window Patient',
      type: StateType.state,
      teeth: teeth ?? {},
      extraNotes: {},
      history: () => const [],
      oldNotes: () => const {},
      historyTitle: 'toothAppointmentNotes',
      onSave: onSave,
    );
  }

  /// Shows [session] the way a list does: a window of its own with Save and
  /// Close.
  void openStandaloneChart(DentalChartSession session,
      {Future<void> Function()? onSave}) {
    WindowsManager.showStandalone(
      dentalChartWindow(session),
      scope: session.id,
      onSave: onSave ?? session.save,
      hasChanges: () => session.hasChanges,
    );
  }

  PanelWindow window(String id) => PanelWindow(
        id: id,
        title: 'patientDetails',
        icon: FluentIcons.medication_admin,
        body: SizedBox(height: 40, child: Text(id)),
      );

  /// A window that edits the record, so it carries the panel's Save.
  PanelWindow editorWindow(String id) => PanelWindow(
        id: id,
        title: 'operativeDetails',
        icon: FluentIcons.medical_care,
        editsRecord: true,
        body: SizedBox(height: 40, child: Text(id)),
      );

  DelegatedPanel panelWith(List<PanelWindow> windows) => DelegatedPanel(
        itemId: 'window-panel',
        singularName: 'patient',
        unicodeSymbol: '👤',
        icon: FluentIcons.medication_admin,
        checkUnsavedChanges: () => false,
        onSave: () async => const [],
        windows: windows,
      );

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The panel and the layer the app shell stacks above it, arranged the way
  /// the shell arranges them: the panel on the end side, windows beside it.
  Future<void> pumpShell(
    WidgetTester tester,
    Panel panel,
    double width,
  ) async {
    PanelsManager.active([panel]);
    await pumpApexoApp(
      tester,
      Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: width < 490 ? width : 350,
              height: double.infinity,
              child: PanelScreen(panel: panel, layoutWidth: width),
            ),
          ),
          WindowsLayer(visible: true, screenWidth: width),
        ],
      ),
    );
  }

  /// The order the windows are stacked in, bottom first — read from the keys the
  /// layer gives each window's place.
  List<String> stackingOrder(WidgetTester tester) => [
        for (final builder
            in tester.widgetList<ValueListenableBuilder<WindowPlacement>>(
          find.byType(ValueListenableBuilder<WindowPlacement>),
        ))
          ((builder.key! as ValueKey<String>).value).replaceFirst('place-', ''),
      ];

  testWidgets('a panel opens only the windows its row holds', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final panel = panelWith([
      window('a'),
      window('b'),
      window('c'),
      window('d'),
      window('e'),
    ]);

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The panel's first window is the panel: it is never a floating card.
    expect(find.byKey(const ValueKey('window-card-a')), findsNothing);
    expect(find.text('a'), findsOneWidget,
        reason: 'the first window is inline');
    // Three 350-wide windows share the row beside the panel; the fourth has no
    // room beside them and waits in the dock rather than being laid over them.
    for (final id in ['b', 'c', 'd']) {
      expect(find.byKey(ValueKey('window-card-$id')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('window-card-e')),
      findsNothing,
      reason: 'no room in the row, so it stays in the dock',
    );
    // Every floating window has its pill, open or not.
    for (final id in ['b', 'c', 'd', 'e']) {
      expect(find.byKey(WK.windowToggle(id)), findsOneWidget);
    }

    final card = tester.getRect(find.byKey(const ValueKey('window-card-b')));
    expect(card.right, lessThanOrEqualTo(1600 - 350));
    expect(
      card.width,
      350,
      reason: 'a side window is exactly as wide as its panel',
    );

    // One row: side by side, all at the same top, none over another.
    final first = tester.getRect(find.byKey(const ValueKey('window-card-b')));
    final second = tester.getRect(find.byKey(const ValueKey('window-card-c')));
    final third = tester.getRect(find.byKey(const ValueKey('window-card-d')));
    expect(second.top, first.top);
    expect(third.top, first.top);
    expect(second.right, lessThanOrEqualTo(first.left));
    expect(third.right, lessThanOrEqualTo(second.left));
  });

  testWidgets('a window is dragged by its header and stays on the screen',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final panel = panelWith([window('a'), window('b')]);

    await pumpShell(tester, panel, 1400);
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('window-card-b'));
    final before = tester.getRect(card);

    // The header is the handle; the body below it keeps its own gestures.
    Offset handle() => tester.getTopLeft(card) + const Offset(40, 12);
    await tester.dragFrom(handle(), const Offset(-120, 80));
    await tester.pumpAndSettle();

    final after = tester.getRect(card);
    expect(after.left, lessThan(before.left), reason: 'it moved inwards');
    expect(after.top, greaterThan(before.top), reason: 'it moved down');

    // Dragged far past the edge, it comes back rather than out of reach.
    await tester.dragFrom(handle(), const Offset(3000, 3000));
    await tester.pumpAndSettle();
    final clamped = tester.getRect(card);
    expect(clamped.left, greaterThanOrEqualTo(0));
    expect(
      clamped.top,
      lessThanOrEqualTo(900 - kWindowMinVisible),
      reason: 'a window keeps its header on the screen',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('touching a window brings it in front of the others',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final panel = panelWith([window('a'), window('b'), window('c')]);

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    // `c` opened after `b`, so it stacks on top of it.
    expect(stackingOrder(tester), ['b', 'c']);

    // `c` cascades over `b`'s body: touch `b` where it still shows — its own
    // header, away from the button at its far end.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('window-card-b'))) +
          const Offset(30, 12),
    );
    await tester.pumpAndSettle();

    expect(stackingOrder(tester), ['c', 'b'],
        reason: 'the window touched is first');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a standalone window closes from its header, asking if dirty',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    var dirty = false;
    WindowsManager.showStandalone(
      window('labwork'),
      onSave: () async {},
      hasChanges: () => dirty,
    );

    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(WK.windowHeaderClose), findsOneWidget);

    // Nothing to lose: one press closes it.
    await tester.tap(find.byKey(WK.windowHeaderClose));
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), isEmpty);

    // With unsaved work the same press asks first.
    dirty = true;
    WindowsManager.showStandalone(
      window('labwork'),
      onSave: () async {},
      hasChanges: () => dirty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowHeaderClose));
    await tester.pumpAndSettle();
    expect(
      WindowsManager.open(),
      hasLength(1),
      reason: 'the window stays until the question is answered',
    );
    expect(find.text(txt('sureClosePanel')), findsWidgets);

    await tester.tap(find.text(txt('sure')).last);
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the labwork window starts an order and takes it away',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final patient = testPatient(id: 'labwork-window-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'labwork-window-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointmentWindow(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();
    await pumpApexoApp(
        tester,
        const Stack(
            children: [WindowsLayer(visible: true, screenWidth: 1400)]));
    await tester.pumpAndSettle();

    // A visit with no order offers to start one.
    expect(find.byKey(WK.btnAddLabwork), findsOneWidget);
    expect(find.byType(LabWorkEditor), findsNothing);

    await tester.tap(find.byKey(WK.btnAddLabwork));
    await tester.pumpAndSettle();
    expect(find.byType(LabWorkEditor), findsOneWidget);
    expect(find.byKey(WK.btnAddLabwork), findsNothing);

    // The order is part of the visit: saving the window writes it.
    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();
    expect(appointments.get(appointment.id)!.hasLabwork, isTrue);

    // And it can be taken away again, which is a change to save.
    await tester.tap(find.byIcon(WindowsIcons.delete));
    await tester.pumpAndSettle();
    expect(find.byKey(WK.btnAddLabwork), findsOneWidget);
    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();
    expect(appointments.get(appointment.id)!.hasLabwork, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the operative window leaves labwork to its own window',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final patient = testPatient(id: 'operative-window-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'operative-window-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointmentWindow(appointment, AppointmentWindow.operative);
    await tester.pumpAndSettle();
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(WK.btnAddLabwork), findsNothing);
    expect(find.byType(LabWorkEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window says whose record it belongs to', (tester) async {
    setViewport(tester, const Size(1400, 900));
    final patient = testPatient(id: 'owner-line-patient', name: 'Nadia Hassan');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'owner-line-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointmentWindow(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();
    await pumpApexoApp(
        tester,
        const Stack(
            children: [WindowsLayer(visible: true, screenWidth: 1400)]));
    await tester.pumpAndSettle();

    // The window's label is "Labwork" for every visit; the line under it says
    // which visit.
    expect(find.textContaining('Nadia Hassan'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window with unsaved work shows a dot by its title',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    var dirty = true;
    WindowsManager.showStandalone(
      window('labwork'),
      onSave: () async {},
      hasChanges: () => dirty,
    );
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(WK.unsavedDot), findsOneWidget);

    // Saving makes it clean, and the dot goes: the window says so without
    // anything else having to change.
    dirty = false;
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byKey(WK.unsavedDot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a patient panel opens the chart beside its list',
      (tester) async {
    setViewport(tester, const Size(1800, 1000));
    final patient = testPatient(id: 'grid-patient');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1800);
    await tester.pumpAndSettle();

    final workspace = PanelsManager.active().single.workspace;
    expect(
      workspace.isOpen(PatientWindow.dentalChart.id),
      isTrue,
    );
    expect(
      workspace.isOpen(PatientWindow.appointments.id),
      isTrue,
      reason: 'the list fits beside the chart, so it is shown beside it',
    );
    expect(
      workspace.open,
      hasLength(2),
      reason: 'and nothing else: the row holds two windows, not four',
    );
    // Beside each other, never stacked.
    final chart = tester.getRect(
        find.byKey(const ValueKey('window-card-$kDentalChartWindowId')));
    final list = tester.getRect(
        find.byKey(ValueKey('window-card-${PatientWindow.appointments.id}')));
    expect(list.top, chart.top);
    expect(list.right, lessThanOrEqualTo(chart.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a visit from the list window closes the list',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'list-close-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'list-close-visit',
      patientID: patient.id,
      date: DateTime(2026, 2, 3, 9),
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    // The patient's visits, on their own — what a table cell opens.
    unawaited(openPatient(patient, PatientWindow.appointments));
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), hasLength(1));

    await pumpApexoApp(
      tester,
      // The card is a fixed-width layout; the suite's synthetic font is wider
      // than any real one, so it is scaled down to keep the card on screen.
      const MediaQuery(
        data: MediaQueryData(
          size: Size(1600, 1000),
          textScaler: TextScaler.linear(0.5),
        ),
        child: Stack(
          children: [WindowsLayer(visible: true, screenWidth: 1600)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The visit's own open button, inside the list.
    await tester.tap(find.byIcon(FluentIcons.go).first);
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the list was a way in, not a window to keep behind the visit',
    );
    expect(PanelsManager.active().single.itemId, appointment.id);
  });

  testWidgets('starting a visit from the list window closes the list',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'list-add-patient');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient, PatientWindow.appointments));
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), hasLength(1));

    await pumpApexoApp(
      tester,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(1600, 1000),
          textScaler: TextScaler.linear(0.5),
        ),
        child: Stack(
          children: [WindowsLayer(visible: true, screenWidth: 1600)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "Add appointment" in the list's own footer: the same rule as tapping a
    // visit — the list was a way in, so it makes way for the new visit.
    await tester.tap(find.byIcon(FluentIcons.add_event));
    await tester.pumpAndSettle();

    expect(WindowsManager.open(), isEmpty);
    expect(
      PanelsManager.active().single.isNew,
      isTrue,
      reason: 'the new visit is up, ready to fill in',
    );
  });

  testWidgets('the chart window says whose record it belongs to',
      (tester) async {
    setViewport(tester, const Size(1800, 1000));
    final patient =
        testPatient(id: 'chart-owner-patient', name: 'Nadia Hassan');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1800);
    await tester.pumpAndSettle();

    // The window's own label is "Dental Chart" for every record; the line under
    // it says whose chart this is.
    final card =
        find.byKey(const ValueKey('window-card-$kDentalChartWindowId'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.text(patientOwnerLine(patient)),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window that edits the record saves it from its own footer',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    var saves = 0;
    final panel = DelegatedPanel(
      itemId: 'saving-window-panel',
      singularName: 'appointment',
      unicodeSymbol: '📅',
      icon: WindowsIcons.calendar,
      checkUnsavedChanges: () => true,
      onSave: () async {
        saves++;
        return const [];
      },
      windows: [window('details'), editorWindow('operative')],
    );

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    // The editing happens in the window, so the saving is offered there too…
    expect(find.byKey(WK.windowSaveFooter('operative')), findsOneWidget);
    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();
    expect(saves, 1, reason: 'the panel\'s own write, run from the window');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window that only reads offers no Save', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final panel = panelWith([
      window('details'),
      // A list of the record's visits: it edits nothing, so a Save would write
      // something the window does not show.
      window('appointments'),
    ]);

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    expect(find.byKey(WK.windowSaveFooter('appointments')), findsNothing);
    expect(find.byKey(WK.windowSave), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window opened again comes to the front', (tester) async {
    setViewport(tester, const Size(1400, 900));
    final patient = testPatient(id: 'raise-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'raise-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointmentWindow(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();
    openAppointmentWindow(appointment, AppointmentWindow.operative);
    await tester.pumpAndSettle();
    await pumpApexoApp(
        tester,
        const Stack(
            children: [WindowsLayer(visible: true, screenWidth: 1400)]));
    await tester.pumpAndSettle();

    // Standalone keys are `scope#id`: the editor is the part after the hash.
    List<String> names() =>
        stackingOrder(tester).map((key) => key.split('#').last).toList();
    expect(names(), ['labwork', 'operative']);

    // Asking for the labwork again must not rebuild it — and must not leave it
    // underneath the window opened after it.
    openAppointmentWindow(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();
    expect(names(), ['operative', 'labwork']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window opened from a row appears at that row', (tester) async {
    setViewport(tester, const Size(1400, 900));
    final patient = testPatient(id: 'origin-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'origin-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    // What the app's pointer listener records: the tap that asked for it.
    WindowOrigin.record(const Offset(300, 500));
    openAppointmentWindow(appointment, AppointmentWindow.labwork);
    await tester.pumpAndSettle();
    await pumpApexoApp(
        tester,
        const Stack(
            children: [WindowsLayer(visible: true, screenWidth: 1400)]));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(
        const ValueKey('window-card-appointment:origin-appointment#labwork')));
    expect(
      card.left,
      300,
      reason: 'it opens where the tap was, not at the panel side',
    );
    expect(card.top, 500 - kWindowTapLift);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window opened again comes from where it is opened now',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    final card = find.byKey(const ValueKey('window-card-row:again#again'));

    WindowOrigin.record(const Offset(300, 300));
    WindowsManager.showStandalone(window('again'), scope: 'row:again');
    await tester.pumpAndSettle();
    expect(tester.getRect(card).left, 300);

    // Closed, then opened again from a different place on the screen.
    WindowsManager.close(WindowsManager.open().single);
    await tester.pumpAndSettle();
    expect(card, findsNothing);

    WindowOrigin.record(const Offset(700, 160));
    WindowsManager.showStandalone(window('again'), scope: 'row:again');
    await tester.pumpAndSettle();
    expect(
      tester.getRect(card).left,
      700,
      reason:
          'the place belongs to this opening, not to the window it replaces',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no panel open a window can be dragged anywhere',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    WindowsManager.showStandalone(window('free'), scope: 'row:free');
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('window-card-row:free#free'));
    final before = tester.getRect(card);
    expect(
      before.right,
      greaterThan(1400 - 350),
      reason: 'the screen, not a panel column, is the limit',
    );

    // Dragged to the far edge it stays on the screen, over where a panel would
    // have been.
    await tester.dragFrom(
      tester.getTopLeft(card) + const Offset(40, 12),
      const Offset(600, 120),
    );
    await tester.pumpAndSettle();
    final after = tester.getRect(card);
    expect(after.right, 1400 - kWindowEdgeInset);
    expect(after.top, before.top + 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone a panel makes the window that opened it step aside',
      (tester) async {
    setViewport(tester, const Size(600, 800));
    final panel = panelWith([window('a'), window('b')]);

    // A list on its own, with no panel behind it.
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 600)]),
    );
    WindowsManager.showStandalone(
      window('appointments-list'),
      scope: 'row:list',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('window-card-row:list#appointments-list')),
      findsOneWidget,
    );

    // Its button opens a panel — the same shell, now with a panel in it. On a
    // phone the panel takes the screen, so the list must not sit over it.
    PanelsManager.active([panel]);
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 600)]),
    );
    await tester.pumpAndSettle();

    expect(WindowsManager.open(), isEmpty);
    expect(
      find.byKey(const ValueKey('window-card-row:list#appointments-list')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimizing a window puts it back in the panel list',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final panel = panelWith([window('a'), window('b')]);

    await pumpShell(tester, panel, 1400);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsOneWidget);

    await tester.tap(find.byKey(WK.windowMinimize('b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsNothing);
    expect(find.byKey(WK.windowToggle('b')), findsOneWidget);

    await tester.tap(find.byKey(WK.windowToggle('b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone windows start minimized and open one at a time',
      (tester) async {
    setViewport(tester, const Size(600, 800));
    final panel = panelWith([window('a'), window('b')]);

    await pumpShell(tester, panel, 600);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('window-card-b')),
      findsNothing,
      reason: 'a phone cannot hold a window beside the panel',
    );
    expect(find.text('a'), findsOneWidget,
        reason: 'the first window is inline');

    await tester.tap(find.byKey(WK.windowToggle('b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsOneWidget);

    // The window carries the minimize that puts it away.
    await tester.tap(find.byKey(WK.windowMinimize('b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone a window asked for comes over the panel\'s own',
      (tester) async {
    setViewport(tester, const Size(600, 800));
    final panel = panelWith([window('a'), window('b')]);
    await pumpShell(tester, panel, 600);
    await tester.pumpAndSettle();

    // The panel's own window is the sheet on screen.
    await tester.tap(find.byKey(WK.windowToggle('b')));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);

    // A window asked for from the app — a patient's visits, opened from a visit
    // — comes over it, rather than waiting behind it in the list a phone draws
    // one entry of.
    WindowsManager.showStandalone(window('visits'));
    await tester.pumpAndSettle();
    expect(find.text('visits'), findsOneWidget,
        reason: 'the window the app asked for never reached the screen');
    expect(find.text('b'), findsNothing,
        reason: 'a phone shows one window at a time');

    // Closing it gives the panel's own window the screen back.
    await tester.tap(find.byKey(WK.windowHeaderClose));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
    expect(find.text('visits'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a floating window gives a space-filling body a height',
      (tester) async {
    setViewport(tester, const Size(2400, 1200));
    final panel = panelWith([
      window('a'),
      // An order list: it fills whatever height it is given and scrolls inside
      // itself, so an unbounded height would be an assertion.
      const PanelWindow(
        id: 'list',
        title: 'due',
        icon: WindowsIcons.folder,
        scrollable: false,
        body: Column(
          children: [
            Expanded(child: SizedBox()),
            SizedBox(height: 24),
          ],
        ),
      ),
    ]);

    await pumpShell(tester, panel, 2400);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('window-card-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone a window is as tall as its content, and no taller',
      (tester) async {
    setViewport(tester, const Size(420, 900));
    final panel = panelWith([
      window('a'),
      // A body that fills the room it is given — a list — says how much room it
      // actually wants.
      const PanelWindow(
        id: 'short',
        title: 'due',
        icon: WindowsIcons.folder,
        scrollable: false,
        maxHeight: 220,
        body: Column(
          children: [
            Expanded(child: SizedBox()),
            SizedBox(height: 16),
          ],
        ),
      ),
    ]);

    await pumpShell(tester, panel, 420);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowToggle('short')));
    await tester.pumpAndSettle();

    final rect =
        tester.getRect(find.byKey(const ValueKey('window-card-short')));
    expect(rect.top, lessThan(60), reason: 'it drops in from the top edge');
    expect(
      rect.height,
      lessThanOrEqualTo(221),
      reason: 'the sheet is the height its content asked for',
    );
    expect(
      rect.bottom,
      lessThan(700),
      reason: 'the screen below it stays clear instead of grey space',
    );
  });

  testWidgets('a window comes back visible after being minimized',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final panel = panelWith([window('a'), window('b')]);

    await pumpShell(tester, panel, 1400);
    await tester.pumpAndSettle();

    // Minimized and brought back in the same breath: the window is still
    // folding away when it is asked for again.
    await tester.tap(find.byKey(WK.windowMinimize('b')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(WK.windowToggle('b')));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('window-card-b'));
    expect(card, findsOneWidget);
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(of: card, matching: find.byType(Opacity)),
        )
        .toList();
    expect(
      opacities.map((o) => o.opacity),
      everyElement(1.0),
      reason: 'a window that is open must be visible',
    );
  });

  testWidgets('collapsing the panel puts its windows away too', (tester) async {
    setViewport(tester, const Size(600, 800));
    final panel = panelWith([window('a'), window('b')]);

    await pumpShell(tester, panel, 600);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowToggle('b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsOneWidget);

    // The panel *is* the screen on a phone: collapsing it must not leave a
    // window hovering over an empty main screen.
    PanelsManager.minimize(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsNothing);

    PanelsManager.minimize(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-card-b')), findsOneWidget);
  });

  testWidgets('an open window does not swallow clicks on the screen behind it',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final panel = panelWith([window('a'), window('b')]);

    PanelsManager.active([panel]);
    var pressed = 0;
    await pumpApexoApp(
      tester,
      Stack(
        children: [
          // Where a full-width window area would have covered the app.
          Positioned(
            top: 0,
            left: 0,
            child: FilledButton(
              key: const ValueKey('behind-the-windows'),
              onPressed: () => pressed++,
              child: const Text('behind'),
            ),
          ),
          const WindowsLayer(visible: true, screenWidth: 1400),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('window-card-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('behind-the-windows')));
    await tester.pumpAndSettle();

    expect(
      pressed,
      1,
      reason: 'a floating window is only as big as itself',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide screen the chart keeps its panoramic layout',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'panoramic-patient');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();

    await pumpApexoApp(
      tester,
      const Stack(
        children: [
          WindowsLayer(visible: true, screenWidth: 1600),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<OpgDentalChart>(find.byType(OpgDentalChart));
    expect(
      chart.isCompactArch,
      isFalse,
      reason: 'the card is wide enough for the straight arches',
    );
  });

  testWidgets('a narrow window falls back to the compact arch', (tester) async {
    setViewport(tester, const Size(1000, 800));
    final patient = testPatient(id: 'compact-patient');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();

    await pumpApexoApp(
      tester,
      const Stack(
        children: [
          WindowsLayer(visible: true, screenWidth: 1000),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<OpgDentalChart>(find.byType(OpgDentalChart));
    expect(chart.isCompactArch, isTrue);
  });

  testWidgets('a window that scrolls itself is not put in a scroll view',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    const selfScrolling = PanelWindow(
      id: 'self-scrolling',
      title: 'due',
      icon: WindowsIcons.folder,
      scrollable: false,
      body: Column(
        children: [
          Expanded(child: SizedBox()),
          SizedBox(height: 20),
        ],
      ),
    );

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 400,
        height: 500,
        child: PanelWindowCard(window: selfScrolling, onMinimize: () {}),
      ),
    );

    // A Column with an Expanded child needs a bounded height: the host must
    // give the body one instead of wrapping it in a scroll view.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the orders panel\'s windows scroll themselves', (tester) async {
    final order = testExpense(id: 'orders-window-test');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses([order], 'Orders Supplier', 'orders-supplier'));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().last;
    expect(
      panel.primaryWindow?.id,
      expenseSummaryWindowId,
      reason: 'the panel leads with the supplier\'s figures',
    );
    expect(
      panel.floatingWindows.every((window) => !window.scrollable),
      isTrue,
      reason: 'their bodies hold Expanded children of their own',
    );
  });

  testWidgets('a patient\'s chart is a window that saves with the panel',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'chart-patient');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().last;
    expect(
      panel.windows.map((window) => window.id),
      contains('dentalChart'),
      reason: 'the chart is a window of the panel, not a tab',
    );

    // The window the panel offers edits the panel's own draft.
    final chartWindow =
        panel.windows.firstWhere((window) => window.id == 'dentalChart');
    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 800,
        child: PanelWindowCard(window: chartWindow, onMinimize: () {}),
      ),
    );

    final chart = tester.widget<DentalChartBody>(
      find.byType(DentalChartBody),
    );
    chart.session.teeth['11'] = 'filling';
    await panel.save();
    expect(patients.get(patient.id)!.teeth['11'], 'filling');
  });

  testWidgets('the appointment panel carries its chart window too',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'chart-appointment-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'chart-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointment(appointment);
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().last;
    expect(
      panel.windows.map((window) => window.id),
      contains('dentalChart'),
    );

    final chartWindow =
        panel.windows.firstWhere((window) => window.id == 'dentalChart');
    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 800,
        child: PanelWindowCard(window: chartWindow, onMinimize: () {}),
      ),
    );

    final chart = tester.widget<DentalChartBody>(
      find.byType(DentalChartBody),
    );
    expect(chart.session.type, StateType.treatment);
    chart.session.teeth['36'] = 'crown';
    await panel.save();
    expect(appointments.get(appointment.id)!.teeth['36'], 'crown');
  });

  testWidgets('a chart opened on its own saves, and Close closes it',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    var saves = 0;
    final session = sessionFor(onSave: () async => saves++);
    openStandaloneChart(session);

    await pumpApexoApp(
      tester,
      const Stack(
        children: [
          WindowsLayer(visible: true, screenWidth: 1400),
        ],
      ),
    );

    expect(find.byKey(WK.windowSave), findsOneWidget);
    expect(find.byKey(WK.windowClose), findsOneWidget);

    session.teeth['11'] = 'filling';
    session.changed();
    await tester.pumpAndSettle();
    // The Save button follows the draft, which is sampled rather than pushed.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();
    expect(saves, 1);

    // Nothing to lose: Close just leaves.
    await tester.tap(find.byKey(WK.windowClose));
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), isEmpty);
    expect(find.byKey(const ValueKey('opg-dental-chart')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone a chart opened on its own takes the screen',
      (tester) async {
    setViewport(tester, const Size(600, 800));
    final session = sessionFor(teeth: {'11': 'filling'});
    openStandaloneChart(session);

    await pumpApexoApp(
      tester,
      const Stack(
        children: [
          WindowsLayer(visible: true, screenWidth: 600),
        ],
      ),
    );

    final chart =
        tester.getRect(find.byKey(const ValueKey('opg-dental-chart')));
    expect(chart.left, greaterThanOrEqualTo(0));
    expect(chart.right, lessThanOrEqualTo(600));
    expect(find.byKey(WK.windowSave), findsOneWidget);

    await tester.tap(find.byKey(WK.windowHeaderClose));
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone a tap beside the sheet asks before discarding work',
      (tester) async {
    setViewport(tester, const Size(600, 800));
    const dirty = true;
    WindowsManager.showStandalone(
      window('labwork'),
      onSave: () async {},
      hasChanges: () => dirty,
    );
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 600)]),
    );
    await tester.pumpAndSettle();

    // A tap above the sheet is a dismissal — but the draft is the user's, so it
    // asks the same question the window's own Close asks.
    await tester.tapAt(const Offset(300, 780));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsWidgets);

    await tester.tap(find.text(txt('back')).last);
    await tester.pumpAndSettle();
    expect(
      WindowsManager.open(),
      hasLength(1),
      reason: 'back keeps the window, and the work in it',
    );

    await tester.tapAt(const Offset(300, 780));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt('sure')).last);
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chart opened from a list is clean once it is saved',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    final patient = testPatient(id: 'chart-standalone-patient');
    patients.set(patient);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatientDentalChart(patient));
    await tester.pumpAndSettle();

    await pumpApexoApp(
      tester,
      const Stack(
        children: [
          WindowsLayer(visible: true, screenWidth: 1400),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final session =
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;
    session.teeth['11'] = 'filling';
    session.changed();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();
    expect(patients.get(patient.id)!.teeth['11'], 'filling');

    // Just saved, so Close has nothing to ask about: it closes at once instead
    // of offering to discard work that is already stored.
    await tester.tap(find.byKey(WK.windowClose));
    await tester.pumpAndSettle();
    expect(find.byType(DentalChartBody), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the windows queued behind the one on screen just go',
      (tester) async {
    setViewport(tester, const Size(600, 800));
    openStandaloneChart(sessionFor(id: 'patient:first'));
    openStandaloneChart(sessionFor(id: 'patient:second'));

    await pumpApexoApp(
      tester,
      const Stack(
        children: [
          WindowsLayer(visible: true, screenWidth: 600),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final first =
        find.byKey(const ValueKey('window-card-patient:first#dentalChart'));
    final second =
        find.byKey(const ValueKey('window-card-patient:second#dentalChart'));
    expect(second, findsOneWidget, reason: 'the newest window is the one up');
    expect(first, findsNothing, reason: 'a phone shows one at a time');

    // Both go in the same breath: the one that was never on screen has no exit
    // to animate and must not shrink the tree while it is being built.
    WindowsManager.closeAll();
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), isEmpty);
    expect(first, findsNothing);
    expect(second, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
