import 'dart:convert';
import 'dart:io';

import 'package:apexo/app/routes.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/firebase_options.dart';
import 'package:apexo/services/notifications/core_local_notification.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/model_push_data.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// This function is called when a background message is received.
/// It initializes the local notifications plugin and shows the notification.
/// It should stay top-level to avoid isolate issues.
@pragma('vm:entry-point')
Future<void> backgroundMsg(RemoteMessage message) async {
  final payload = jsonDecode(message.data["payload"]);
  final pushData = PushData.fromJson(payload);
  final tuple = pushData.displayTuple();

  PushListeners._addStaticNotification(pushData);

  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb || Platform.isWindows == false) {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }
  if (kIsWeb == false && (Platform.isAndroid || Platform.isIOS)) {
    final local = LocalNotificationsService.instance();
    await local.init();
    await local.showNotification(tuple[0], tuple[1], message.data["payload"]);
  }
}

abstract class PushListeners {
  static Future<void> foregroundMsg(RemoteMessage message) async {
    final payload = jsonDecode(message.data["payload"]);
    final pushData = PushData.fromJson(payload);
    final tuple = pushData.displayTuple();
    _addStaticNotification(pushData);
    await Messaging.local?.showNotification(
      tuple[0],
      tuple[1],
      message.data["payload"],
    );
  }

  static void foregroudRes(NotificationResponse res) {
    final payload = jsonDecode(res.payload!);
    final pushData = PushData.fromJson(payload);
    if (pushData.store == "notes") {
      routes.navigate("notes");
    } else if (pushData.store == "appointments") {
      routes.navigate("calendar");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openAppointment(appointments.get(pushData.id));
      });
    }
  }

  static void causedTheAppToOpen(RemoteMessage message) {
    // not completely implemented yet
    // the following code is just a placeholder
    // and it's not even working!
    // it is hard to test this function
    // not worth the effort for now

    final payload = jsonDecode(message.data["payload"]);
    final pushData = PushData.fromJson(payload);
    _addStaticNotification(pushData);
  }

  static void backgroundRes(NotificationResponse res) {
    final payload = jsonDecode(res.payload!);
    final pushData = PushData.fromJson(payload);
    if (pushData.store == "notes") {
      routes.navigate("notes");
    } else if (pushData.store == "appointments") {
      routes.navigate("calendar");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openAppointment(appointments.get(pushData.id));
      });
    }
  }

  static void _addStaticNotification(PushData pushData) {
    final tuple = pushData.displayTuple();
    staticNotifications.addNotification(
      StaticNotification(
        icon: FluentIcons.a_a_d_logo,
        title: tuple[0],
        body: tuple[1],
        actions: [
          NotificationAction(
            color: Colors.blue,
            label: 'View',
            action: () {
              if (pushData.store == "notes") {
                routes.navigate("notes");
              } else if (pushData.store == "appointments") {
                routes.navigate("calendar");
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  openAppointment(appointments.get(pushData.id));
                });
              }
            },
            hideOnRoute: pushData.store == "notes" ? "notes" : "calendar",
          ),
        ],
      ),
    );
  }
}
