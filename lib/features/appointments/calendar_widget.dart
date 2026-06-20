import 'dart:math';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/swipe_detector.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Card;
import 'package:flutter/material.dart' show Card;
import 'package:intl/intl.dart' as intl;
import 'package:table_calendar/table_calendar.dart';
import '../../utils/colors_without_yellow.dart';
import '../../utils/round.dart';
import 'events_agenda_widget.dart';
import 'events_timeline_widget.dart';

/// Which view to show below the day title bar.
enum EventsViewMode {
  /// Plain sorted list of appointment tiles.
  agenda,

  /// Google‑Calendar‑style time grid with duration‑based positioning.
  timeline,
}

// ─────────────────────────────────────────────────────────────────────────────
// Main widget
// ─────────────────────────────────────────────────────────────────────────────

class WeekAgendaCalendar<Item extends Appointment> extends StatefulWidget {
  final List<Item> items;
  final List<Widget>? actions;
  final StartingDayOfWeek startDay;
  final int initiallySelectedDay;
  final void Function(DateTime date) onAddNew;
  final void Function(Item item) onSetTime;
  final void Function(Item item) onSelect;

  const WeekAgendaCalendar({
    super.key,
    required this.items,
    required this.startDay,
    required this.initiallySelectedDay,
    required this.onAddNew,
    required this.onSetTime,
    required this.onSelect,
    this.actions,
  });

  @override
  WeekAgendaCalendarState<Item> createState() =>
      WeekAgendaCalendarState<Item>();
}

class WeekAgendaCalendarState<Item extends Appointment>
    extends State<WeekAgendaCalendar<Item>> {
  CalendarFormat calendarFormat = CalendarFormat.week;
  late DateTime selectedDate;
  final now = DateTime.now();
  bool showPayments = false;

  double get calendarHeight {
    switch (calendarFormat) {
      case CalendarFormat.month:
        return 300;
      case CalendarFormat.twoWeeks:
        return 170;
      default:
        return 130;
    }
  }

  @override
  void initState() {
    super.initState();
    selectedDate =
        DateTime.fromMillisecondsSinceEpoch(widget.initiallySelectedDay);
  }

  void _goToToday() => setState(() => selectedDate = now);

  List<Item> _getItemsForDay(DateTime day) =>
      widget.items.where((item) => isSameDay(day, item.date)).toList();

  List<Item> _getItemsForSelectedDay() =>
      widget.items.where((item) => isSameDay(selectedDate, item.date)).toList();

  bool isSameDay(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;

  @override
  Widget build(BuildContext context) {
    final itemsForSelectedDay = _getItemsForSelectedDay();
    return Column(
      children: [
        _buildCommandBar(),
        _buildCalendar(),
        const SizedBox(height: 1),
        Expanded(
          child: SwipeDetector(
            onSwipePrev: () => setState(() {
              selectedDate = selectedDate.subtract(const Duration(days: 1));
            }),
            onSwipeNext: () => setState(() {
              selectedDate = selectedDate.add(const Duration(days: 1));
            }),
            child: Column(children: [
              _buildDayTitleBar(itemsForSelectedDay),
              Expanded(
                child: localSettings.calendarEventsViewMode ==
                        EventsViewMode.agenda
                    ? AgendaListView<Item>(
                        items: itemsForSelectedDay,
                        showPayments: showPayments,
                        onSelect: widget.onSelect,
                        onSetTime: widget.onSetTime,
                      )
                    : CalendarTimelineView(
                        items: itemsForSelectedDay.cast<Appointment>().toList(),
                        showPayments: showPayments,
                        selectedDate: selectedDate,
                        onSelect: (appointment) =>
                            widget.onSelect(appointment as Item),
                        onSetTime: (appointment) =>
                            widget.onSetTime(appointment as Item),
                      ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // ─── Command bar ───────────────────────────────────────────────────────
  Widget _buildCommandBar() {
    return ScreenCommandBar(
      mainButton: IconButton(
        onPressed: () => widget.onAddNew(selectedDate),
        icon: ButtonContent(FluentIcons.add, txt("newAppointment")),
      ),
      farItems: widget.actions ?? [],
    );
  }

  // ─── Calendar header ───────────────────────────────────────────────────
  Widget _buildCalendar() {
    return Container(
        constraints: BoxConstraints(maxHeight: calendarHeight),
        child: Card(
          color: Colors.transparent,
          elevation: 0,
          child: _buildTableCalendar(),
        ));
  }

  Widget _buildTableCalendar() {
    return TableCalendar(
      firstDay: now.subtract(const Duration(days: 9999)),
      lastDay: now.add(const Duration(days: 9999)),
      focusedDay: selectedDate,
      daysOfWeekVisible: true,
      rowHeight: 30,
      startingDayOfWeek: widget.startDay,
      pageJumpingEnabled: true,
      selectedDayPredicate: (day) => isSameDay(day, selectedDate),
      shouldFillViewport: true,
      calendarFormat: calendarFormat,
      onFormatChanged: (format) {
        setState(() {
          calendarFormat = format;
        });
      },
      availableCalendarFormats: Map.from({
        CalendarFormat.twoWeeks: txt("twoWeeksAbbr"),
        CalendarFormat.month: txt("monthAbbr"),
        CalendarFormat.week: txt("weekAbbr")
      }),
      eventLoader: (day) => _getItemsForDay(day),
      headerStyle: HeaderStyle(
          formatButtonShowsNext: false,
          formatButtonTextStyle: const TextStyle(color: Colors.white),
          formatButtonDecoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.grey.toAccentColor().lightest,
                Colors.grey.toAccentColor().light,
              ]),
              borderRadius: BorderRadius.circular(4))),
      calendarBuilders: CalendarBuilders(
        dowBuilder: (context, day) => Center(
          child: Txt(
            intl.DateFormat("EE", locale.s.$code).format(day),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        headerTitleBuilder: (context, day) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Center(
                child: Txt(
                  intl.DateFormat('MMMM yyyy', locale.s.$code).format(day),
                ),
              ),
              const Divider(size: 20, direction: Axis.vertical),
              if (!isSameDay(day, DateTime.now()))
                IconButton(
                  onPressed: _goToToday,
                  iconButtonMode: IconButtonMode.large,
                  icon: Row(
                    children: [
                      const Icon(FluentIcons.goto_today),
                      const SizedBox(width: 5),
                      Txt(txt("today"))
                    ],
                  ),
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
                    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: BorderSide(
                            color:
                                colorsWithoutYellow[DateTime.now().weekday - 1]
                                    .withValues(alpha: 1)))),
                  ),
                ),
            ],
          );
        },
        defaultBuilder: (context, day, focusedDay) {
          return DayCell(day: day, type: DayCellType.normal);
        },
        todayBuilder: (context, day, focusedDay) {
          return DayCell(day: day, type: DayCellType.today);
        },
        selectedBuilder: (context, day, focusedDay) {
          return DayCell(day: day, type: DayCellType.selected);
        },
        markerBuilder: (context, day, events) {
          return events.isEmpty
              ? null
              : AppointmentsNumberIndicator(events: events, day: day);
        },
      ),
      onDaySelected: (newDate, focusedDay) {
        setState(() => selectedDate = newDate);
      },
    );
  }

  // ─── Day title bar ─────────────────────────────────────────────────────
  Widget _buildDayTitleBar(List<Item> items) {
    return Container(
      decoration: topBarDecoration(context, Colors.grey),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: 45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => setState(() {
              localSettings.toggleEventsViewMode();
            }),
            icon: Row(
              spacing: 10,
              mainAxisSize: MainAxisSize.min,
              children: [
                Txt(
                  " ${DF.commonDate(selectedDate)}",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Tooltip(
                    message: localSettings.calendarEventsViewMode ==
                            EventsViewMode.agenda
                        ? txt("switchToTimelineView")
                        : txt("switchToAgendaView"),
                    child: Icon(
                      localSettings.calendarEventsViewMode ==
                              EventsViewMode.agenda
                          ? WindowsIcons.group_list
                          : WindowsIcons.grid_view,
                      size: 20,
                    )),
              ],
            ),
          ),
          if (login.perm(Perm.revenue).read)
            Row(
              children: [
                if (showPayments)
                  MoneyDisplay(
                    "💵 ${(items as List<Appointment>).fold<double>(0, (amount, appointment) => amount + appointment.paid)} ${currency()}",
                    style: const TextStyle(fontSize: 13),
                  ),
                const SizedBox(width: 5),
                ToggleButton(
                  checked: showPayments,
                  onChanged: (x) {
                    setState(() {
                      showPayments = x;
                    });
                  },
                  child: Row(
                    children: [
                      showPayments
                          ? const Icon(FluentIcons.view)
                          : const Icon(FluentIcons.hide2),
                      const SizedBox(width: 5),
                      Text(txt("payments")),
                    ],
                  ),
                ),
              ],
            )
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared leaf widgets
// ─────────────────────────────────────────────────────────────────────────────

class AppointmentsNumberIndicator extends StatelessWidget {
  final List<Object?> events;
  final DateTime day;
  const AppointmentsNumberIndicator({
    super.key,
    required this.events,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    return Txt(
      events.length.toString(),
      style: TextStyle(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.bold,
        fontSize: 10,
        color: Colors.white,
        shadows: [
          ...kElevationToShadow[1]!,
          Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 2,
              offset: const Offset(0, 0)),
          Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 15,
              offset: const Offset(0, 0)),
          ...List.generate(
            10,
            (index) => Shadow(
                color: colorsWithoutYellow[day.weekday - 1].withValues(
                    alpha: min(roundToPrecision(events.length / 30, 2), 1)),
                blurRadius: 1),
          )
        ],
      ),
    );
  }
}

enum DayCellType {
  today,
  selected,
  normal,
}

class DayCell extends StatelessWidget {
  final DateTime day;
  final DayCellType type;
  const DayCell({
    super.key,
    required this.day,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: type == DayCellType.normal
              ? [
                  Colors.grey.withAlpha(10),
                  Colors.grey.withAlpha(20),
                ]
              : type == DayCellType.today
                  ? [
                      colorsWithoutYellow[day.weekday - 1].withAlpha(20),
                      colorsWithoutYellow[day.weekday - 1].withAlpha(100),
                    ]
                  : [
                      colorsWithoutYellow[day.weekday - 1],
                      colorsWithoutYellow[day.weekday - 1].lighter,
                    ],
        ),
        shape: BoxShape.circle,
        boxShadow: type == DayCellType.selected ? kElevationToShadow[2] : null,
      ),
      child: Center(
        child: Txt(intl.DateFormat("d", locale.s.$code).format(day),
            style: type == DayCellType.normal
                ? null
                : const TextStyle(color: Colors.white)),
      ),
    );
  }
}
