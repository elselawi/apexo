import 'package:apexo/common_widgets/duration_pill.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

/// The calendar: the month grid and choosing a day.
///
/// Creating an appointment from a day needs the appointment panel's patient
/// picker (an `AutoSuggestBox`), which the tag-input tests in `patients.dart`
/// show is not yet drivable from the harness — see `todo.md` §6.
void registerCalendarTests() {
  group('calendar', () {
    testWidgets('01: the calendar renders its day cells', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openCalendar(tester);

      expect(find.byKey(WK.btnNewAppointment), findsOneWidget);
      // Today starts selected, so its cell is the selected one — a cell only
      // carries its date key while it is *not* the selection.
      expect(find.byKey(WK.calendarSelected), findsWidgets,
          reason: 'the calendar has no selected day cell');
      expect(find.byKey(WK.calendarDay(DateTime.now())), findsNothing,
          reason:
              "today's cell kept its date key while it is the selected one");
    });

    testWidgets('02: a day can be selected', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openCalendar(tester);

      // Tomorrow: rendered in every calendar format (the calendar opens on two
      // weeks, which shows today's week and the next one — a past day can be
      // outside it), and never today itself, because the selected cell carries
      // `calendarSelected` instead of its date key.
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      await E2E.tap(tester, find.byKey(WK.calendarDay(tomorrow)),
          description: 'the day cell');
      await E2E.waitFor(tester, find.byKey(WK.calendarSelected),
          description: 'the selected day cell');

      // The selection moved: today is not the selected day any more, so its cell
      // is back to carrying its own date key.
      expect(find.byKey(WK.calendarDay(DateTime.now())), findsWidgets,
          reason: 'the selection did not move off today');
    });

    testWidgets('03: an appointment can be rescheduled to another day',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      final day = DateTime.now();
      await Fixtures.createAppointment(tester, patientName: patient, day: day);

      // The date dialog opens on the appointment's own month, so the new day has
      // to be in it — and the calendar shows **one week from the start of the
      // week containing today** (`CalendarFormat.week`, and the clinic's week
      // starts on Monday), so a day after today is always on screen while
      // yesterday often is not. Move forward when the month allows, and back only
      // from the last day of a month.
      final lastDayOfMonth = DateTime(day.year, day.month + 1, 0).day;
      final moved = day.day == lastDayOfMonth
          ? day.subtract(const Duration(days: 1))
          : day.add(const Duration(days: 1));

      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.changeAppointmentDate(tester, moved);
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.selectDay(tester, moved);
      await E2E.waitFor(tester, find.textContaining(patient),
          description: 'the moved appointment on its new day');
      await Fixtures.selectDay(tester, day);
      expect(find.textContaining(patient), findsNothing,
          reason: 'the rescheduled appointment is still on its old day');
    });

    testWidgets('04: the duration can be picked from the pill', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now());

      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.setDuration(tester, 45);
      // The pill draws the *stored* row, not the draft, so it still reads the old
      // duration until the panel is reopened — which is what the next block asks.
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openAppointmentTile(tester, patient: patient);
      expect(
          find.descendant(
              of: find.byType(DurationPill),
              matching: find.textContaining('45')),
          findsOneWidget,
          reason: 'the duration did not survive the panel');
      await Fixtures.closePanel(tester);
    });

    testWidgets('05: a day with no appointments shows the empty state',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openCalendar(tester);

      // A day inside the visible fortnight that carries no count badge is a day
      // with nothing booked on it (the badge only exists when a day has events).
      DateTime? empty;
      for (var ahead = 1; ahead <= 13 && empty == null; ahead++) {
        final day = DateTime.now().add(Duration(days: ahead));
        if (Fixtures.dayCount(tester, day) == null) empty = day;
      }
      expect(empty, isNotNull,
          reason: 'every day in the visible fortnight has appointments');

      await Fixtures.selectDay(tester, empty!);
      await E2E.waitFor(
          tester, find.textContaining(txt('noAppointmentsForThisDay')),
          description: 'the empty-day state');
    });

    testWidgets('06: the today button comes back from another month',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openCalendar(tester);
      expect(find.byKey(WK.calendarToday), findsNothing,
          reason: 'the calendar opened on another month');

      await Fixtures.turnCalendarMonth(tester, 1);
      await E2E.waitFor(tester, find.byKey(WK.calendarToday),
          description: 'the today button');
      await E2E.tap(tester, find.byKey(WK.calendarToday),
          description: 'the today button');
      await E2E.settle(tester, frames: 30);
      expect(find.byKey(WK.calendarToday), findsNothing,
          reason: 'the today button did not come back to today');
    });

    testWidgets('07: the timeline view renders the same day', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now());

      await Fixtures.openCalendar(tester);
      await Fixtures.openCalendarTimeline(tester);
      expect(find.byType(CalendarTimelineView), findsOneWidget,
          reason: 'the timeline view did not render');
      // The same day, so the same visit is still on screen.
      expect(find.textContaining(patient), findsWidgets,
          reason: 'the timeline shows a different day');
    });

    testWidgets('08: paging to another month keeps the appointment data',
        (tester) async {
      // Kept skipped in this task: backend/E2E runs are out of scope, but the
      // deterministic widget regression now proves the month-page marker keeps
      // rendering. When this is re-enabled, wait on the selected-day cell rather
      // than on `calendarDay(today)`: the selected cell carries
      // `calendarSelected`, not its date key.
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      final today = DateTime.now();
      await Fixtures.createAppointment(tester,
          patientName: patient, day: today);

      await Fixtures.openCalendar(tester);
      final before = Fixtures.dayCount(tester, today);
      expect(before, isNotNull,
          reason: 'the booked day has no count badge to begin with');

      await Fixtures.turnCalendarMonth(tester, 1);
      await Fixtures.turnCalendarMonth(tester, -1);
      await E2E.waitFor(tester, find.byKey(WK.calendarSelected),
          description: "today's selected cell after paging back");
      expect(find.byKey(WK.calendarToday), findsNothing,
          reason: 'paging back did not return to the current month');
      expect(Fixtures.selectedDay(tester),
          '${today.year}-${today.month}-${today.day}',
          reason: 'paging back did not keep today selected');
      expect(Fixtures.dayCount(tester, today), before,
          reason: "the day's appointments were lost across month pages");
    }, skip: true);
  });
}
