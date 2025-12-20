import 'dart:math';

import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/swipe_detector.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Card;
import 'package:flutter/material.dart' show Card, TimeOfDay, showTimePicker;
import 'package:intl/intl.dart' as intl;
import '../../utils/colors_without_yellow.dart';
import '../../utils/round.dart';
import '../../common_widgets/item_title.dart';
import 'appointments_store.dart';
import 'package:table_calendar/table_calendar.dart';

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
  late bool showPayments = false;

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

  void _goToToday() {
    setState(() {
      selectedDate = now;
    });
  }

  List<Item> _getItemsForDay(DateTime day) {
    return widget.items.where((item) => isSameDay(day, item.date)).toList();
  }

  List<Item> _getItemsForSelectedDay() {
    return widget.items
        .where((item) => isSameDay(selectedDate, item.date))
        .toList();
  }

  bool isSameDay(DateTime day1, DateTime day2) {
    return day1.day == day2.day &&
        day1.month == day2.month &&
        day1.year == day2.year;
  }

  @override
  Widget build(BuildContext context) {
    var itemsForSelectedDay = _getItemsForSelectedDay();
    return Column(
      children: [
        _buildCommandBar(),
        _buildCalendar(),
        const SizedBox(height: 1),
        Expanded(
          child: SwipeDetector(
            onSwipeLeft: () => setState(() {
              selectedDate = selectedDate.subtract(const Duration(days: 1));
            }),
            onSwipeRight: () => setState(() {
              selectedDate = selectedDate.add(const Duration(days: 1));
            }),
            child: Column(children: [
              _buildCurrentDayTitleBar(itemsForSelectedDay),
              itemsForSelectedDay.isEmpty
                  ? _buildEmptyDayMessage()
                  : _buildAppointmentsList(itemsForSelectedDay),
            ]),
          ),
        ),
      ],
    );
  }

  Acrylic _buildCommandBar() {
    return Acrylic(
      elevation: 150,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
                onPressed: () => widget.onAddNew(selectedDate),
                icon: Row(
                  children: [
                    const Icon(FluentIcons.add_event, size: 17),
                    const SizedBox(width: 10),
                    Txt(txt("add"))
                  ],
                )),
            Row(
              children: widget.actions ?? [],
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildAppointmentsList(List<Item> itemsForSelectedDay) {
    var sortedItems = [...itemsForSelectedDay]..sort((a, b) =>
        a.date.millisecondsSinceEpoch - b.date.millisecondsSinceEpoch);
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: sortedItems.length,
        itemBuilder: (context, index) {
          Item item = sortedItems[index];
          return Padding(
            padding: const EdgeInsets.all(1),
            child: AppointmentCalendarTile<Item>(
              key: WK.calendarAppointmentTile,
              context: context,
              showPayments: showPayments,
              item: item,
              onSelect: (item) {
                widget.onSelect(item);
              },
              onSetTime: (item) {
                widget.onSetTime(item);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyDayMessage() {
    return Expanded(
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: InfoBar(
            isLong: false,
            isIconVisible: true,
            severity: InfoBarSeverity.warning,
            title: Txt(txt("noAppointmentsForThisDay")),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentDayTitleBar(List<Item> itemsForSelectedDay) {
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "dd MMMM"
        : "MMMM dd";
    return Container(
      decoration: BoxDecoration(
          border: BorderDirectional(
              bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
          gradient: LinearGradient(colors: [
            colorsWithoutYellow[selectedDate.weekday - 1]
                .darkest
                .withValues(alpha: 0.08),
            colorsWithoutYellow[selectedDate.weekday - 1].withValues(alpha: 0),
          ])),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: 45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            intl.DateFormat("$df / yyyy", locale.s.$code).format(selectedDate),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if (login.isAdmin)
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
            )
        ],
      ),
    );
  }
}

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
                  Colors.grey.withValues(alpha: 0.02),
                  Colors.grey.withValues(alpha: 0.05),
                ]
              : type == DayCellType.today
                  ? [
                      colorsWithoutYellow[day.weekday - 1]
                          .withValues(alpha: 0.1),
                      colorsWithoutYellow[day.weekday - 1]
                          .withValues(alpha: 0.2),
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

class AppointmentCalendarTile<Item extends Appointment>
    extends StatelessWidget {
  final Item item;
  final void Function(Item item) onSetTime;
  final void Function(Item item) onSelect;
  final bool showPayments;
  const AppointmentCalendarTile(
      {super.key,
      required this.context,
      required this.item,
      required this.onSetTime,
      required this.onSelect,
      required this.showPayments});

  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
        ),
      ),
      child: ListTile(
        title: ItemTitle(item: item),
        subtitle: item.subtitleLine1.isNotEmpty
            ? Txt(item.subtitleLine1, overflow: TextOverflow.ellipsis)
            : null,
        leading: Row(children: [
          routes.panels().where((p) => p.item.id == item.id).isNotEmpty
              ? IconButton(
                  icon: const Icon(FluentIcons.open_in_new_tab),
                  onPressed: () {
                    final index =
                        routes.panels().indexWhere((p) => p.item.id == item.id);
                    if (index == -1) return;
                    routes.bringPanelToFront(index);
                  })
              : Transform.scale(
                  scale: 1.25,
                  child: Checkbox(
                      checked: item.isDone,
                      onChanged: (checked) {
                        item.isDone = checked == true;
                        appointments.set(item as Appointment);
                      }),
                ),
          const SizedBox(width: 8),
          const Divider(direction: Axis.vertical, size: 40),
        ]),
        onPressed: () => onSelect(item),
        trailing: Row(
          children: [
            const Divider(direction: Axis.vertical, size: 40),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () async {
                    final index =
                        routes.panels().indexWhere((p) => p.item.id == item.id);
                    if (index > -1) return routes.bringPanelToFront(index);
                    TimeOfDay? res = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                            hour: item.date.hour, minute: item.date.minute));
                    if (res != null) {
                      item.date = DateTime(item.date.year, item.date.month,
                          item.date.day, res.hour, res.minute);
                      onSetTime(item);
                    }
                  },
                  icon: Row(
                    children: [
                      routes.panels().where((p) => p.item.id == item.id).isEmpty
                          ? const Icon(FluentIcons.clock)
                          : const Icon(FluentIcons.open_in_new_tab),
                      const SizedBox(width: 5),
                      Txt(intl.DateFormat('hh:mm a', locale.s.$code)
                          .format(item.date)),
                    ],
                  ),
                ),
                if (item.subtitleLine2.isNotEmpty)
                  SizedBox(
                      width: 75,
                      child: Txt(
                        item.subtitleLine2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      )),
                if (item.paid > 0 && login.isAdmin && this.showPayments)
                  Txt(
                    "💵 ${item.paid.toStringAsFixed(0)} ${globalSettings.get("currency_______").value}",
                    style: const TextStyle(fontSize: 12),
                  )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
