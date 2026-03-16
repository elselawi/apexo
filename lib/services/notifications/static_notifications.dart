import 'package:apexo/app/routes.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';

class NotificationAction {
  final Color color;
  final String label;
  final VoidCallback action;
  final String hideOnRoute;
  NotificationAction({
    required this.color,
    required this.label,
    required this.action,
    required this.hideOnRoute,
  });
}

class StaticNotification {
  final IconData icon;
  final String title;
  final String body;
  final List<NotificationAction> actions;

  StaticNotification({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });
}

class _NotificationsService {
  List<Appointment> get todayAppointmentsForYou {
    return dashboardCtrl.todayAppointments
        .where((a) => a.operatorsIDs.contains(login.currentAccountID))
        .toList();
  }

  List<Appointment> get dueLabworks {
    return labworks.due
        .where((a) => a.operatorsIDs.contains(login.currentAccountID))
        .toList();
  }

  List<Patient> get notDeliveredLabworks {
    return labworks.notDelivered
        .where((p) => p.allAppointments.last.operatorsIDs
            .contains(login.currentAccountID))
        .toList();
  }

  List<Note> get incomingPendingNotes {
    return notes.present.values
        .where((n) => n.assignedTo == login.currentAccountID && n.done == false)
        .toList();
  }

  List<Note> get outgoingPendingNotes {
    return notes.present.values
        .where((n) => n.createdBy == login.currentAccountID && n.done == false)
        .toList();
  }

  final List<StaticNotification> _notifications = [];

  void addNotification(StaticNotification notification) {
    _notifications.add(notification);
  }

  List<StaticNotification> get notifications {
    return [
      if (todayAppointmentsForYou.isNotEmpty)
        StaticNotification(
          icon: FluentIcons.goto_today,
          title: txt("appointmentsToday"),
          body:
              '${txt("youHave")} ${todayAppointmentsForYou.length} ${txt("appointmentsSetToday")}',
          actions: [
            NotificationAction(
              color: Colors.blue,
              label: txt("view"),
              action: () => routes.navigate("appointments"),
              hideOnRoute: "appointments",
            )
          ],
        ),
      if (dueLabworks.isNotEmpty)
        StaticNotification(
          icon: FluentIcons.manufacturing,
          title: txt("dueLabworks"),
          body: '${txt("youHave")} ${dueLabworks.length} ${txt("labworksDue")}',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: txt("view"),
                action: () => routes.navigate("labworks"),
                hideOnRoute: "labworks")
          ],
        ),
      if (notDeliveredLabworks.isNotEmpty)
        StaticNotification(
          icon: FluentIcons.manufacturing,
          title: txt("undeliveredLabworks"),
          body:
              '${txt("youHave")} ${notDeliveredLabworks.length} ${txt("labworksNotDelivered")}',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: txt("view"),
                action: () => routes.navigate("labworks"),
                hideOnRoute: "labworks")
          ],
        ),
      if (incomingPendingNotes.isNotEmpty)
        StaticNotification(
          icon: WindowsIcons.reply,
          title: txt("incomingNotes"),
          body:
              '${txt("youHave")} ${incomingPendingNotes.length} ${txt("incomingPendingNotes")}',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: txt("view"),
                action: () => routes.navigate("notes"),
                hideOnRoute: "notes")
          ],
        ),
      if (outgoingPendingNotes.isNotEmpty)
        StaticNotification(
          icon: WindowsIcons.reply_mirrored,
          title: txt("outgoingNotes"),
          body:
              '${txt("youHave")} ${outgoingPendingNotes.length} ${txt("outgoingPendingNotes")}',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: txt("view"),
                action: () => routes.navigate("notes"),
                hideOnRoute: "notes")
          ],
        ),
      ..._notifications,
    ];
  }
}

final staticNotifications = _NotificationsService();
