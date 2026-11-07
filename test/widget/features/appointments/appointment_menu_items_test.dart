@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/events_agenda_widget.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late List<int> originalPerms;
  late List<Patient> originalPatients;
  late List<Appointment> originalAppointments;

  setUp(() {
    originalPerms = login.savedPermissions;
    originalPatients = patients.docs.values.toList();
    originalAppointments = appointments.docs.values.toList();
    patients.observableMap.clear();
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    patients.observableMap.clear();
    patients.setAll(originalPatients);
    appointments.observableMap.clear();
    appointments.setAll(originalAppointments);
    login.savedPermissions = originalPerms;
  });

  for (final source in ['patient record', 'agenda', 'timeline']) {
    for (final postOp in [0, 2]) {
      testWidgets('$source menu keeps the shared actions with post-op $postOp',
          (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        login.savedPermissions = Perm.full..[Perm.postOp] = postOp;
        final patient = testPatient(
          id: 'menu-patient',
          name: 'Nadia Hassan',
          phone: '+12025550123',
        );
        final appointment = testAppointment(
          id: 'menu-visit',
          patientID: patient.id,
          date: DateTime(2026, 1, 15, 10),
          preOpNotes: 'Visit preview',
        );
        patients.set(patient);
        appointments.set(appointment);
        final opened = <AppointmentWindow?>[];
        final Widget content;
        final Finder target;
        switch (source) {
          case 'patient record':
            content = SingleChildScrollView(
              child: PatientAppointments(
                patient,
                hide: const [
                  AppointmentSections.patient,
                  AppointmentSections.paymentSummary,
                ],
                onOpenAppointment: (_, window) => opened.add(window),
              ),
            );
            target = find.byType(AppointmentCard);
          case 'agenda':
            content = AgendaListView<Appointment>(
              items: [appointment],
              showPayments: false,
              onSelect: (_, window) => opened.add(window),
              onSetTime: (_) {},
            );
            target = find.byKey(WK.calendarAppointmentTile);
          default:
            content = MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(0.6)),
              child: CalendarTimelineView(
                items: [appointment],
                selectedDate: appointment.date,
                showPayments: false,
                onSelect: (_, window) => opened.add(window),
                onSetTime: (_) {},
                onAddNew: (_) {},
              ),
            );
            target = find.byType(TimelineChip);
        }
        await pumpApexoApp(tester, SizedBox(width: 1200, child: content));
        await tester.tap(target, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        Finder label(String text) => find.descendant(
              of: find.byType(MenuFlyout),
              matching: find.text(text),
            );
        for (final window in appointmentWindows(appointment)) {
          expect(label(txt(window.titleKey)), findsWidgets);
        }
        expect(label(txt('operativeDetails')),
            postOp == 2 ? findsWidgets : findsNothing);
        expect(label(txt('markAsDone')), findsWidgets);
        expect(label(txt('delete')), findsWidgets);
        expect(label(txt('sendEmail')), findsWidgets);
        final inPatient = source == 'patient record';
        expect(label(txt('allAppointments')),
            inPatient ? findsNothing : findsWidgets);
        expect(
          label(txt('openPatientRecord').replaceAll('{name}', patient.title)),
          inPatient ? findsNothing : findsWidgets,
        );
        expect(patient.phone, isNotEmpty);
        expect(
          tester
              .widget<MenuFlyout>(find.byType(MenuFlyout))
              .items
              .whereType<MenuFlyoutSubItem>(),
          inPatient ? isEmpty : hasLength(1),
        );

        await tester
            .tap(label(txt(AppointmentWindow.dentalChart.titleKey)).first);
        await tester.pumpAndSettle();
        expect(opened, [AppointmentWindow.dentalChart]);
        expect(find.byType(MenuFlyout), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('chart and gallery shortcuts stay in the patient panel',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final patient = testPatient(id: 'shortcut-patient', name: 'Nadia Hassan');
    patients.set(patient);
    appointments.set(testAppointment(
      id: 'shortcut-visit',
      patientID: patient.id,
      date: DateTime(2026, 1, 15),
      teeth: {'11': 'filling'},
    ));
    unawaited(openPatientRecord(patient));
    await pumpApexoApp(
      tester,
      SingleChildScrollView(child: PatientAppointments(patient)),
    );
    final panel = PanelsManager.active().single;
    final dentalNotes = find.text(txt('dentalNotes')).first;
    await tester.tapAt(tester.getCenter(dentalNotes));
    await tester.pumpAndSettle();

    // The visit lives in the patient's panel; its chart attaches there, never
    // as its own panel or window.
    expect(PanelsManager.active(), [panel]);
    expect(WindowsManager.open(), isEmpty);
    expect(panel.attached!.itemId, 'shortcut-visit');
    expect(
      panel.workspace
          .isOpen(AppointmentWindow.dentalChart.id, slot: kAttachedSlot),
      isTrue,
    );

    await tester.tap(find.byType(AppointmentCard), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find
        .descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt('gallery')),
        )
        .first);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), [panel]);
    expect(WindowsManager.open(), isEmpty);
    expect(
      panel.workspace.isOpen(AppointmentWindow.gallery.id, slot: kAttachedSlot),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a patient visit card also offers the menu on long press',
      (tester) async {
    final patient = testPatient(id: 'long-press-patient');
    patients.set(patient);
    appointments.set(testAppointment(
      id: 'long-press-visit',
      patientID: patient.id,
      date: DateTime(2026, 1, 15),
    ));
    await pumpApexoApp(
      tester,
      SingleChildScrollView(child: PatientAppointments(patient)),
    );

    // A corner, not the centre: the centre can land on a text field, whose long
    // press is the field's own.
    await tester.longPressAt(
      tester.getTopLeft(find.byType(AppointmentCard)) + const Offset(24, 12),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MenuFlyout), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the calendar gallery menu opens only the gallery window',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final patient = testPatient(id: 'menu-gallery-patient');
    final visit = testAppointment(
      id: 'menu-gallery-visit',
      patientID: patient.id,
      date: DateTime(2026, 2, 10),
      imgs: ['photo-1'],
    );
    patients.set(patient);
    appointments.set(visit);
    await pumpApexoApp(
      tester,
      SizedBox(
        width: 1200,
        child: AgendaListView<Appointment>(
          items: [visit],
          showPayments: false,
          onSelect: (appointment, window) {},
          onSetTime: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(WK.calendarAppointmentTile),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find
        .descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt('gallery')),
        )
        .first);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty,
        reason: 'the context menu opened the gallery, not the patient record');
    final floating = WindowsManager.open().single;
    expect(floating.window.id, AppointmentWindow.gallery.id);
    expect(PanelsManager.active(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
