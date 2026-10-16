import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/firebase_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/core_local_notification.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// How long two notices for the same change are treated as the same event:
/// long enough to cover the gap between the realtime pull and the relay's push
/// for one change, short enough to never merge two real edits.
const Duration staticNotificationDedupeWindow = Duration(seconds: 30);

final Map<String, DateTime> _seenNotifications = {};

/// The key two notices for the *same* change share: store, record,
/// create-or-update and the changed fields (sorted, since the two producers may
/// list them in any order).
String staticNotificationKey(PushData data) {
  final fields = [...data.updatedFields]..sort();
  return '${data.store}|${data.id}|'
      '${data.isCreation ? 'create' : 'update'}|${fields.join(',')}';
}

/// Forgets every dedupe key (e.g., on logout or between tests).
void resetStaticNotificationDedupe() => _seenNotifications.clear();

void _pruneSeenNotifications(DateTime now) {
  _seenNotifications.removeWhere(
    (_, seenAt) => now.difference(seenAt) >= staticNotificationDedupeWindow,
  );
}

/// Builds the navigation actions for a [PushData] item.
List<NotificationAction> actionsForPushData(PushData pushData) {
  if (pushData.store != "notes" && pushData.store != "appointments") {
    return const [];
  }
  return [
    NotificationAction(
      color: Colors.blue,
      label: txt("view"),
      action: () {
        if (pushData.store == "notes") {
          routes.navigate(AppRoute.notes);
        } else if (pushData.store == "appointments") {
          routes.navigate(AppRoute.calendar);
          PushListeners.openAppointmentIfExist(pushData.id);
        }
      },
      hideOnRoute:
          pushData.store == "notes" ? AppRoute.notes : AppRoute.calendar,
    ),
  ];
}

/// Dispatches an in-app notification for [pushData] unless the same change
/// was already notified within [staticNotificationDedupeWindow].
///
/// When [ding] is true, plays the Windows notification sound and shows a toast
/// (used by the store sync path).
Future<bool> dispatchStaticNotification(
  PushData pushData, {
  IconData? icon,
  DateTime? clock,
  bool ding = false,
}) async {
  final now = clock ?? DateTime.now();
  _pruneSeenNotifications(now);
  final key = staticNotificationKey(pushData);
  if (_seenNotifications.containsKey(key)) return false;
  _seenNotifications[key] = now;

  final tuple = pushData.displayTuple();
  final resolvedIcon = icon ?? FluentIcons.a_a_d_logo;
  final actions = actionsForPushData(pushData);

  if (ding) {
    await staticNotifications.dingANotification(
      title: tuple[0],
      body: tuple[1],
      icon: resolvedIcon,
      actions: actions,
    );
  } else {
    staticNotifications.addNotification(
      StaticNotification(
        icon: resolvedIcon,
        title: tuple[0],
        body: tuple[1],
        actions: actions,
      ),
    );
  }
  return true;
}

/// Safely extracts and decodes the [PushData] payload from a [RemoteMessage].
/// Returns `null` if the message has no valid `"payload"` JSON string.
({String raw, PushData data})? pushPayloadOf(RemoteMessage message) {
  final raw = message.data["payload"];
  if (raw is! String || raw.isEmpty) return null;
  return tryParsePushPayload(raw);
}

/// Safely parses a raw JSON string into [PushData], returning `null` if
/// [raw] is null, empty, or malformed JSON.
({String raw, PushData data})? tryParsePushPayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return (raw: raw, data: PushData.fromJson(decoded));
  } catch (_) {
    return null;
  }
}

/// The background notification callback runs in a separate isolate. It may
/// only perform background-safe work; route navigation is deferred until the
/// app is resumed through the normal FCM/local foreground callbacks.
@pragma('vm:entry-point')
void backgroundNotificationResponse(NotificationResponse response) {
  // Intentionally no UI access or store synchronization in a background
  // isolate. The payload remains available to the platform notification.
}

/// This function is called when a background message is received.
/// It initializes the local notifications plugin and shows the notification.
/// It should stay top-level to avoid isolate issues.
@pragma('vm:entry-point')
Future<void> backgroundMsg(RemoteMessage message) async {
  await login.ready;
  await patientSide.ready;

  if (login.token.isEmpty && patientSide.patientID.isEmpty) {
    return;
  }

  final parsed = pushPayloadOf(message);
  if (parsed == null) return;
  final pushData = parsed.data;
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
    await local.showNotification(tuple[0], tuple[1], parsed.raw);
  }
}

abstract class PushListeners {
  static Future<void> foregroundMsg(RemoteMessage message) async {
    if (login.token.isEmpty && patientSide.patientID.isEmpty) {
      return;
    }

    final parsed = pushPayloadOf(message);
    if (parsed == null) return;
    final pushData = parsed.data;

    if (pushData.store == "appointments") {
      await appointments.synchronize();
    }

    if (pushData.store == "notes") {
      await notes.synchronize();
    }

    final tuple = pushData.displayTuple();
    _addStaticNotification(pushData);
    await Messaging.local?.showNotification(
      tuple[0],
      tuple[1],
      parsed.raw,
    );
  }

  static void openAppointmentIfExist(String id) {
    if (appointments.get(id) == null) {
      return;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openAppointment(appointments.get(id));
      });
    }
  }

  static void foregroudRes(NotificationResponse res) {
    if (login.token.isEmpty && patientSide.patientID.isEmpty) {
      return;
    }
    final parsed = tryParsePushPayload(res.payload);
    if (parsed == null) return;
    final pushData = parsed.data;
    if (pushData.store == "notes") {
      routes.navigate(AppRoute.notes);
    } else if (pushData.store == "appointments") {
      routes.navigate(AppRoute.calendar);
      openAppointmentIfExist(pushData.id);
    }
  }

  static void causedTheAppToOpen(RemoteMessage message) {
    if (login.token.isEmpty && patientSide.patientID.isEmpty) {
      return;
    }
    final parsed = pushPayloadOf(message);
    if (parsed == null) return;
    final pushData = parsed.data;
    _addStaticNotification(pushData);
  }

  static void _addStaticNotification(PushData pushData) {
    unawaited(
      dispatchStaticNotification(
        pushData,
        icon: FluentIcons.a_a_d_logo,
      ),
    );
  }
}
