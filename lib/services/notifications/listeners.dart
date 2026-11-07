import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/firebase_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/core_local_notification.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/push_interpretation.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/utils/logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Two notices for one change are merged within this window: it spans the gap
/// between the realtime pull and the relay push, but not two real edits.
const Duration staticNotificationDedupeWindow = Duration(seconds: 30);

final Map<String, DateTime> _seenNotifications = {};

/// Dedupe key for one change: store, record, create/update and the sorted
/// field/value tuples, since the two producers may order fields differently.
String staticNotificationKey(PushData data) {
  final indices = List<int>.generate(
      data.updatedFields.length, (index) => index)
    ..sort((a, b) => data.updatedFields[a].compareTo(data.updatedFields[b]));
  final changes = [
    for (final index in indices)
      [
        data.updatedFields[index],
        index < data.oldVals.length ? data.oldVals[index] : null,
        index < data.newVals.length ? data.newVals[index] : null,
      ],
  ];
  return '${data.store}|${data.id}|'
      '${data.isCreation ? 'create' : 'update'}|${jsonEncode(changes)}';
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

/// Adds an in-app notice for [pushData] once per dedupe window; [ding] also
/// plays the notification sound (used by the store sync path).
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

/// Decodes `{"payload": "<PushData JSON>"}` from any transport's data map.
/// Windows delivers the same envelope, so this is not FCM-specific.
({String raw, PushData data})? pushPayloadOfData(Map<String, dynamic>? data) {
  final raw = data?["payload"];
  if (raw is! String || raw.isEmpty) return null;
  return tryParsePushPayload(raw);
}

({String raw, PushData data})? pushPayloadOf(RemoteMessage message) =>
    pushPayloadOfData(message.data);

({String raw, PushData data})? tryParsePushEnvelope(String? envelope) {
  if (envelope == null || envelope.isEmpty) return null;
  try {
    final decoded = jsonDecode(envelope);
    if (decoded is! Map<String, dynamic>) return null;
    return pushPayloadOfData(decoded);
  } catch (_) {
    return null;
  }
}

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

/// Runs in a separate isolate: only background-safe work here; navigation is
/// deferred to the foreground callbacks.
@pragma('vm:entry-point')
void backgroundNotificationResponse(NotificationResponse response) {
}

/// Background FCM handler; stays top-level so the isolate entry point resolves.
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

  unawaited(PushListeners._addStaticNotification(pushData));

  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && !Platform.isWindows && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    final local = LocalNotificationsService.instance();
    await local.init();
    await local.showNotification(tuple[0], tuple[1], parsed.raw);
  }
}

abstract class PushListeners {
  @visibleForTesting
  static Future<void> Function(
    String? title,
    String? body,
    String? payload,
  ) showLocalNotification = (title, body, payload) async {
    await Messaging.local?.showNotification(title, body, payload);
  };

  /// Set by the initializer on Windows. A callback keeps the Windows-native
  /// channel out of every other platform that imports this file.
  static Future<void> Function()? promoteWindowsInstanceIfApplicable;

  /// Synchronizes the notice's store before adding the in-app notice, so the
  /// record exists when it is opened; a tap navigates instead of re-showing it.
  static Future<void> handlePushData(
    PushData pushData, {
    bool openedFromNotification = false,
  }) async {
    await login.ready;
    await patientSide.ready;
    if (login.token.isEmpty && patientSide.patientID.isEmpty) {
      return;
    }

    final session = await notificationSessions.waitForUsableSession();
    if (session == null || !notificationSessions.isCurrent(session)) return;
    final sessionRevision = session.generation;
    if (pushData.store == "appointments") {
      await appointments.synchronize();
    }

    if (pushData.store == "notes") {
      await notes.synchronize();
    }
    if (notificationSessions.revision != sessionRevision) return;

    await _addStaticNotification(pushData);
    if (notificationSessions.revision != sessionRevision) return;

    if (openedFromNotification) {
      // Sync once more if the record is missing; the local store may be stale.
      if (pushData.store == "appointments" &&
          appointments.get(pushData.id) == null) {
        await appointments.synchronize();
        if (notificationSessions.revision != sessionRevision) return;
      }
      _navigateTo(pushData);
      return;
    }

    final tuple = pushData.displayTuple();
    await showLocalNotification(
      tuple[0],
      tuple[1],
      jsonEncode(pushData.toJson()),
    );
  }

  static Future<void> foregroundMsg(RemoteMessage message) async {
    final parsed = pushPayloadOf(message);
    if (parsed == null) return;
    await handlePushData(parsed.data);
  }

  static void openAppointmentIfExist(String id) {
    final WidgetsBinding binding;
    try {
      binding = WidgetsBinding.instance;
    } catch (_) {
      // A background isolate has no screen on which to open a record.
      return;
    }
    final sessionRevision = notificationSessions.revision;
    binding.addPostFrameCallback((_) {
      if (notificationSessions.revision != sessionRevision) return;
      // Resolve at execution time: the record may have changed since the click.
      unawaited(openAppointmentById(id));
    });
    binding.ensureVisualUpdate();
  }

  /// The toast-click callback. The payload is captured synchronously and handled
  /// asynchronously, so a cold click before session restore is not dropped.
  static void foregroudRes(NotificationResponse response) {
    unawaited(
      handleLocalNotificationClick(response).catchError(
        (Object error, StackTrace stack) async {
          logger(
            "Failed handling a notification click "
            "(${error.runtimeType}).",
            stack,
            2,
          );
        },
      ),
    );
  }

  static Future<void> handleLocalNotificationClick(
    NotificationResponse response,
  ) async {
    // Promote before any session or store work: a toast shown by a hidden push
    // process must reveal that process and cancel its pending exit.
    final promote = promoteWindowsInstanceIfApplicable;
    if (promote != null) await promote();

    final parsed = tryParsePushPayload(response.payload);
    if (parsed == null) return;

    final session = await notificationSessions.waitForUsableSession();
    if (session == null || !notificationSessions.isCurrent(session)) return;

    await handlePushData(parsed.data, openedFromNotification: true);
  }

  /// An FCM tap that launched or resumed the app is handled as a click, so it
  /// navigates instead of showing another notification.
  static Future<void> causedTheAppToOpen(RemoteMessage message) async {
    final parsed = pushPayloadOf(message);
    if (parsed == null) return;
    await handlePushData(parsed.data, openedFromNotification: true);
  }

  /// Opens the record a payload is about.
  static void _navigateTo(PushData pushData) {
    if (pushData.store == "notes") {
      routes.navigate(AppRoute.notes);
    } else if (pushData.store == "appointments") {
      routes.navigate(AppRoute.calendar);
      openAppointmentIfExist(pushData.id);
    }
  }

  static Future<void> _addStaticNotification(PushData pushData) async {
    await dispatchStaticNotification(
      pushData,
      icon: FluentIcons.a_a_d_logo,
    );
  }
}
