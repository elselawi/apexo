import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/events_agenda_widget.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late List<int> originalPerms;

  setUp(() {
    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    login.savedPermissions = originalPerms;
  });

  testWidgets('long pressing an agenda row opens its context menu',
      (tester) async {
    final previousPatients = patients.docs.values.toList();
    final previousAppointments = appointments.docs.values.toList();
    patients.observableMap.clear();
    appointments.observableMap.clear();
    patients.set(testPatient(id: 'agenda-menu-patient', name: 'Menu Patient'));
    final appointment = testAppointment(
      id: 'agenda-menu-test',
      patientID: 'agenda-menu-patient',
      date: DateTime(2026, 1, 15, 10, 30),
      teeth: {'11': 'filling', '12': 'filling'},
      imgs: ['photo-a.png', 'photo-b.png'],
      dcmImgs: ['xray.dcm'],
    );
    appointments.set(appointment);
    addTearDown(() {
      appointments.observableMap.clear();
      appointments.setAll(previousAppointments);
      patients.observableMap.clear();
      patients.setAll(previousPatients);
    });

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 300,
        child: AgendaListView<Appointment>(
          items: [appointment],
          showPayments: false,
          onSelect: (_, __) {},
          onSetTime: (_) {},
        ),
      ),
    );

    final row = find.byKey(WK.calendarAppointmentTile);
    expect(row, findsOneWidget);
    expect(find.byType(MenuFlyout), findsNothing);

    await tester.longPress(row);
    await tester.pumpAndSettle();

    Finder item(String key) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt(key)),
        );
    Finder suffix(Finder finder) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: finder,
        );
    // One item per appointment tab, then the row's own actions.
    expect(item("appointment"), findsWidgets);
    expect(item("operativeDetails"), findsWidgets);
    expect(item("gallery"), findsWidgets);
    expect(item("markAsDone"), findsWidgets);
    // The visit's patient: their whole history, and their record.
    expect(item("allAppointments"), findsWidgets);
    expect(item("treatments"), findsWidgets);
    expect(
      item(txt("openPatientRecord").replaceAll("{name}", "Menu Patient")),
      findsWidgets,
    );
    // The action that takes the visit away comes last.
    expect(item("delete"), findsWidgets);

    // The counts the menu appends: two treated teeth, three pictures in the
    // gallery (two photos and one X-ray), one visit in the patient's history.
    expect(suffix(find.text('(2)')), findsWidgets);
    expect(suffix(find.text('(3)')), findsWidgets);
    expect(suffix(find.text('(1)')), findsWidgets);
    // No labwork order and no patient web page: both say so with an empty
    // ring, not an error.
    expect(suffix(find.byIcon(FluentIcons.circle_ring)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a visit from the menu archives it after confirmation',
      (tester) async {
    final previousAppointments = appointments.docs.values.toList();
    appointments.observableMap.clear();
    appointments.set(testAppointment(
      id: 'agenda-delete-test',
      date: DateTime(2026, 1, 15, 10, 30),
    ));
    addTearDown(() {
      appointments.observableMap.clear();
      appointments.archived.clear();
      appointments.setAll(previousAppointments);
    });

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 300,
        child: AgendaListView<Appointment>(
          items: [appointments.get('agenda-delete-test')!],
          showPayments: false,
          onSelect: (_, __) {},
          onSetTime: (_) {},
        ),
      ),
    );

    await tester.longPress(find.byKey(WK.calendarAppointmentTile));
    await tester.pumpAndSettle();

    await tester.tap(find
        .descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt("delete")),
        )
        .first);
    await tester.pumpAndSettle();

    // The menu steps aside for the confirmation, anchored where it was.
    expect(find.byType(MenuFlyout), findsNothing);
    expect(find.byType(ConfirmDeleteFlyout), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, txt("delete")).first);
    await tester.pumpAndSettle();

    expect(appointments.archived.containsKey('agenda-delete-test'), isTrue);
    expect(appointments.get('agenda-delete-test')!.archived, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tab item opens the panel on that tab', (tester) async {
    final appointment = testAppointment(
      id: 'agenda-tab-test',
      date: DateTime(2026, 1, 15, 10, 30),
    );
    final opened = <AppointmentWindow?>[];

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 300,
        child: AgendaListView<Appointment>(
          items: [appointment],
          showPayments: false,
          onSelect: (_, window) => opened.add(window),
          onSetTime: (_) {},
        ),
      ),
    );

    await tester.longPress(find.byKey(WK.calendarAppointmentTile));
    await tester.pumpAndSettle();

    await tester.tap(find
        .descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt("operativeDetails")),
        )
        .first);
    await tester.pumpAndSettle();

    // The window comes from appointmentWindows, the same list the panel builds.
    expect(opened, [AppointmentWindow.operative]);
  });

  testWidgets('the row\'s own control comes back when the panel closes',
      (tester) async {
    final appointment = testAppointment(
      id: 'agenda-open-state-test',
      date: DateTime(2026, 1, 15, 10, 30),
    );

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 300,
        child: AgendaListView<Appointment>(
          items: [appointment],
          showPayments: false,
          onSelect: (_, __) {},
          onSetTime: (_) {},
        ),
      ),
    );
    expect(find.byType(Checkbox), findsOneWidget);

    // The record is opened in a panel: the row swaps its checkbox for "bring
    // that panel forward".
    final panel = DelegatedPanel(
      itemId: appointment.id,
      singularName: 'appointment',
      unicodeSymbol: '📅',
      icon: WindowsIcons.calendar,
      windows: const [],
      checkUnsavedChanges: () => false,
      onSave: () async => const [],
    );
    PanelsManager.active([panel]);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    // Both of the row's controls hand over to the open panel.
    expect(find.byIcon(FluentIcons.open_in_new_tab), findsWidgets);

    // Closing it puts the checkbox back — without waiting for the list to
    // change, which is what used to leave the button on a closed record.
    PanelsManager.closeAll();
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byIcon(FluentIcons.open_in_new_tab), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right clicking a timeline chip opens the same menu',
      (tester) async {
    final appointment = testAppointment(
      id: 'timeline-menu-test',
      date: DateTime(2026, 1, 15),
    );

    await pumpApexoApp(
      tester,
      // A chip is a fixed-width card; the suite's synthetic font is wider than
      // any real one, so the harness scales text down to keep the card intact.
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.6)),
        child: SizedBox(
          width: 1200,
          height: 800,
          child: CalendarTimelineView(
            items: [appointment],
            showPayments: false,
            selectedDate: appointment.date,
            onSelect: (_, __) {},
            onSetTime: (_) {},
            onAddNew: (_) {},
          ),
        ),
      ),
    );

    // The long press belongs to the drag, so the menu is on right click.
    await tester.longPress(find.byType(TimelineChip));
    await tester.pumpAndSettle();
    expect(find.byType(MenuFlyout), findsNothing);

    await tester.tap(find.byType(TimelineChip), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(MenuFlyout),
        matching: find.text(txt("operativeDetails")),
      ),
      findsWidgets,
    );
    // A chip is a fixed-width card, so the test's synthetic font can overflow
    // it; what matters here is that the menu opened at all.
  });
}
