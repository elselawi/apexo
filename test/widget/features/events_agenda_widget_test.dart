import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/events_agenda_widget.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';

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
    final appointment = testAppointment(
      id: 'agenda-menu-test',
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

    final row = find.byKey(WK.calendarAppointmentTile);
    expect(row, findsOneWidget);
    expect(find.byType(MenuFlyout), findsNothing);

    await tester.longPress(row);
    await tester.pumpAndSettle();

    Finder item(String key) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt(key)),
        );
    // One item per appointment tab, then the row's own action.
    expect(item("appointment"), findsWidgets);
    expect(item("operativeDetails"), findsWidgets);
    expect(item("gallery"), findsWidgets);
    expect(item("markAsDone"), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tab item opens the panel on that tab', (tester) async {
    final appointment = testAppointment(
      id: 'agenda-tab-test',
      date: DateTime(2026, 1, 15, 10, 30),
    );
    final opened = <int?>[];

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 300,
        child: AgendaListView<Appointment>(
          items: [appointment],
          showPayments: false,
          onSelect: (_, tabIndex) => opened.add(tabIndex),
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

    // The index comes from appointmentTabs, the same list the panel builds.
    expect(
        opened, [appointmentTabIndex(appointment, AppointmentTab.operative)]);
  });
}
