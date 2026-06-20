import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Card;
import 'package:flutter/material.dart' show TimeOfDay, showTimePicker;
import 'package:intl/intl.dart' as intl;
import 'appointments_store.dart';

// ─── Agenda (plain list) view ───────────────────────────────────────────

/// Simple list view of appointments, shown when [CalendarViewMode.agenda]
/// is selected.
class AgendaListView<Item extends Appointment> extends StatelessWidget {
  final List<Item> items;
  final bool showPayments;
  final void Function(Item item) onSelect;
  final void Function(Item item) onSetTime;

  const AgendaListView({
    super.key,
    required this.items,
    required this.showPayments,
    required this.onSelect,
    required this.onSetTime,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        color: Colors.transparent,
        child: Center(
          child: InfoBar(
            isLong: false,
            isIconVisible: true,
            severity: InfoBarSeverity.warning,
            title: Txt(txt("noAppointmentsForThisDay")),
          ),
        ),
      );
    }
    final sortedItems = [...items]..sort((a, b) =>
        a.date.millisecondsSinceEpoch - b.date.millisecondsSinceEpoch);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: sortedItems.length,
      itemBuilder: (context, index) {
        final item = sortedItems[index];
        return Padding(
          padding: const EdgeInsets.all(0),
          child: AppointmentCalendarTile<Item>(
            key: WK.calendarAppointmentTile,
            context: context,
            showPayments: showPayments,
            item: item,
            onSelect: onSelect,
            onSetTime: onSetTime,
          ),
        );
      },
    );
  }
}

// ─── Appointment list tile ──────────────────────────────────────────────

class AppointmentCalendarTile<Item extends Appointment>
    extends StatelessWidget {
  final Item item;
  final void Function(Item item) onSetTime;
  final void Function(Item item) onSelect;
  final bool showPayments;
  const AppointmentCalendarTile({
    super.key,
    required this.context,
    required this.item,
    required this.onSetTime,
    required this.onSelect,
    required this.showPayments,
  });

  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
      ),
      child: ListTile(
        key: ValueKey(item.id),
        margin: EdgeInsets.zero,
        shape: listDividerBorder(context),
        tileColor: WidgetStateColor.resolveWith((states) {
          if (item.isDone) {
            return Colors.blue.withAlpha(10);
          } else if (states.contains(WidgetState.hovered)) {
            return FluentTheme.of(context)
                .resources
                .controlAltFillColorTertiary;
          }
          return FluentTheme.of(context).resources.solidBackgroundFillColorBase;
        }),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                SizedBox(width: 165, child: ItemTitle(item: item)),
              ],
            ),
            Column(
              children: [
                if (item.hasLabwork) ...[
                  const Icon(FluentIcons.manufacturing, size: 17),
                  const SizedBox(height: 5),
                ],
                TreatmentLabels(
                    labels: item.teeth.entries
                        .toSet()
                        .map((e) => TreatmentLabel(
                            string: e.value,
                            color: labelToColor(e.value),
                            icon: labelToIcon(e.value),
                            iso: e.key,
                            extraNote: item.teethExtraNotes[e.key]))
                        .toList()),
              ],
            )
          ],
        ),
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
                      style: CheckboxThemeData(
                        icon: WindowsIcons.completed,
                        uncheckedIconColor: WidgetStatePropertyAll(
                            FluentTheme.of(context).inactiveColor),
                      ),
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
                Row(
                  spacing: 2,
                  children: [
                    if ((item.patient?.phonesString ?? '').isNotEmpty)
                      PhoneNumberButton(phoneNumbers: item.patient!.phone),
                    if ((item.patient?.email ?? '').isNotEmpty)
                      EmailButton(email: item.patient!.email),
                    if ((item.patient?.allAppointments ?? []).length > 1)
                      AppointmentsHistoryFlyout(
                        patient: item.patient!,
                        exclude: item,
                      ),
                  ],
                ),
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
                if (item.paid > 0 &&
                    login.perm(Perm.revenue).read &&
                    showPayments)
                  MoneyDisplay(
                    "💵 ${item.paid.toStringAsFixed(2)} ${currency()}",
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
