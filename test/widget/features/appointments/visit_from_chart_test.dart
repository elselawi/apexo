@Tags(['serial'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_defaults.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/window_defaults.dart';

class _Shell extends StatelessWidget {
  const _Shell({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [PanelsManager.active.stream],
      builder: (context, _) {
        final panels = PanelsManager.active();
        final panel = panels.isEmpty ? null : panels.last;
        return Stack(
          children: [
            if (panel != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: 350,
                  height: double.infinity,
                  child: PanelScreen(panel: panel, layoutWidth: width),
                ),
              ),
            WindowsLayer(
              visible: true,
              screenWidth: width,
              refreshStreams: [
                patients.observableMap.stream,
                appointments.observableMap.stream,
              ],
            ),
          ],
        );
      },
    );
  }
}

void main() {
  late List<int> originalPerms;
  late Map<String, Patient> originalPatients;
  late Map<String, Appointment> originalAppointments;

  setUp(() async {
    originalPerms = login.savedPermissions;
    originalPatients = {...patients.observableMap.docs};
    originalAppointments = {...appointments.observableMap.docs};
    login.savedPermissions = Perm.full;
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    await resetWindowDefaults();
  });

  tearDown(() async {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    login.savedPermissions = originalPerms;
    patients.observableMap
      ..clear()
      ..setAll(originalPatients.values.toList());
    appointments.observableMap
      ..clear()
      ..setAll(originalAppointments.values.toList());
    await resetWindowDefaults();
  });

  /// What the device remembers about the windows each kind of panel opens with.
  void remember({
    List<String> host = const [],
    List<String> visit = const ['dentalChart'],
  }) {
    String stored = jsonEncode({
      'patient/host': host,
      'appointment/attached': visit,
    });
    windowDefaults = WindowDefaults(
      read: () => stored,
      write: (value) => stored = value,
    );
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1536, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bContext = tester.element(find.byType(FluentApp));
    await pumpApexoApp(tester, _Shell(width: size.width));
    await tester.pumpAndSettle();
  }

  /// The charts on screen, by the record whose teeth they edit.
  List<String> chartScopes(WidgetTester tester) => [
        for (final body
            in tester.widgetList<DentalChartBody>(find.byType(DentalChartBody)))
          body.session.id,
      ];

  testWidgets(
      'a visit started from the patient chart shows its chart and post-op record',
      (tester) async {
    // A 125 %-scaled laptop: the chart needs more height than the row has.
    remember();
    final patient = testPatient(id: 'new-visit-patient');
    patients.set(patient);
    appointments.set(testAppointment(
      id: 'new-visit-older',
      patientID: patient.id,
      date: DateTime(2026, 1, 1),
    ));

    await pumpApexoApp(tester, const SizedBox.shrink());
    await pumpShell(tester, size: const Size(1092, 614));

    unawaited(openPatientPanel(patient));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(panel.workspace.open, isEmpty,
        reason: 'the user left none of this patient\'s windows open');

    // The record's own chart, from the button at the top of the panel.
    await tester.tap(find.byKey(WK.workspaceWindowToggle('dentalChart')));
    await tester.pumpAndSettle();
    expect(chartScopes(tester), ['patient:${patient.id}']);

    // A visit started from the chart is the one the user came for.
    await tester.tap(find.byKey(WK.chartAddAppointment));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.btnCreateAppointment));
    await tester.pumpAndSettle();

    final visit = appointments.docs.values
        .firstWhere((appointment) => appointment.id != 'new-visit-older');
    expect(visit.patientID, patient.id);
    expect(panel.attached?.itemId, visit.id,
        reason: 'the new visit is carried beside its patient');

    expect(
      chartScopes(tester),
      ['appointment:${visit.id}'],
      reason: 'one chart on screen, and it is the visit\'s: the patient\'s own '
          'chart must not stand in for it because it happens to fit',
    );
    expect(find.byType(AppointmentOperativeForm), findsOneWidget,
        reason: 'the post-op record belongs under the visit\'s chart');
    final form = tester.getRect(find.byType(AppointmentOperativeForm));
    expect(form.height, greaterThan(0),
        reason: 'the post-op record has to be readable, not clipped away');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the visits list opens beside the visit and stays open',
      (tester) async {
    remember(host: const ['dentalChart']);
    final patient = testPatient(id: 'list-patient');
    patients.set(patient);
    final visit = testAppointment(
        id: 'list-visit', patientID: patient.id, date: DateTime.now());
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await pumpShell(tester);

    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    expect(
      panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
      isTrue,
    );

    // The chart's title carries the record's whole list of visits.
    await tester.tap(find.byKey(WK.chartAllAppointments));
    await tester.pumpAndSettle();
    expect(panel.workspace.isOpen(PatientWindow.appointments.id), isTrue,
        reason: 'the window the user asked for is the one on screen');
    expect(
      panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot),
      isFalse,
      reason: 'at this width the chart and the list do not both fit',
    );
    expect(find.byType(AppointmentCard), findsOneWidget);
  });

  testWidgets('the list\'s checkbox completes a visit that is open beside it',
      (tester) async {
    remember(host: const ['dentalChart']);
    final patient = testPatient(id: 'tick-patient');
    patients.set(patient);
    final visit = testAppointment(
        id: 'tick-visit', patientID: patient.id, date: DateTime.now());
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await pumpShell(tester);

    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().single;
    panel.showWindow(PatientWindow.appointments.id);
    await tester.pumpAndSettle();
    expect(find.byKey(WK.acCheckBox), findsOneWidget);

    await tester.tap(find.byKey(WK.acCheckBox));
    await tester.pumpAndSettle();

    expect(appointments.get(visit.id)!.isDone, isTrue,
        reason: 'a tick in the list is the visit completed, not a draft note');
    expect(appointmentSessions.get(visit.id)!.item.isDone, isTrue,
        reason: 'the visit\'s own band agrees');
    expect(appointmentSessions.get(visit.id)!.hasPendingEdits, isFalse,
        reason: 'the tick is written, so the visit is not left dirty on it');
    expect(tester.widget<Checkbox>(find.byKey(WK.acCheckBox)).checked, isTrue,
        reason: 'the tick is what the user sees');
    expect(panel.workspace.isOpen(PatientWindow.appointments.id), isTrue,
        reason: 'ticking a visit must not close the list it is ticked in');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab in the visit\'s price field lands in its paid field',
      (tester) async {
    remember();
    final patient = testPatient(id: 'tab-patient');
    patients.set(patient);
    final visit = testAppointment(
        id: 'tab-visit',
        patientID: patient.id,
        price: 100,
        paid: 40,
        date: DateTime.now());
    appointments.set(visit);

    await pumpApexoApp(tester, const SizedBox.shrink());
    await pumpShell(tester);
    await openAppointment(visit, AppointmentWindow.dentalChart);
    await tester.pumpAndSettle();

    FocusNode focusOf(Key field) => tester
        .widget<EditableText>(find.descendant(
            of: find.byKey(field), matching: find.byType(EditableText)))
        .focusNode;

    // Traversal reads the whole scene and the chart's neighbours sit between
    // the two, so these fields handle Tab themselves.
    await tester.tap(find.byKey(WK.fieldAppointmentPrice));
    await tester.pumpAndSettle();
    expect(focusOf(WK.fieldAppointmentPrice).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focusOf(WK.fieldAppointmentPayment).hasFocus, isTrue,
        reason: 'Tab goes price then paid, whatever stands beside the chart');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(focusOf(WK.fieldAppointmentPrice).hasFocus, isTrue,
        reason: 'Shift + Tab walks the pair back');
  });
}
