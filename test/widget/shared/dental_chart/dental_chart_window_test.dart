@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
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
import 'package:apexo/features/appointments/appointment_labwork_widgets.dart';
import 'package:apexo/features/appointments/appointment_session.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:apexo/features/patients/patient_dental_chart.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/window_actions.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
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
    Widget Function(DentalChartSession)? header,
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
      header: header,
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

  /// A window as tall as a form: taller than the room a window opened low on the
  /// screen used to be given.
  PanelWindow tallWindow(String id, double height) => PanelWindow(
        id: id,
        title: 'patientDetails',
        icon: FluentIcons.medication_admin,
        body: SizedBox(height: height, child: Text(id)),
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
    double width, {
    TextDirection direction = TextDirection.ltr,
    List<Panel> backgroundPanels = const [],
  }) async {
    PanelsManager.active([...backgroundPanels, panel]);
    await pumpApexoApp(
      tester,
      Directionality(
        textDirection: direction,
        child: Stack(
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
          // A row key is `slot/windowId`; a test asks after the window.
          windowIdOfRowKey((builder.key! as ValueKey<String>)
              .value
              .replaceFirst('place-', '')),
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
    expect(find.byKey(WK.btnRemoveLabwork), findsNothing,
        reason: 'there is no order for the footer to take away');

    await tester.tap(find.byKey(WK.btnAddLabwork));
    await tester.pumpAndSettle();
    expect(find.byType(LabWorkEditor), findsOneWidget);
    expect(find.byKey(WK.btnAddLabwork), findsNothing);
    expect(find.byKey(WK.btnRemoveLabwork), findsOneWidget,
        reason: 'starting the order brings the footer\'s remove out at once');

    // The order is part of the visit: saving the window writes it. The band's
    // other window is up beside it, so the Save is named by its window.
    Finder labworkSave() => find.descendant(
          of: find.byKey(WK.windowSaveFooter('labwork')),
          matching: find.byKey(WK.windowSave),
        );
    await tester.tap(labworkSave());
    await tester.pumpAndSettle();
    expect(appointments.get(appointment.id)!.hasLabwork, isTrue);

    // And it can be taken away again — from the window's own footer, beside
    // Save and Close, and only after the standard delete question, like every
    // other delete in the app — and that is a change to save.
    expect(
      find.ancestor(
        of: find.byKey(WK.btnRemoveLabwork),
        matching: find.byType(WindowActions),
      ),
      findsOneWidget,
      reason: 'the remove is the footer\'s, not a glyph inside the order',
    );
    await tester.tap(find.byKey(WK.btnRemoveLabwork));
    await tester.pumpAndSettle();
    expect(find.byType(LabWorkEditor), findsOneWidget,
        reason: 'the order stays until the question is answered');
    await tester.tap(find.text(txt('removeLabwork')).last);
    await tester.pumpAndSettle();
    expect(find.byKey(WK.btnAddLabwork), findsOneWidget);
    expect(find.byKey(WK.btnRemoveLabwork), findsNothing,
        reason: 'the footer offers nothing to remove once the order is gone');
    await tester.tap(labworkSave());
    await tester.pumpAndSettle();
    expect(appointments.get(appointment.id)!.hasLabwork, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final width in [350.0, 960.0]) {
    testWidgets('operative card shares the chart surface at width $width',
        (tester) async {
      setViewport(tester, Size(width, 800));
      final session = sessionFor(id: 'appointment:overlay-test');
      const cardKey = ValueKey('operative-overlay-test');
      final spec = dentalChartWindow(
        session,
        overlayFooter: true,
        footer: const SizedBox(key: cardKey, height: 140),
      );
      expect(spec.footer, isNull);
      expect(spec.scrollable, isFalse);

      await pumpApexoApp(
        tester,
        SizedBox(width: width, height: 620, child: spec.body),
      );
      await tester.pumpAndSettle();

      final chartRect =
          tester.getRect(find.byKey(const ValueKey('opg-dental-chart')));
      final cardRect = tester.getRect(find.byKey(cardKey));
      if (width < kOpgViewportMinWidth) {
        expect(chartRect.overlaps(cardRect), isTrue,
            reason: 'the bubble floats over the chart, not a gray footer');
        final cardPosition = cardRect.topLeft;
        await tester.drag(
            find.byType(SingleChildScrollView).first, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(cardKey)), cardPosition,
            reason: 'scrolling the teeth keeps the bubble pinned');
      } else {
        expect(chartRect.bottom, lessThanOrEqualTo(cardRect.top),
            reason: 'wide charts keep their existing footer layout');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a wide chart with a scope header hugs its content',
      (tester) async {
    setViewport(tester, const Size(1200, 1200));
    final session = sessionFor(
      header: (_) => const SizedBox(height: 40),
    );
    const cardKey = ValueKey('wide-operative-card');
    await pumpApexoApp(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 960,
          child: DentalChartBody(
            session: session,
            overlay: const SizedBox(key: cardKey, height: 140),
          ),
        ),
      ),
    );
    expect(tester.getBottomLeft(find.byType(DentalChartBody)).dy,
        tester.getBottomLeft(find.byKey(cardKey)).dy);
    expect(tester.getSize(find.byType(DentalChartBody)).height, lessThan(1000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow visit floats its operative form over the teeth',
      (tester) async {
    setViewport(tester, const Size(350, 675));
    final patient = testPatient(id: 'overlay-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'overlay-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openAppointment(appointment));
    await tester.pumpAndSettle();
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      await pumpApexoApp(
        tester,
        const Stack(children: [WindowsLayer(visible: true, screenWidth: 350)]),
        theme: theme,
      );
      await tester.pumpAndSettle();

      final chartRect =
          tester.getRect(find.byKey(const ValueKey('opg-dental-chart')));
      final formRect = tester.getRect(
          find.byKey(const ValueKey('visit-operative-overlay-appointment')));
      expect(chartRect.overlaps(formRect), isTrue);
      final bubble = tester.widget<Container>(find.descendant(
        of: find.byKey(const ValueKey('chart-footer-overlay-appointment')),
        matching: find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).borderRadius ==
                BorderRadius.circular(9)),
      ));
      final background = (bubble.decoration! as BoxDecoration).color!;
      expect(background.a, closeTo(0.96, 0.005),
          reason: 'the $theme bubble should be almost opaque');
      expect(find.byKey(WK.chartDeleteVisit), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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

  for (final width in [1400.0, 600.0]) {
    testWidgets(
        'the operative window deletes its visit once it is confirmed '
        '(${width.toInt()}px wide)', (tester) async {
      setViewport(tester, Size(width, 900));
      // A visit whose patient is not on this device: its windows stand on their
      // own, and its operative one carries the visit's delete.
      final appointment = testAppointment(
        id: 'operative-delete-appointment',
        patientID: 'operative-delete-patient-missing',
      );
      appointments.set(appointment);

      await pumpApexoApp(tester, const SizedBox.shrink());
      openAppointmentWindow(appointment, AppointmentWindow.operative);
      await tester.pumpAndSettle();
      await pumpApexoApp(
        tester,
        Stack(children: [WindowsLayer(visible: true, screenWidth: width)]),
      );
      await tester.pumpAndSettle();

      // The window's own footer is where it lives, beside Save and Close.
      final footer = find.ancestor(
        of: find.byKey(WK.operativeDeleteVisit),
        matching: find.byType(WindowActions),
      );
      expect(footer, findsOneWidget);
      expect(
        find.descendant(of: footer, matching: find.byType(WindowCloseButton)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull,
          reason: 'the three actions fit the window at this width');

      await tester.tap(find.byKey(WK.operativeDeleteVisit));
      await tester.pumpAndSettle();
      expect(appointments.get(appointment.id)!.archived, isNot(isTrue),
          reason: 'nothing is deleted until the question is answered');

      await tester.tap(find.text(txt('deleteVisit')).last);
      await tester.pumpAndSettle();
      expect(appointments.get(appointment.id)!.archived, isTrue);
      expect(WindowsManager.open(), isEmpty,
          reason: 'the visit it showed is gone, and its window with it');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a visit beside its patient keeps delete visit in the chart window footer',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    // The operative record lives at the foot of the visit's chart beside a
    // patient, so that window's footer is the one that carries its delete.
    final patient = testPatient(id: 'chart-delete-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'chart-delete-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openAppointment(appointment));
    await tester.pumpAndSettle();
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(panel.attached?.itemId, appointment.id);

    expect(
      find.ancestor(
        of: find.byKey(WK.chartDeleteVisit),
        matching: find.byType(WindowActions),
      ),
      findsOneWidget,
      reason: 'the delete sits with the chart window\'s Save and Close',
    );
    expect(find.byKey(WK.operativeDeleteVisit), findsNothing,
        reason: 'the visit is beside its patient, not in an operative window');

    await tester.tap(find.byKey(WK.chartDeleteVisit));
    await tester.pumpAndSettle();
    expect(appointments.get(appointment.id)!.archived, isNot(isTrue));
    await tester.tap(find.text(txt('deleteVisit')).last);
    await tester.pumpAndSettle();

    expect(appointments.get(appointment.id)!.archived, isTrue);
    expect(panel.attached, isNull,
        reason: 'the visit it deleted leaves the panel it was carried by');
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

  testWidgets('a patient panel opens its chart, and its list sits beside it',
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
      reason: 'a record opens on its workspace',
    );
    expect(
      workspace.isOpen(PatientWindow.appointments.id),
      isFalse,
      reason: 'the list is one button in the header, not a first pick',
    );
    // The header's button opens it — beside the chart, in the same row.
    await tester.tap(
        find.byKey(WK.workspaceWindowToggle(PatientWindow.appointments.id)));
    await tester.pumpAndSettle();
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
    // The visit is carried by its patient's panel — the panel the list belonged
    // to (plan §0).
    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id);
    expect(panel.attached!.itemId, appointment.id);
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

    // "Add appointment" in the list's own footer asks for the visit in a sheet
    // first, so the list it was started from stays behind it until the visit
    // exists.
    await tester.tap(find.byIcon(FluentIcons.add_event));
    await tester.pumpAndSettle();
    expect(find.byKey(WK.fieldNewAppointmentPatient), findsOneWidget);
    expect(WindowsManager.open(), hasLength(1));

    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();

    // Now the list was a way in: it makes way for the visit, which is stored
    // rather than a draft.
    expect(WindowsManager.open(), isEmpty);
    final panel = PanelsManager.active().single;
    expect(panel.isNew, isFalse,
        reason: 'the sheet stored the visit before its record opened');
    expect(
      appointments.docs.values.where((a) => a.patientID == patient.id),
      hasLength(1),
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
    // Wide enough for the visit's chart and one attachment beside it, so both
    // stay in the row and the question is only which is in front.
    setViewport(tester, const Size(1920, 1080));
    final patient = testPatient(id: 'raise-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'raise-appointment',
      patientID: patient.id,
    );
    appointments.set(appointment);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(appointment, AppointmentWindow.dentalChart);
    await openAppointment(appointment, AppointmentWindow.gallery);
    await pumpApexoApp(
        tester,
        const Stack(
            children: [WindowsLayer(visible: true, screenWidth: 1920)]));
    await tester.pumpAndSettle();

    List<String> names() =>
        stackingOrder(tester).map((key) => key.split('#').last).toList();
    expect(names(), containsAll(['dentalChart', 'gallery']));
    expect(names().last, 'gallery',
        reason: 'the window asked for last is the one in front');

    // Asking for the chart again must not rebuild it — and must not leave it
    // underneath the window opened after it.
    await openAppointment(appointment, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    expect(names().last, 'dentalChart');
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
    // A visit's windows are the panel's, not the app's: a window that appears at
    // the tap is one that stands on its own. A visit whose patient the account
    // may not see is the case that still does (plan §0.1).
    login.savedPermissions = List.of(Perm.full)..[Perm.patients] = 1;
    addTearDown(() => login.savedPermissions = Perm.full);

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

  testWidgets('a window opened from the foot of the screen is opened whole',
      (tester) async {
    setViewport(tester, const Size(1400, 900));
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 1400)]),
    );
    final card = find.byKey(const ValueKey('window-card-row:low#low'));

    // A row's button near the bottom edge of the screen.
    WindowOrigin.record(const Offset(300, 880));
    WindowsManager.showStandalone(tallWindow('low', 640), scope: 'row:low');
    await tester.pumpAndSettle();

    final rect = tester.getRect(card);
    expect(
      rect.bottom,
      lessThanOrEqualTo(900),
      reason: 'no part of it hangs off the screen',
    );
    expect(
      rect.height,
      greaterThan(640),
      reason:
          'it is as tall as it asked to be, not shortened to the room a tap '
          'near the bottom used to leave — which opened it scrolled',
    );
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

  testWidgets('the chart is washed in the colour of the record it edits',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'tinted-chart-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'tinted-chart-visit', patientID: patient.id);
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    Color? tint() =>
        tester.widget<OpgDentalChart>(find.byType(OpgDentalChart)).tint;

    /// The wash the arches sit in — the chart's background, never the teeth.
    Color wash() {
      final decoration = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(OpgDentalChart),
            matching: find.byType(Container),
          ))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((decoration) => decoration.gradient != null);
      return decoration.gradient!.colors.first;
    }

    expect(tint(), PanelAccents.patient,
        reason: 'the plan is the patient record, and blue is its colour');
    final patientWash = wash();

    await tester.tap(find.byKey(ValueKey('scope-appointment:${visit.id}')));
    await tester.pumpAndSettle();

    expect(tint(), PanelAccents.appointment,
        reason: 'the visit is the appointment, and violet is its colour');
    final visitWash = wash();

    expect(visitWash, isNot(patientWash),
        reason: 'the two scopes cannot look like the same chart');
    expect(
      visitWash.r,
      greaterThan(patientWash.r),
      reason: 'violet is the redder of the two washes',
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('the visit\'s chart is one of the visit\'s windows, not a panel',
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
    unawaited(openAppointment(appointment));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id,
        reason: 'the patient is the panel; the visit is carried beside it');
    expect(
      panel.attached!.windows.map((window) => window.id),
      contains('dentalChart'),
    );

    final chartWindow = panel.attached!.windows
        .firstWhere((window) => window.id == 'dentalChart');
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
    expect(chart.session.type, StateType.treatment,
        reason: 'it writes the visit\'s treatments, not the patient\'s state');
    chart.session.teeth['36'] = 'crown';
    await panel.attached!.save();
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

  testWidgets(
      'the scope bar lists the plan and all visits newest-first and swaps charts while keeping the patient panel open',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'scope-patient', name: 'Nadia Hassan');
    patients.set(patient);
    final febVisit = testAppointment(
      id: 'scope-visit-feb',
      patientID: patient.id,
      date: DateTime(2026, 2, 4, 10),
    );
    final marVisit = testAppointment(
      id: 'scope-visit-mar',
      patientID: patient.id,
      date: DateTime(2026, 3, 12, 14),
    );
    appointments.setAll([febVisit, marVisit]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    expect(find.byType(VisitScopeBar), findsOneWidget);
    expect(
      tester.getRect(find.byType(VisitScopeBar)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(OpgDentalChart)).top),
      reason: 'the scope bar sits above the arches',
    );
    expect(
      find.byKey(const ValueKey('scope-timeline-track')),
      findsOneWidget,
      reason: 'visits are drawn as dots on a horizontal timeline',
    );

    final febDot = find.byKey(ValueKey('scope-appointment:${febVisit.id}'));
    final marDot = find.byKey(ValueKey('scope-appointment:${marVisit.id}'));
    expect(febDot, findsOneWidget);
    expect(marDot, findsOneWidget);
    expect(
      tester.getCenter(febDot).dx,
      lessThan(tester.getCenter(marDot).dx),
      reason:
          'the first dot on the timeline is the first appointment and the last dot is the last appointment',
    );
    expect(
      find.descendant(
        of: find.byType(VisitScopeBar),
        matching: find.text(DF.allNumbers(febVisit.date)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(VisitScopeBar),
        matching: find.text(DF.allNumbers(marVisit.date)),
      ),
      findsOneWidget,
    );

    DentalChartSession activeSession() =>
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;

    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'patient:${patient.id}');
    expect(activeSession().titleKey, kDentalChartTitleKey);

    // Choosing a visit when clean swaps the chart in place without duplicating
    // it and without moving the patient panel.
    await tester.tap(find.byKey(ValueKey('scope-appointment:${marVisit.id}')));
    await tester.pumpAndSettle();

    expect(find.text(txt('sureClosePanel')), findsNothing);
    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'appointment:${marVisit.id}');
    expect(activeSession().titleKey, kTreatmentsTitleKey);
    expect(PanelsManager.active().single.itemId, patient.id);

    // Each chart keeps its own Save and writes its own record.
    activeSession().teeth['36'] = 'crown';
    activeSession().changed();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();
    expect(appointments.get(marVisit.id)!.teeth['36'], 'crown');

    // Swapping to another visit replaces the chart again.
    await tester.tap(find.byKey(ValueKey('scope-appointment:${febVisit.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'appointment:${febVisit.id}');
    expect(PanelsManager.active().single.itemId, patient.id);

    // Choosing the plan swaps back to the patient's chart.
    await tester.tap(find.byKey(ValueKey('scope-patient:${patient.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'patient:${patient.id}');
    expect(activeSession().titleKey, kDentalChartTitleKey);
    expect(WindowsManager.open(), isEmpty);
    expect(PanelsManager.active().single.itemId, patient.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing another scope asks when dirty and swaps on confirm',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient =
        testPatient(id: 'dirty-scope-patient', name: 'Nadia Hassan');
    patients.set(patient);
    final visit = testAppointment(
      id: 'dirty-scope-visit',
      patientID: patient.id,
      date: DateTime(2026, 3, 12, 14),
    );
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    DentalChartSession activeSession() =>
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;

    activeSession().teeth['11'] = 'caries';
    activeSession().changed();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('scope-appointment:${visit.id}')));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsWidgets);
    expect(activeSession().id, 'patient:${patient.id}');

    // Backing out keeps the current chart and its unsaved work.
    await tester.tap(find.text(txt('back')).last);
    await tester.pumpAndSettle();
    expect(activeSession().id, 'patient:${patient.id}');
    expect(activeSession().teeth['11'], 'caries');

    // Confirming discards the unsaved work and swaps to the visit's chart.
    await tester.tap(find.byKey(ValueKey('scope-appointment:${visit.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt('sure')).last);
    await tester.pumpAndSettle();

    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'appointment:${visit.id}');
    expect(PanelsManager.active().single.itemId, patient.id);

    // Dirty on the visit's chart also survives a switch back to the plan:
    // pressing the plan closes the visit from the panel and keeps its draft, so
    // there is nothing to ask and nothing to discard.
    activeSession().teeth['26'] = 'filling';
    activeSession().changed();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('scope-patient:${patient.id}')));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing,
        reason: 'closing the visit keeps its draft; it is not a discard');
    expect(find.byKey(WK.visitBand), findsNothing);
    expect(PanelsManager.active().single.attached, isNull);
    final retained = PanelsManager.active()
        .single
        .owned
        .whereType<AppointmentSession>()
        .single;
    expect(retained.chart.teeth['26'], 'filling',
        reason: 'the visit draft is still owned by its panel');

    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'patient:${patient.id}');
    expect(
      activeSession().teeth,
      isEmpty,
      reason: 'the discarded plan edit does not reappear on return',
    );

    // Reopening the visit restores the same draft, dirty mark and all.
    await tester.tap(find.byKey(ValueKey('scope-appointment:${visit.id}')));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing);
    expect(activeSession().id, 'appointment:${visit.id}');
    expect(activeSession().teeth['26'], 'filling');
    expect(PanelsManager.active().single.itemId, patient.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'moving between visits keeps the chart and operative edits of the one left',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient =
        testPatient(id: 'carried-draft-patient', name: 'Nadia Hassan');
    patients.set(patient);
    final first = testAppointment(
      id: 'carried-draft-first',
      patientID: patient.id,
      date: DateTime(2026, 3, 12, 14),
    );
    final second = testAppointment(
      id: 'carried-draft-second',
      patientID: patient.id,
      date: DateTime(2026, 4, 2, 10),
    );
    appointments.setAll([first, second]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    DentalChartSession activeSession() =>
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;

    await tester.tap(find.byKey(ValueKey('scope-appointment:${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing);
    expect(activeSession().id, 'appointment:${first.id}');

    // Both halves of the visit's surface hold work: the teeth in its chart and
    // the post-op record under it.
    final panel = PanelsManager.active().single;
    final session = panel.owned
        .whereType<AppointmentSession>()
        .firstWhere((owned) => owned.item.id == first.id);
    session.chart.teeth['11'] = 'caries';
    session.chart.changed();
    session.item.postOpNotes = 'Access and canal prep';
    session.refreshDirty();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('scope-appointment:${second.id}')));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing,
        reason: 'the visit left behind keeps its draft; nothing is discarded');
    expect(activeSession().id, 'appointment:${second.id}');
    expect(session.chart.teeth['11'], 'caries');
    expect(session.item.postOpNotes, 'Access and canal prep');

    // Coming back is the same draft, dirty mark and all.
    await tester.tap(find.byKey(ValueKey('scope-appointment:${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing);
    expect(activeSession(), same(session.chart));
    expect(activeSession().teeth['11'], 'caries');
    expect(session.hasPendingEdits, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tooth history opens the visit chart while Open record reaches the full visit',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient =
        testPatient(id: 'history-scope-patient', name: 'Nadia Hassan');
    patients.set(patient);
    final visit = testAppointment(
      id: 'history-scope-visit',
      patientID: patient.id,
      date: DateTime(2026, 3, 12, 14),
      teeth: {'16': 'rCT'},
    );
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.tooth('16', selected: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('open-appointment-${visit.id}')));
    await tester.pumpAndSettle();

    DentalChartSession activeSession() =>
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;

    expect(find.byType(DentalChartBody), findsOneWidget);
    expect(activeSession().id, 'appointment:${visit.id}');
    expect(
      PanelsManager.active().single.itemId,
      patient.id,
      reason:
          'history opens the visit chart rather than replacing the patient panel',
    );

    // The record the chart belongs to is the panel already on screen — there is
    // nowhere further to go, and no second window to go there in (plan §5.2 #24).
    expect(WindowsManager.open(), isEmpty);
    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id);
    expect(panel.attached!.itemId, visit.id);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
        'many visits stay on one row and reveal the selection in $direction',
        (tester) async {
      setViewport(tester, const Size(600, 800));
      final patient = testPatient(id: 'crowded-patient');
      patients.set(patient);
      final visits = List.generate(
          40,
          (i) => testAppointment(
              id: 'crowded-$i',
              patientID: patient.id,
              date: DateTime(2026, 1, 40 - i)));
      appointments.setAll(visits);
      final oldest = visits.last;
      await pumpApexoApp(
          tester,
          Directionality(
            textDirection: direction,
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 320,
                  child: VisitScopeBar(
                      patient: patient,
                      session: appointmentDentalChart(oldest),
                      currentAppointment: oldest),
                )),
          ));
      await tester.pumpAndSettle();

      final bar = find.byType(VisitScopeBar);
      final strip = find.byKey(const ValueKey('scope-visit-scroll'));
      final plan = find.byKey(ValueKey('scope-patient:${patient.id}'));
      final selected = find.byKey(ValueKey('scope-appointment:${oldest.id}'));
      final scroll = tester.widget<SingleChildScrollView>(strip).controller!;
      expect(tester.getSize(bar).height, 40);
      expect(scroll.offset, greaterThan(0));
      final viewport = tester.getRect(strip);
      final selectedRect = tester.getRect(selected);
      expect(selectedRect.center.dx,
          inInclusiveRange(viewport.left, viewport.right));
      final planRect = tester.getRect(plan);
      final offset = scroll.offset;
      await tester.sendEventToBinding(PointerScrollEvent(
          position: viewport.center, scrollDelta: const Offset(0, -100)));
      await tester.pumpAndSettle();
      expect(scroll.offset, lessThan(offset),
          reason: 'mouse wheel scrolls the visit strip');
      expect(tester.getRect(plan), planRect, reason: 'the plan stays pinned');
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets(
        'an interval says its duration once its segment can hold it in '
        '$direction', (tester) async {
      setViewport(tester, const Size(600, 800));
      final patient = testPatient(id: 'interval-patient');
      patients.set(patient);
      // Quarterly visits: on a bar this wide each segment is about fifty
      // pixels — room for "3m", which the old fixed 68 px rule refused to draw.
      final visits = List.generate(
          5,
          (i) => testAppointment(
              id: 'interval-$i',
              patientID: patient.id,
              date: DateTime(2025, 1, 1).add(Duration(days: 90 * i))));
      appointments.setAll(visits);
      await pumpApexoApp(
          tester,
          Directionality(
            textDirection: direction,
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 480,
                  child: VisitScopeBar(
                      patient: patient,
                      session: appointmentDentalChart(visits.first),
                      currentAppointment: visits.first),
                )),
          ));
      await tester.pumpAndSettle();

      final track =
          tester.getSize(find.byKey(const ValueKey('scope-timeline-track')));
      final layout =
          computeTimelineLayout(visits: visits, viewportWidth: track.width);
      final gaps = [
        for (var i = 0; i < visits.length - 1; i++)
          layout.positions[i + 1] - layout.positions[i],
      ];
      expect(gaps.any((gap) => gap < 68), isTrue,
          reason: 'the segments are narrower than the old fixed label width');
      expect(find.text('3m'), findsWidgets,
          reason: 'a segment that holds "3m" says it');
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('switching visits slides scopes in the same slot in $direction',
        (tester) async {
      setViewport(tester, const Size(1600, 1000));
      final patient = testPatient(id: 'arrow-patient');
      patients.set(patient);
      final older = testAppointment(
          id: 'arrow-older', patientID: patient.id, date: DateTime(2026, 1, 1));
      final newer = testAppointment(
          id: 'arrow-newer', patientID: patient.id, date: DateTime(2026, 2, 1));
      appointments.setAll([older, newer]);
      await pumpApexoApp(tester, const SizedBox.shrink());
      unawaited(openPatient(patient));
      await tester.pumpAndSettle();
      await pumpShell(tester, PanelsManager.active().single, 1600,
          direction: direction);
      await tester.pumpAndSettle();

      DentalChartSession session() =>
          tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;
      final olderDot = find.byKey(ValueKey('scope-appointment:${older.id}'));
      final newerDot = find.byKey(ValueKey('scope-appointment:${newer.id}'));

      await tester.tap(newerDot);
      await tester.pumpAndSettle();
      expect(session().id, 'appointment:${newer.id}');

      final barRect = tester.getRect(find.byType(VisitScopeBar));
      final saveRect = tester.getRect(find.byKey(WK.windowSave));
      final windowRect =
          tester.getRect(find.byKey(const ValueKey('window-card-dentalChart')));
      await tester.tap(olderDot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(DentalChartBody), findsOneWidget);
      final slide = tester.widget<FractionalTranslation>(
          find.byKey(const ValueKey('dental-chart-scope-slide')));
      expect(slide.translation.dx,
          direction == TextDirection.rtl ? lessThan(0) : greaterThan(0));
      expect(tester.getRect(find.byType(VisitScopeBar)), barRect);
      expect(tester.getRect(find.byKey(WK.windowSave)), saveRect);
      expect(
          tester.getRect(find.byKey(const ValueKey('window-card-dentalChart'))),
          windowRect);
      expect(
          find.ancestor(
              of: find.byType(VisitScopeBar),
              matching: find.byType(FractionalTranslation)),
          findsNothing);
      for (final opacity in tester.widgetList<Opacity>(find.ancestor(
          of: find.byType(VisitScopeBar), matching: find.byType(Opacity)))) {
        expect(opacity.opacity, 1,
            reason: 'only the chart fades, never its controls');
      }
      await tester.pumpAndSettle();
      expect(session().id, 'appointment:${older.id}');

      await tester.tap(newerDot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final incomingSlide = tester.widget<FractionalTranslation>(
          find.byKey(const ValueKey('dental-chart-scope-slide')));
      expect(incomingSlide.translation.dx,
          direction == TextDirection.rtl ? greaterThan(0) : lessThan(0));
      await tester.pumpAndSettle();
      expect(session().id, 'appointment:${newer.id}');
      expect(PanelsManager.active().single.itemId, patient.id);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.tap(olderDot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final reducedSlide = tester.widget<FractionalTranslation>(
          find.byKey(const ValueKey('dental-chart-scope-slide')));
      expect(reducedSlide.translation, Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byType(DentalChartBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'dirty history navigation and the dock cannot silently lose chart edits',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'guard-patient');
    patients.set(patient);
    final visit = testAppointment(id: 'guard-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();
    bContext = tester.element(find.byType(VisitScopeBar));
    DentalChartSession session() =>
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;
    final plan = session();
    plan.teeth['11'] = 'caries';
    plan.changed();
    plan.onOpenAppointment!(visit.id);
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsWidgets);
    await tester.tap(find.text(txt('back')).last);
    await tester.pumpAndSettle();
    expect(session(), same(plan));
    expect(plan.teeth['11'], 'caries');

    plan.onOpenAppointment!(visit.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt('sure')).last);
    await tester.pumpAndSettle();
    expect(session().id, 'appointment:${visit.id}');
    expect(plan.teeth, isEmpty);
    final visitSession = session();
    visitSession.teeth['26'] = 'filling';
    visitSession.changed();
    bContext = tester.element(find.byType(VisitScopeBar));
    final panel = PanelsManager.active().single;
    // Putting the chart away is a minimize, not a discard: the draft stays in the
    // visit's session, so the band's chip closes it without a question — and
    // nothing typed is lost (plan §4.6).
    await tester.tap(find.byKey(WK.windowMinimize(kDentalChartWindowId)));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing);
    expect(panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
        isFalse);
    expect(visitSession.teeth['26'], 'filling');

    // And asking for it again is the same draft, not a re-read of the record.
    panel.workspace.show(kDentalChartWindowId, slot: kAttachedSlot);
    await tester.pumpAndSettle();
    expect(session(), same(visitSession));
    expect(session().teeth['26'], 'filling');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the visit chart is the visit session\'s draft, and its Save writes the visit',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'shared-draft-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'shared-draft-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id,
        reason: 'the visit is carried by the patient, not a panel of its own');
    final chart = panelDentalChart('appointment:${visit.id}')!;
    expect(chart, same((panel.attached! as AppointmentSession).chart),
        reason: 'one draft per visit: the chart belongs to the session');
    expect(panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
        isTrue);

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();
    chart.teeth['36'] = 'crown';
    chart.changed();
    await tester.tap(find.byKey(WK.windowSave));
    await tester.pumpAndSettle();

    expect(appointments.get(visit.id)!.teeth['36'], 'crown');
    expect(chart.hasChanges, isFalse);
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visit band tools open the visit\'s editors in its slot',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'tools-patient');
    patients.set(patient);
    final visit = testAppointment(id: 'tools-visit', patientID: patient.id);
    final otherVisit = testAppointment(
        id: 'tools-other-visit',
        patientID: patient.id,
        date: DateTime(2026, 3, 12));
    appointments.setAll([visit, otherVisit]);
    await pumpApexoApp(tester, const SizedBox.shrink());
    // The visit, opened on its chart, beside its patient.
    unawaited(openAppointment(visit, AppointmentWindow.dentalChart));
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    expect(panel.itemId, patient.id);
    expect(panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
        isTrue);

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();
    // The visit's post-op record is part of the chart now, not a window: its
    // fields are under the teeth, on the chart's own frame.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('window-card-$kDentalChartWindowId')),
        matching: find.byKey(WK.fieldAppointmentPostOpNotes),
      ),
      findsOneWidget,
      reason: 'the operative details live at the foot of the chart',
    );
    // The band's dock carries one tool: the operative record, whose fields are
    // pinned to the foot of the chart.
    expect(find.byKey(WK.visitBandWindow('operative')), findsOneWidget);
    for (final id in ['labwork', 'gallery']) {
      expect(find.byKey(WK.visitBandWindow(id)), findsNothing,
          reason: 'labwork and photos are not tools in the band\'s dock');
    }
    // They hang off the band as attachments — the same tray the patient panel
    // draws under itself — and off the post-op card inside the visit's chart.
    Finder bandChip(String id) => find.descendant(
          of: find.byKey(WK.visitBandAttachments),
          matching: find.byKey(
              WK.attachmentToggle(id, owner: PanelWindow.bandAttachment)),
        );
    Finder chartChip(String id) => find.descendant(
          of: find.byKey(WK.visitChartAttachments),
          matching:
              find.byKey(WK.attachmentToggle(id, owner: kDentalChartWindowId)),
        );
    for (final id in ['labwork', 'gallery']) {
      expect(bandChip(id), findsOneWidget,
          reason: 'the band offers $id beside the visit it belongs to');
      expect(chartChip(id), findsOneWidget,
          reason: 'the post-op card offers $id too');
    }
    for (final id in ['labwork', 'gallery']) {
      // The chart takes the row alone below 1902: opening one of the visit's
      // editors from its band puts the chart back in its dock and the editor on
      // screen (plan §4.3). The band is the control that stays available.
      panel.workspace.show(kDentalChartWindowId, slot: kAttachedSlot);
      await tester.pumpAndSettle();
      expect(panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
          isTrue);
      // One from the card inside the chart, one from the band's tray: both say
      // the same thing about the same window.
      final chip = id == 'labwork' ? chartChip(id) : bandChip(id);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(panel.workspace.isOpen(id, slot: kAttachedSlot), isTrue);
      expect(panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
          isFalse,
          reason: 'one chart takes the row; a tool takes it from the chart');
      expect(WindowsManager.open(), isEmpty,
          reason: 'a visit window is the panel\'s, not the app\'s');
      expect(PanelsManager.active().single, same(panel));
    }
    // Operative details are not a window of their own: their band button opens
    // the chart whose foot they are pinned to.
    await tester.tap(find.byKey(WK.visitBandWindow('operative')));
    await tester.pumpAndSettle();
    expect(panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
        isTrue);
    expect(find.byKey(WK.fieldAppointmentPostOpNotes), findsOneWidget);
    // Selecting the other visit makes it the one in the row — the same call the
    // Visits list makes (plan §4.8).
    await selectVisit(patient.id, otherVisit.id, focus: kDentalChartWindowId);
    await tester.pumpAndSettle();
    expect((panel.attached! as AppointmentSession).item.id, otherVisit.id);
    expect(PanelsManager.active().single, same(panel));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every row of the visit band starts on one edge', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'band-edge-patient');
    patients.set(patient);
    final visit = testAppointment(id: 'band-edge-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    Rect rectOf(Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return box.localToGlobal(Offset.zero) & box.size;
    }

    // The date opens its row; the operators, the note and the operative
    // details button open theirs; the tray opens its own. Every one of them
    // starts where the others do, and the glyphs that name them live inside
    // their boxes rather than in a gutter ahead of them.
    final date = rectOf(find.byKey(WK.fieldAppointmentDate));
    final operators = rectOf(find.byKey(WK.fieldOperators));
    final notes = rectOf(find.byKey(WK.fieldAppointmentPreOpNotes));
    final dock = rectOf(find.byKey(WK.visitBandWindow('operative')));
    final labwork = rectOf(find.byKey(
        WK.attachmentToggle('labwork', owner: PanelWindow.bandAttachment)));
    for (final entry in {
      'operators': operators,
      'pre-op notes': notes,
      'operative details': dock,
      'labwork': labwork,
    }.entries) {
      expect(entry.value.left, closeTo(date.left, 0.01),
          reason: '${entry.key} starts on the edge the date starts on');
    }
    // The date takes the room the time and the duration leave it: a date that
    // fits is never ellipsized for want of width the row has to spare.
    expect(date.width, greaterThan(118),
        reason: 'the date is not pinned to a width smaller than the row');
    expect(
      rectOf(find.byKey(WK.fieldAppointmentTime)).left,
      greaterThan(date.right),
    );
    // One height for the fields of the form, so the band reads as one set.
    expect(operators.height, date.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chart and its post-op record share one draft and one save',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'borrowed-tools-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'borrowed-tools-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    final session = panel.attached! as AppointmentSession;
    session.chart.teeth['26'] = 'crown';
    session.chart.changed();
    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    // The note is typed in the record the chart carries; the tooth was marked on
    // the chart. Both are the same draft.
    await tester.enterText(
      find.byKey(WK.fieldAppointmentPostOpNotes),
      'crown seated',
    );
    await tester.pumpAndSettle();
    expect(session.item.postOpNotes, 'crown seated');

    // One window, one Save, one write: the chart's Save writes both.
    await tester.tap(find.descendant(
      of: find.byKey(WK.windowSaveFooter(kDentalChartWindowId)),
      matching: find.byKey(WK.windowSave),
    ));
    await tester.pumpAndSettle();
    expect(appointments.get(visit.id)!.teeth['26'], 'crown');
    expect(appointments.get(visit.id)!.postOpNotes, 'crown seated');
    expect(session.hasPendingEdits, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone scope changes animate only teeth and keep controls usable',
      (tester) async {
    setViewport(tester, const Size(600, 900));
    final patient = testPatient(id: 'phone-scope-patient');
    patients.set(patient);
    final older = testAppointment(
        id: 'phone-scope-older',
        patientID: patient.id,
        date: DateTime(2026, 1, 1));
    final newer = testAppointment(
        id: 'phone-scope-newer',
        patientID: patient.id,
        date: DateTime(2026, 2, 1));
    appointments.setAll([older, newer]);
    await openAppointmentDentalChart(newer);
    await pumpApexoApp(tester,
        const Stack(children: [WindowsLayer(visible: true, screenWidth: 600)]));
    await tester.pumpAndSettle();
    final barRect = tester.getRect(find.byType(VisitScopeBar));
    final saveRect = tester.getRect(find.byKey(WK.windowSave));
    final olderDot = find.byKey(ValueKey('scope-appointment:${older.id}'));
    final newerDot = find.byKey(ValueKey('scope-appointment:${newer.id}'));
    await tester.tap(olderDot);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(find.byType(VisitScopeBar)), barRect);
    expect(tester.getRect(find.byKey(WK.windowSave)), saveRect);
    for (final translation in tester.widgetList<FractionalTranslation>(
        find.ancestor(
            of: find.byType(VisitScopeBar),
            matching: find.byType(FractionalTranslation)))) {
      expect(translation.translation, Offset.zero);
    }
    expect(
        tester
            .widget<FractionalTranslation>(
                find.byKey(const ValueKey('dental-chart-scope-slide')))
            .translation
            .dx,
        greaterThan(0));
    await tester.tap(newerDot);
    await tester.pumpAndSettle();
    expect(
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session.id,
        'appointment:${newer.id}');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the visit chart offers a way to start another visit for the same patient',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'add-visit-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'add-visit-anchor', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    // One button beside the visits it will join: no trip to the calendar, and the
    // patient is already known. It pairs the plus with the shorter of "Add" and
    // "New" in every locale, now that the arrows no longer take that space.
    expect(find.byKey(WK.chartAddAppointment), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(WK.chartAddAppointment),
            matching: find.text(txt('new'))),
        findsWidgets,
        reason: 'the button carries a word, not just a plus icon');
    expect(
        find.descendant(
            of: find.byKey(WK.chartAddAppointment),
            matching: find.byIcon(FluentIcons.add)),
        findsOneWidget,
        reason: 'the plus still says what the word means');
    expect(find.byKey(const ValueKey('scope-newer')), findsNothing);
    expect(find.byKey(const ValueKey('scope-older')), findsNothing);
    await tester.tap(find.byKey(WK.chartAddAppointment));
    await tester.pumpAndSettle();
    expect(find.byType(NewAppointmentDialog), findsOneWidget,
        reason:
            'the button starts a visit for the patient whose chart is open');
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
        'a patient with no visits gets the whole add appointment label in $direction',
        (tester) async {
      setViewport(tester, const Size(600, 800));
      final patient = testPatient(id: 'first-visit-patient');
      patients.set(patient);
      await pumpApexoApp(
          tester,
          Directionality(
            textDirection: direction,
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 320,
                  child: VisitScopeBar(
                      patient: patient, session: patientDentalChart(patient)),
                )),
          ));
      await tester.pumpAndSettle();

      // No visits means no timeline eating the width, so the button can afford
      // its whole name instead of the short "new" it uses beside the timeline.
      expect(find.byKey(const ValueKey('scope-visit-scroll')), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(WK.chartAddAppointment),
              matching: find.text(txt('addAppointment'))),
          findsWidgets);
      expect(
          find.descendant(
              of: find.byKey(WK.chartAddAppointment),
              matching: find.byIcon(FluentIcons.add)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the visit chart title opens the patient\'s whole list of visits',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'all-visits-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'all-visits-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    expect(find.byKey(WK.chartAllAppointments), findsOneWidget,
        reason: 'the chart title carries the list, beside minimize');

    await tester.tap(find.byKey(WK.chartAllAppointments));
    await tester.pumpAndSettle();
    // The list is the patient's own window, opened in the patient's row: the
    // title leads to the record's whole history, not to one visit of it.
    expect(
      panel.workspace.isOpen(PatientWindow.appointments.id),
      isTrue,
      reason: 'the chart title leads to the list of every visit',
    );
    expect(
      panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
      isFalse,
      reason: 'at this width the list and the chart do not both fit, so the '
          'list has the row and the chart steps aside, keeping its draft',
    );
    expect(WindowsManager.open(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching scope replaces the band and the post-op record',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'scope-fields-patient');
    patients.set(patient);
    final first = testAppointment(
      id: 'scope-fields-first',
      patientID: patient.id,
      date: DateTime(2026, 6, 1, 10, 0),
      preOpNotes: 'first pre-op',
      postOpNotes: 'first post-op',
      price: 10,
    );
    final second = testAppointment(
      id: 'scope-fields-second',
      patientID: patient.id,
      date: DateTime(2026, 6, 2, 11, 30),
      preOpNotes: 'second pre-op',
      postOpNotes: 'second post-op',
      price: 20,
    );
    appointments.setAll([first, second]);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(first, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    String? bandNotes() => tester
        .widget<LiveTranscribingTextField>(
            find.byKey(WK.fieldAppointmentPreOpNotes))
        .controller
        ?.text;
    String? postOpNotes() => tester
        .widget<LiveTranscribingTextField>(
            find.byKey(WK.fieldAppointmentPostOpNotes))
        .controller
        ?.text;
    DateTime bandDate() => tester
        .state<DateTimePickerState>(find.byKey(WK.fieldAppointmentDate))
        .value;
    DateTime bandTime() => tester
        .state<DateTimePickerState>(find.byKey(WK.fieldAppointmentTime))
        .value;

    expect(bandDate(), first.date);
    expect(bandTime(), first.date);
    expect(bandNotes(), 'first pre-op');
    expect(postOpNotes(), 'first post-op');

    // Exactly what the scope bar's visit tab does: select the other visit's
    // chart. The band and the post-op record under the chart must be that
    // visit's from the first frame, not the previous visit's fields behind a
    // new title.
    await selectVisit(patient.id, second.id, focus: kDentalChartWindowId);
    await tester.pumpAndSettle();

    expect(bandDate(), second.date,
        reason: 'the band date belongs to the visit whose title is shown');
    expect(bandTime(), second.date,
        reason: 'the time follows the same visit as the date');
    expect(bandNotes(), 'second pre-op',
        reason: 'the band form is a view of the selected visit');
    expect(postOpNotes(), 'second post-op',
        reason: 'the chart footer is a view of the selected visit');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'both patient workspaces stay visible; the plan leaves the visit and locks '
      'the patient fields', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'plan-button-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'plan-button-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    // The two workspaces are always drawn, one active and one inactive; the
    // visit's chart is the chart on screen, so the chart button drives it.
    expect(find.byKey(WK.workspaceWindowToggle('dentalChart')), findsOneWidget);
    expect(
        find.byKey(WK.workspaceWindowToggle('appointments')), findsOneWidget);
    expect(
      tester.widget(find.byKey(WK.workspaceWindowToggle('dentalChart'))),
      isA<FilledButton>(),
    );
    expect(
      panel.workspace.isOpen('dentalChart', slot: kAttachedSlot),
      isTrue,
    );
    expect(panel.workspace.isOpen('dentalChart'), isFalse);

    // The patient's fields stay visible but take no edits while the visit is
    // the record being worked on.
    expect(find.byKey(WK.patientReadOnly), findsOneWidget);
    final absorbing = tester.widget<AbsorbPointer>(
      find
          .ancestor(
            of: find.byKey(WK.fieldPatientName),
            matching: find.byType(AbsorbPointer),
          )
          .first,
    );
    expect(absorbing.absorbing, isTrue);

    // The plan tab is the way to the patient's own chart: it closes the visit
    // (keeping its draft) and clears the band.
    await tester.tap(find.byKey(ValueKey('scope-patient:${patient.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(WK.visitBand), findsNothing,
        reason: 'asking for the plan leaves the visit');
    expect(panel.attached, isNull);
    expect(panel.workspace.isOpen('dentalChart'), isTrue);
    expect(find.byKey(WK.patientReadOnly), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the band moves to the visit that still has unsaved work',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'move-visit-patient');
    patients.set(patient);
    final dirtyVisit = testAppointment(
      id: 'move-visit-dirty',
      patientID: patient.id,
      date: DateTime(2026, 7, 1),
    );
    final otherVisit = testAppointment(
      id: 'move-visit-other',
      patientID: patient.id,
      date: DateTime(2026, 7, 2),
    );
    appointments.setAll([dirtyVisit, otherVisit]);
    await pumpApexoApp(tester, const SizedBox.shrink());
    await openAppointment(dirtyVisit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    final dirty = panel.owned.whereType<AppointmentSession>().single;
    dirty.item.preOpNotes = 'typed but not saved';
    dirty.refreshDirty();

    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();
    await selectVisit(patient.id, otherVisit.id, focus: kDentalChartWindowId);
    await tester.pumpAndSettle();
    expect((panel.attached! as AppointmentSession).item.id, otherVisit.id);
    expect(find.byKey(WK.visitMoveToVisit), findsOneWidget);

    await tester.tap(find.byKey(WK.visitMoveToVisit));
    await tester.pumpAndSettle();

    expect((panel.attached! as AppointmentSession).item.id, dirtyVisit.id,
        reason: 'the footer hint is also the way back to that visit');
    expect(find.byKey(WK.visitBand), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone opening a visit shows the band, not a chart sheet',
      (tester) async {
    setViewport(tester, const Size(420, 900));
    final patient = testPatient(id: 'phone-band-patient');
    patients.set(patient);
    final visit = testAppointment(
      id: 'phone-band-visit',
      patientID: patient.id,
      date: DateTime(2026, 6, 3, 9, 0),
    );
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    // The opener has no screen of its own to ask; the app root is the screen.
    bContext = tester.element(find.byType(SizedBox).first);

    await openAppointment(visit);
    await tester.pumpAndSettle();
    final panel = PanelsManager.active().single;
    await pumpShell(tester, panel, 420);
    await tester.pumpAndSettle();

    expect(find.byKey(WK.visitBand), findsOneWidget,
        reason: 'the visit is the band on a phone');
    expect(panel.workspace.openIn(kAttachedSlot), isEmpty,
        reason: 'a chart sheet would cover the date, time and duration');
    expect(find.byType(DentalChartBody), findsNothing,
        reason: 'the band is the surface the opener came for');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the plan chart keeps the all-visits action on its title',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'plan-action-patient');
    patients.set(patient);
    final visit =
        testAppointment(id: 'plan-action-visit', patientID: patient.id);
    appointments.set(visit);
    await pumpApexoApp(tester, const SizedBox.shrink());
    final panel =
        await ensurePatientPanel(patient, focus: PatientWindow.dentalChart.id);
    await pumpShell(tester, panel, 1600);
    await tester.pumpAndSettle();

    expect(find.byKey(WK.chartAllAppointments), findsOneWidget,
        reason: 'the plan tab and the visit chart answer the same question');
    await tester.tap(find.byKey(WK.chartAllAppointments));
    await tester.pumpAndSettle();
    expect(panel.workspace.isOpen(PatientWindow.appointments.id), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      testWidgets(
          'scope slider snaps and previews before release in $direction with $kind',
          (tester) async {
        setViewport(tester, const Size(1600, 1000));
        final patient = testPatient(id: 'scrub-patient');
        patients.set(patient);
        final visits = List.generate(
            3,
            (i) => testAppointment(
                  id: 'scrub-$i',
                  patientID: patient.id,
                  date: DateTime(2026, 1, 1 + i * i * 5),
                ));
        appointments.setAll(visits);
        await pumpApexoApp(tester, const SizedBox.shrink());
        unawaited(openPatient(patient));
        await tester.pumpAndSettle();
        await pumpShell(tester, PanelsManager.active().single, 1600,
            direction: direction);
        await tester.pumpAndSettle();
        Finder dot(int i) =>
            find.byKey(ValueKey('scope-appointment:${visits[i].id}'));
        Finder card(int i) =>
            find.byKey(ValueKey('scope-hover-card-${visits[i].id}'));
        bool selected(int i) => tester
            .widgetList<Semantics>(
              find.descendant(of: dot(i), matching: find.byType(Semantics)),
            )
            .any((s) => s.properties.selected == true);
        String scope() => tester
            .widget<DentalChartBody>(find.byType(DentalChartBody))
            .session
            .id;
        await tester.tap(dot(2));
        await tester.pumpAndSettle();
        final barRect = tester.getRect(find.byType(VisitScopeBar));
        final first = tester.getCenter(dot(0));
        final middle = tester.getCenter(dot(1));
        final last = tester.getCenter(dot(2));
        final nearMiddle =
            Offset(middle.dx + (last.dx - middle.dx) * 0.2, middle.dy);
        var haptics = 0;
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            expect(call.arguments, 'HapticFeedbackType.selectionClick');
            haptics++;
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));

        final drag = await tester.startGesture(last, kind: kind);
        await drag.moveTo(nearMiddle);
        await tester.pumpAndSettle();
        expect(selected(1), isTrue);
        expect(selected(2), isFalse);
        expect(card(1), findsOneWidget);
        expect(scope(), 'appointment:${visits[2].id}',
            reason: 'scrubbing previews without opening intermediate charts');
        expect(haptics, 1);
        await drag.moveTo(nearMiddle + const Offset(2, 0));
        await tester.pumpAndSettle();
        expect(haptics, 1, reason: 'no repeated feedback within the same snap');
        await drag.moveTo(first);
        await tester.pumpAndSettle();
        expect(card(0), findsOneWidget);
        expect(card(1), findsNothing);
        expect(selected(0), isTrue);
        await drag.moveTo(nearMiddle);
        await tester.pumpAndSettle();
        expect(haptics, 3);
        await drag.up();
        await tester.pumpAndSettle();
        expect(scope(), 'appointment:${visits[1].id}');
        expect(card(1), findsNothing);
        expect(tester.getRect(find.byType(VisitScopeBar)), barRect);
        await tester
            .tapAt(Offset(middle.dx + (last.dx - middle.dx) * 0.65, middle.dy));
        await tester.pumpAndSettle();
        expect(scope(), 'appointment:${visits[2].id}',
            reason: 'tapping the line between dots selects the nearest visit');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('scope slider edge-scrolls and cancels in $direction',
        (tester) async {
      setViewport(tester, const Size(600, 800));
      final patient = testPatient(id: 'edge-scrub-patient');
      patients.set(patient);
      final visits = List.generate(
          40,
          (i) => testAppointment(
                id: 'edge-scrub-$i',
                patientID: patient.id,
                date: DateTime(2026, 1, 1 + i),
              ));
      appointments.setAll(visits);
      await pumpApexoApp(
          tester,
          Directionality(
            textDirection: direction,
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 320,
                  child: VisitScopeBar(
                      patient: patient,
                      session: appointmentDentalChart(visits.last),
                      currentAppointment: visits.last),
                )),
          ));
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('scope-visit-scroll'));
      final scroll = tester.widget<SingleChildScrollView>(strip).controller!;
      final viewport = tester.getRect(strip);
      final selected =
          find.byKey(ValueKey('scope-appointment:${visits.last.id}'));
      final edge = Offset(
          direction == TextDirection.ltr
              ? viewport.left + 1
              : viewport.right - 1,
          viewport.center.dy);
      expect(PanelsManager.active(), isEmpty,
          reason: 'before starting the drag');
      final drag = await tester.startGesture(tester.getCenter(selected));
      await drag.moveTo(edge);
      await tester.pump(const Duration(milliseconds: 100));
      final before = scroll.offset;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(scroll.offset, greaterThan(before));
      expect(
          find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>)
                  .value
                  .startsWith('scope-hover-card-')),
          findsOneWidget);
      await drag.cancel();
      await tester.pumpAndSettle();
      final stopped = scroll.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll.offset, stopped);
      expect(PanelsManager.active(), isEmpty,
          reason: 'cancelled scrubbing never opens a visit');
      expect(
          find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>)
                  .value
                  .startsWith('scope-hover-card-')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets(
        'scope slider supports Escape and repeated keyboard selection in $direction',
        (tester) async {
      setViewport(tester, const Size(1600, 1000));
      final patient = testPatient(id: 'keyboard-scrub-patient');
      patients.set(patient);
      final visits = List.generate(
          3,
          (i) => testAppointment(
                id: 'keyboard-scrub-$i',
                patientID: patient.id,
                date: DateTime(2026, 1, 1 + i * 10),
              ));
      appointments.setAll(visits);
      await pumpApexoApp(tester, const SizedBox.shrink());
      unawaited(openPatient(patient));
      await tester.pumpAndSettle();
      await pumpShell(tester, PanelsManager.active().single, 1600,
          direction: direction);
      await tester.pumpAndSettle();
      Finder dot(int i) =>
          find.byKey(ValueKey('scope-appointment:${visits[i].id}'));
      String scope() => tester
          .widget<DentalChartBody>(find.byType(DentalChartBody))
          .session
          .id;
      await tester.tap(dot(2));
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(tester.getCenter(dot(2)));
      await drag.moveTo(tester.getCenter(dot(1)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();
      expect(scope(), 'appointment:${visits[2].id}');
      expect(find.byKey(ValueKey('scope-hover-card-${visits[1].id}')),
          findsNothing);
      final previous = direction == TextDirection.rtl
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      String? previewValue() => tester
          .widget<Semantics>(find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.slider == true))
          .properties
          .value;
      await tester.sendKeyEvent(previous);
      await tester.pumpAndSettle();
      expect(previewValue(), DF.full(visits[1].date));
      expect(find.byKey(ValueKey('scope-hover-card-${visits[1].id}')),
          findsOneWidget);
      await tester.sendKeyEvent(previous);
      await tester.pumpAndSettle();
      expect(previewValue(), DF.full(visits[0].date));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(previewValue(), DF.full(visits[2].date));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(previewValue(), DF.full(visits[0].date));
      expect(scope(), 'appointment:${visits[2].id}');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(scope(), 'appointment:${visits[0].id}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'scope slider asks about unsaved work only on release and restores on refusal',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient = testPatient(id: 'dirty-scrub-patient');
    patients.set(patient);
    final visits = List.generate(
        2,
        (i) => testAppointment(
              id: 'dirty-scrub-$i',
              patientID: patient.id,
              date: DateTime(2026, 1, 1 + i * 10),
            ));
    appointments.setAll(visits);
    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();
    final session =
        tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session;
    session.teeth['11'] = 'caries';
    session.changed();
    await tester.pumpAndSettle();
    Finder dot(int i) =>
        find.byKey(ValueKey('scope-appointment:${visits[i].id}'));
    final drag = await tester.startGesture(tester.getCenter(dot(0)));
    await drag.moveTo(tester.getCenter(dot(1)));
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsNothing);
    expect(find.byKey(ValueKey('scope-hover-card-${visits[1].id}')),
        findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text(txt('sureClosePanel')), findsWidgets);
    await tester.tap(find.text(txt('back')).last);
    await tester.pumpAndSettle();
    expect(tester.widget<DentalChartBody>(find.byType(DentalChartBody)).session,
        same(session));
    expect(session.teeth['11'], 'caries');
    expect(find.byKey(ValueKey('scope-patient:${patient.id}')), findsOneWidget);
    expect(
        find.byKey(ValueKey('scope-hover-card-${visits[1].id}')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'timeline dot distances are proportional to duration between appointments, hover shows rich card, and transparency fade appears only when overflowing',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final patient =
        testPatient(id: 'timeline-prop-patient', name: 'Layla Mansour');
    patients.set(patient);

    final firstVisit = testAppointment(
      id: 'timeline-v1',
      patientID: patient.id,
      date: DateTime(2026, 1, 1, 10),
      teeth: {'16': 'rCT'},
      postOpNotes: 'Access and canal prep',
      price: 150,
      paid: 150,
      isDone: true,
    );
    // 5 days after firstVisit
    final secondVisit = testAppointment(
      id: 'timeline-v2',
      patientID: patient.id,
      date: DateTime(2026, 1, 6, 11),
      teeth: {'16': 'crown', '26': 'filling'},
      teethExtraNotes: {'16': 'Zirconia shade A2'},
      postOpNotes: 'Crown cemented',
      prescriptions: ['Ibuprofen 400mg'],
      price: 300,
      paid: 200,
      isDone: true,
    );
    // 55 days after secondVisit (11x longer interval than first->second)
    final lastVisit = testAppointment(
      id: 'timeline-v3',
      patientID: patient.id,
      date: DateTime(2026, 3, 2, 14),
      preOpNotes: '6-week recall check',
      price: 50,
      paid: 0,
      isDone: false,
    );
    appointments.setAll([firstVisit, secondVisit, lastVisit]);

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();
    await pumpShell(tester, PanelsManager.active().single, 1600);
    await tester.pumpAndSettle();

    final dot1 = find.byKey(ValueKey('scope-appointment:${firstVisit.id}'));
    final dot2 = find.byKey(ValueKey('scope-appointment:${secondVisit.id}'));
    final dot3 = find.byKey(ValueKey('scope-appointment:${lastVisit.id}'));

    final x1 = tester.getCenter(dot1).dx;
    final x2 = tester.getCenter(dot2).dx;
    final x3 = tester.getCenter(dot3).dx;

    // 1. Chronological order: first dot is first appointment, last dot is last appointment
    expect(x1, lessThan(x2));
    expect(x2, lessThan(x3));

    // 2. Distance between dots is proportional to duration between appointments
    final gap12 = x2 - x1; // 5 days
    final gap23 = x3 - x2; // 55 days
    expect(
      gap23,
      greaterThan(gap12 * 3),
      reason:
          '55-day gap must be visually much wider than the 5-day gap on the timeline',
    );

    // 3. With 3 visits, all dots fit on the line without scrolling or fade mask
    final strip = find.byKey(const ValueKey('scope-visit-scroll'));
    final scroll = tester.widget<SingleChildScrollView>(strip).controller!;
    expect(scroll.position.maxScrollExtent, 0.0);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('scope-timeline-fade')),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
      reason: 'no transparency fade when all visits fit without scrolling',
    );

    // 4. Hovering on a dot displays a rich card with date, interval, treatment, notes, price & payment
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(dot2));
    await tester.pumpAndSettle();

    final hoverCard =
        find.byKey(ValueKey('scope-hover-card-${secondVisit.id}'));
    expect(hoverCard, findsOneWidget);
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.text(DF.full(secondVisit.date)),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.text(txt('crown')),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.text(txt('filling')),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.textContaining('Zirconia shade A2'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.text('Crown cemented'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.text('300'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.text('200'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: hoverCard,
        matching: find.textContaining(txt('underpaid')),
      ),
      findsWidgets,
    );

    // Moving pointer away hides the rich hover card
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(hoverCard, findsNothing);

    // 5. When the number of visits goes too large, scrolling and transparency fade activate
    final manyVisits = List.generate(
      35,
      (i) => testAppointment(
        id: 'many-v-$i',
        patientID: patient.id,
        date: DateTime(2026, 4, 1).add(Duration(days: i * 2)),
      ),
    );
    appointments.setAll(manyVisits);
    await tester.pumpAndSettle();

    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('scope-timeline-fade')),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
      reason:
          'when visits overflow the timeline, a ShaderMask transparency fade indicates scrollable content',
    );
    expect(tester.takeException(), isNull);
  });
}
