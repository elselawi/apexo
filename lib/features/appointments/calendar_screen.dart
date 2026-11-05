import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/clip.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:table_calendar/table_calendar.dart';
import 'appointments_store.dart';
import 'new_appointment_dialog.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [
          appointments.observableMap.stream,
          appointments.filterByOperatorID.stream,
          // A follow-up lives on the patient, and the day's band must lose a
          // face the moment the promise is taken back — wherever it was taken
          // back from.
          patients.observableMap.stream,
          followUpRevision.stream,
          // The feature can be switched off under an open calendar.
          globalSettings.observableMap.stream,
        ],
        builder: (context, snapshot) {
          return WeekAgendaCalendar(
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
                    if (!fitsInCodePoints(name, 17)) {
                      name = "${clipCodePoints(name, 14)}...";
                    }
                    return ComboBoxItem(value: account.id, child: Text(name));
                  }),
                ],
                onChanged: login.perm(Perm.appointments).exact(1)
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
              // The calendar moved the visit: apply the move to the visit's one
              // draft, so a form open on it goes dirty instead of being reverted
              // by its next Save (plan §2.6a).
              appointmentCommand(item.id, (draft) => draft.date = item.date);
            },
            onSelect: openAppointment,
            followUpsOnDay: followUpsOn,
            onBookFollowUp: login.perm(Perm.appointments).none
                ? null
                : (followUp, {at}) async {
              // The same sheet "add appointment" opens, with the two answers it
              // would have asked for — whose visit, and which day — already
              // given. A face dropped on the timeline keeps the hour it was
              // dropped on.
              final created = await addAppointment(
                context,
                day: at ?? followUp.date,
                patientID: followUp.patient.id,
              );
              if (created == null) return;
              await openAppointment(created);
            },
            onAddNew: (selectedDate) async {
              // The sheet asks for what a visit needs — whose it is and when —
              // and the visit is stored before its panel opens, so no visit is
              // ever a draft.
              final created =
                  await addAppointment(context, day: selectedDate);
              if (created == null) return;
              await openAppointment(created);
            },
          );
        });
  }
}
