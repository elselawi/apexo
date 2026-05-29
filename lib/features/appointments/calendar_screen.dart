import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:table_calendar/table_calendar.dart';
import 'calendar_widget.dart';
import 'appointment_model.dart';
import 'appointments_store.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [
          appointments.observableMap.stream,
          appointments.filterByOperatorID.stream
        ],
        builder: (context, snapshot) {
          return WeekAgendaCalendar<Appointment>(
            items: appointments.filtered.values.toList(),
            actions: [
              ComboBox<String>(
                style: const TextStyle(overflow: TextOverflow.ellipsis),
                items: [
                  ComboBoxItem<String>(
                    value: "",
                    child: Txt(txt("allDoctors")),
                  ),
                  ...accounts.operators.map((account) {
                    var name = "🥼 ${accounts.name(account)}";
                    if (name.length > 17) {
                      name = "${name.substring(0, 14)}...";
                    }
                    return ComboBoxItem(value: account.id, child: Text(name));
                  }),
                ],
                onChanged: login.permissions[PInt.appointments] == 1
                    ? null
                    : (id) => appointments.filterByOperatorID(id ?? ""),
                value: appointments.filterByOperatorID(),
              ),
            ],
            startDay: StartingDayOfWeek.values.firstWhere(
                (v) => v.name == globalSettings.startDayOfWeek,
                orElse: () => StartingDayOfWeek.monday),
            initiallySelectedDay: DateTime.now().millisecondsSinceEpoch,
            onSetTime: (item) {
              appointments.set(item);
            },
            onSelect: openAppointment,
            onAddNew: (selectedDate) {
              openAppointment(Appointment.fromJson({
                "date": selectedDate.millisecondsSinceEpoch / 60000,
                if (login.permissions[PInt.patients] == 1 ||
                    login.permissions[PInt.appointments] == 1 ||
                    login.currentLoginIsOperator)
                  "operatorsIDs": [login.currentAccountID]
              }));
            },
          );
        });
  }
}
