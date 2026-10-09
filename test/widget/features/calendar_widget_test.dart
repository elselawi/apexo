import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/services/localization/locale.dart' show Txt;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../helpers/pump_app.dart';

void main() {
  Appointment appointmentAt(DateTime date) => Appointment.fromJson({
        'id': 'appointment-${date.millisecondsSinceEpoch}',
        'date': (date.millisecondsSinceEpoch / 60000).round(),
      });

  Future<void> pumpCalendar(
    WidgetTester tester, {
    required List<Appointment> items,
    required DateTime selectedDay,
  }) async {
    await pumpApexoApp(
      tester,
      SizedBox(
        width: 713.37,
        height: 500,
        child: WeekAgendaCalendar<Appointment>(
          items: items,
          startDay: StartingDayOfWeek.monday,
          initiallySelectedDay: selectedDay.millisecondsSinceEpoch,
          onAddNew: (_) {},
          onSetTime: (_) {},
          onSelect: (_) {},
        ),
      ),
    );

    final calendarState = tester.state<WeekAgendaCalendarState<Appointment>>(
      find.byType(WeekAgendaCalendar<Appointment>),
    );
    (calendarState as dynamic).setState(() {
      calendarState.calendarFormat = CalendarFormat.month;
    });
    await tester.pumpAndSettle();
  }

  int? dayCount(WidgetTester tester, DateTime day) {
    final badge = find.byKey(WK.calendarDayCount(day));
    if (badge.evaluate().isEmpty) return null;
    final label = tester.widget<Txt>(
      find.descendant(of: badge, matching: find.byType(Txt)),
    );
    return int.tryParse(label.data ?? '');
  }

  Future<void> turnCalendarMonth(WidgetTester tester, int delta) async {
    final selected = find.byKey(WK.calendarSelected);
    final Offset from;
    if (selected.evaluate().isNotEmpty) {
      from = tester.getCenter(selected.first);
    } else {
      from = tester.getCenter(find.byType(DayCell).first);
    }
    await tester.dragFrom(from, Offset(delta > 0 ? -700 : 700, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('month paging keeps a selected day marker', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final items = <Appointment>[
      appointmentAt(today),
      appointmentAt(today.add(const Duration(hours: 1))),
      appointmentAt(today.add(const Duration(hours: 2))),
    ];

    await pumpCalendar(tester, items: items, selectedDay: today);

    expect(dayCount(tester, today), 3);
    expect(find.byKey(WK.calendarToday), findsNothing);

    await turnCalendarMonth(tester, 1);
    expect(find.byKey(WK.calendarToday), findsOneWidget);

    await turnCalendarMonth(tester, -1);
    expect(find.byKey(WK.calendarToday), findsNothing);
    expect(dayCount(tester, today), 3);
    expect(find.byKey(WK.calendarSelected), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month view renders many-event badges exactly', (tester) async {
    final now = DateTime.now();
    final selectedDay = DateTime(now.year, now.month, 1, 9);
    final busyDay = DateTime(now.year, now.month, 18, 8);
    final items = List<Appointment>.generate(
      37,
      (index) => appointmentAt(
        busyDay.add(Duration(minutes: 15 * index)),
      ),
    );

    await pumpCalendar(tester, items: items, selectedDay: selectedDay);

    expect(dayCount(tester, busyDay), 37);
    expect(find.byKey(WK.calendarDayCount(busyDay)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
