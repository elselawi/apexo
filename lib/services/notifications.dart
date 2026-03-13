import 'package:apexo/app/routes.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
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

class Notification {
  final IconData icon;
  final String title;
  final String body;
  final List<NotificationAction> actions;

  Notification({
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

  final List<Notification> _notifications = [];

  List<Notification> get notifications {
    return [
      if (todayAppointmentsForYou.isNotEmpty)
        Notification(
          icon: FluentIcons.goto_today,
          title: 'Today\'s Appointments',
          body: 'You have ${todayAppointmentsForYou.length} appointments today',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: 'View',
                action: () => routes.navigate("appointments"),
                hideOnRoute: "appointments")
          ],
        ),
      if (dueLabworks.isNotEmpty)
        Notification(
          icon: FluentIcons.manufacturing,
          title: 'Due Labworks',
          body: 'You have ${dueLabworks.length} labworks due',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: 'View',
                action: () => routes.navigate("labworks"),
                hideOnRoute: "labworks")
          ],
        ),
      if (notDeliveredLabworks.isNotEmpty)
        Notification(
          icon: FluentIcons.manufacturing,
          title: 'Not Delivered Labworks',
          body:
              'You have ${notDeliveredLabworks.length} labworks not delivered',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: 'View',
                action: () => routes.navigate("labworks"),
                hideOnRoute: "labworks")
          ],
        ),
      if (incomingPendingNotes.isNotEmpty)
        Notification(
          icon: WindowsIcons.reply,
          title: 'Incoming Pending Notes',
          body:
              'You have ${incomingPendingNotes.length} incoming pending notes',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: 'View',
                action: () => routes.navigate("notes"),
                hideOnRoute: "notes")
          ],
        ),
      if (outgoingPendingNotes.isNotEmpty)
        Notification(
          icon: WindowsIcons.reply_mirrored,
          title: 'Outgoing Pending Notes',
          body:
              'You have ${outgoingPendingNotes.length} outgoing pending notes',
          actions: [
            NotificationAction(
                color: Colors.blue,
                label: 'View',
                action: () => routes.navigate("notes"),
                hideOnRoute: "notes")
          ],
        ),
      ..._notifications,
    ];
  }
}

final notifications = _NotificationsService();
