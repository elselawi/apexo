import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../helpers/pump_app.dart';

void main() {
  for (final yearsFromToday in [-10, 10, -40]) {
    testWidgets(
        'calendar opens $yearsFromToday years away at fractional widths',
        (tester) async {
      final now = DateTime.now();
      final selected = DateTime(now.year + yearsFromToday, 5, 15);
      await pumpApexoApp(
        tester,
        SizedBox(
          width: 713.37,
          height: 500,
          child: WeekAgendaCalendar<Appointment>(
            items: const [],
            startDay: StartingDayOfWeek.monday,
            initiallySelectedDay: selected.millisecondsSinceEpoch,
            onAddNew: (_) {},
            onSetTime: (_) {},
            onSelect: (_) {},
          ),
        ),
      );
      final calendar = tester.widget<TableCalendar<Appointment>>(
        find.byType(TableCalendar<Appointment>),
      );
      int dayValue(DateTime value) => DateTime.utc(value.year, value.month, value.day)
          .millisecondsSinceEpoch;
      expect(dayValue(calendar.firstDay), lessThanOrEqualTo(dayValue(selected)));
      expect(dayValue(calendar.lastDay), greaterThanOrEqualTo(dayValue(selected)));
      expect(dayValue(calendar.focusedDay), dayValue(selected));
      final width =
          tester.getSize(find.byType(TableCalendar<Appointment>)).width;
      expect(width, width.floorToDouble());
      expect(tester.takeException(), isNull);
    });
  }
}
