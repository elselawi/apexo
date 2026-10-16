import 'dart:io';

import 'package:apexo/app/app.dart';
import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/windows_ding/sound_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:toastification/toastification.dart';

class NotificationAction {
  NotificationAction({
    required this.color,
    required this.label,
    required this.action,
    required this.hideOnRoute,
  });
  final Color color;
  final String label;
  final VoidCallback action;

  /// The route this action is pointless on — the notice hides its button
  /// there. `null` means it never hides.
  final AppRoute? hideOnRoute;
}

class StaticNotification {
  StaticNotification({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });
  final IconData icon;
  final String title;
  final String body;
  final List<NotificationAction> actions;
}

class _NotificationsService {
  final ObservableState<int> state = ObservableState(0);

  List<Appointment> get todayAppointmentsForYou {
    if (login.currentAccountID.isEmpty) return const [];
    return dashboardCtrl.todayAppointments
        .where((a) => a.operatorsIDs.contains(login.currentAccountID))
        .toList();
  }

  List<Appointment> get dueLabworks {
    if (login.currentAccountID.isEmpty) return const [];
    return labworks.due
        .where((a) => a.operatorsIDs.contains(login.currentAccountID))
        .toList();
  }

  List<Patient> get notDeliveredLabworks {
    if (login.currentAccountID.isEmpty) return const [];
    return labworks.notDeliveredPatients
        .where((p) =>
            p.allAppointments.isNotEmpty &&
            p.allAppointments.last.operatorsIDs
                .contains(login.currentAccountID))
        .toList();
  }

  List<Note> get incomingPendingNotes {
    if (login.currentAccountID.isEmpty) return const [];
    return notes.present.values
        .where((n) =>
            n.isNote &&
            n.assignedTo == login.currentAccountID &&
            n.done == false)
        .toList();
  }

  List<Note> get outgoingPendingNotes {
    if (login.currentAccountID.isEmpty) return const [];
    return notes.present.values
        .where((n) =>
            n.isNote &&
            n.createdBy == login.currentAccountID &&
            n.done == false)
        .toList();
  }

  final List<StaticNotification> _notifications = [];

  void addNotification(StaticNotification notification) {
    _notifications.add(notification);
    state(state() + 1);
  }

  void clear() {
    if (_notifications.isEmpty) return;
    _notifications.clear();
    state(state() + 1);
  }

  Future<void> dingANotification({
    required String title,
    required String body,
    required IconData icon,
    List<NotificationAction> actions = const [],
  }) async {
    addNotification(
      StaticNotification(
        icon: icon,
        title: title,
        body: body,
        actions: actions,
      ),
    );

    if (kIsWeb || Platform.isWindows == false) {
      // the sound and should only be visible on windows
      // since there are currently no other way to support
      // windows notifications other than this
      return;
    }

    triggerSound();

    try {
      if (!bContext.mounted) return;
    } catch (_) {
      return;
    }

    toastification.show(
      context: bContext,
      type: ToastificationType.info,
      style: ToastificationStyle.flat,
      title: Text(title),
      description: Text(body),
      alignment: locale.isRtl ? Alignment.bottomLeft : Alignment.bottomRight,
      autoCloseDuration: const Duration(seconds: 4),
      icon: Icon(icon),
      borderRadius: BorderRadius.circular(12.0),
      boxShadow: lowModeShadow,
      direction: locale.isRtl ? TextDirection.rtl : TextDirection.ltr,
      dragToClose: true,
      applyBlurEffect: true,
    );
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
              action: () => routes.navigate(AppRoute.calendar),
              hideOnRoute: AppRoute.calendar,
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
                action: () => routes.navigate(AppRoute.labworks),
                hideOnRoute: AppRoute.labworks)
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
                action: () => routes.navigate(AppRoute.labworks),
                hideOnRoute: AppRoute.labworks)
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
                action: () => routes.navigate(AppRoute.notes),
                hideOnRoute: AppRoute.notes)
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
                action: () => routes.navigate(AppRoute.notes),
                hideOnRoute: AppRoute.notes)
          ],
        ),
      ..._notifications,
    ];
  }
}

final staticNotifications = _NotificationsService();
