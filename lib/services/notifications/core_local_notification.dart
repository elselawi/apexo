import 'dart:async';
import 'dart:math';

import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/notifications/windows_notification_identity.dart';
import 'package:apexo/services/notifications/windows_toast_ids_stub.dart'
    if (dart.library.io) 'package:apexo/services/notifications/windows_toast_ids_io.dart'
    as toast_ids;
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  //Factory constructor to return singleton instance
  factory LocalNotificationsService.instance() => _instance;
  LocalNotificationsService._internal();

  //Singleton instance
  static final LocalNotificationsService _instance =
      LocalNotificationsService._internal();

  //Main plugin instance for handling notifications
  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

  //Android-specific initialization settings using app launcher icon
  final _androidInitializationSettings =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  // iOS and macOS initialization settings, shared since both use the same
  // Darwin plugin. Permission is not requested here: FirebaseMessagingService
  // asks for it before local notifications are initialized, and the display
  // permission is app-wide, so asking again would only repeat the request.
  final _darwinInitializationSettings = const DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  // Windows settings: the app name shown on the toast, the MSIX identity that
  // may display as this app, and the COM class id the plugin registers for
  // activation. All three live in WindowsNotificationIdentity so the packaging
  // uses the same values.
  final _windowsInitializationSettings = const WindowsInitializationSettings(
    appName: WindowsNotificationIdentity.appName,
    appUserModelId: WindowsNotificationIdentity.appUserModelId,
    guid: WindowsNotificationIdentity.activationGuid,
  );

  //Android notification channel configuration
  final _androidChannel = const AndroidNotificationChannel(
    'channel_id',
    'Channel name',
    description: 'Android push notification channel',
    importance: Importance.max,
  );

  //Flag to track initialization status
  bool _isFlutterLocalNotificationInitialized = false;

  //Counter for generating unique notification IDs on platforms whose plugin
  // does not use the id as a persistent toast tag.
  int _notificationIdCounter = 0;

  /// Windows toast id allocation. A test replaces this to avoid Hive.
  @visibleForTesting
  static Future<int> Function() windowsNotificationId =
      toast_ids.nextWindowsNotificationId;

  /// The last notification handed to the OS.
  ///
  /// A device's notification centre cannot be read from Dart, so an end-to-end
  /// test asserts this instead: it is exactly what the platform was asked to
  /// display.
  @visibleForTesting
  ({String? title, String? body, String? payload})? lastShown;

  /// Initializes the local notifications plugin for Android, iOS, macOS and
  /// Windows.
  Future<void> init() async {
    if (_isFlutterLocalNotificationInitialized) {
      return;
    }

    // Create plugin instance
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Combine platform-specific settings
    final initializationSettings = InitializationSettings(
      android: _androidInitializationSettings,
      iOS: _darwinInitializationSettings,
      macOS: _darwinInitializationSettings,
      windows: _windowsInitializationSettings,
    );

    // A cold toast click can arrive through this callback while the app is
    // still restoring its session. Do not inspect credentials here: the
    // asynchronous handler captures the payload immediately and waits for the
    // real session boundary.
    var callbackSeen = false;
    String? launchDetailsPayload;
    Timer? launchDetailsTimer;
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        callbackSeen = true;
        if (launchDetailsPayload != null &&
            launchDetailsPayload == response.payload) {
          // The launch-details recovery below already handed this exact cold
          // click to the shared handler.
          launchDetailsPayload = null;
          launchDetailsTimer?.cancel();
          launchDetailsTimer = null;
          return;
        }
        PushListeners.foregroudRes(response);
      },
      onDidReceiveBackgroundNotificationResponse:
          backgroundNotificationResponse,
    );

    // The Windows plugin can deliver a cold click through the callback during
    // initialization, but some plugin/platform combinations only expose it via
    // `getNotificationAppLaunchDetails`. Handle it exactly once, and only if the
    // callback did not already do so.
    try {
      final launch = await _flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (!callbackSeen &&
          (launch?.didNotificationLaunchApp ?? false) &&
          response != null) {
        launchDetailsPayload = response.payload;
        PushListeners.foregroudRes(response);
        // The duplicate callback, when there is one, arrives during startup.
        // Do not suppress a genuine later click on the same toast forever.
        launchDetailsTimer = Timer(const Duration(seconds: 2), () {
          launchDetailsPayload = null;
          launchDetailsTimer = null;
        });
      }
    } catch (error, stack) {
      logger(
        "Could not read the notification launch details "
        "(${error.runtimeType}).",
        stack,
        2,
      );
    }

    // Create Android notification channel
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // Mark initialization as complete
    _isFlutterLocalNotificationInitialized = true;
  }

  /// Show a local notification with the given title, body, and payload.
  Future<void> showNotification(
    String? title,
    String? body,
    String? payload,
  ) async {
    if (!_isFlutterLocalNotificationInitialized) {
      await init();
    }
    // Android-specific notification details
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.max,
      priority: Priority.high,
    );

    // iOS and macOS notification details. The banner and list presentations
    // cover the newer Apple systems, where `presentAlert` no longer applies.
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
    );

    // Combine platform-specific details. Windows has no per-notification
    // settings beyond its defaults here: the toast is shown under the AUMID
    // the initialization settings registered.
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: const WindowsNotificationDetails(),
    );

    final id = await _allocateNotificationId();

    lastShown = (title: title, body: body, payload: payload);

    // Display the notification
    await _flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  Future<int> _allocateNotificationId() async {
    if (PushPlatform.current != PushPlatform.wns) {
      return _notificationIdCounter++;
    }
    try {
      return await windowsNotificationId();
    } catch (error, stack) {
      // A failed allocation must not silently reuse tag zero: that is exactly
      // the collision the persistent allocator exists to prevent. Fall back to
      // a random positive 31-bit id for this toast, and log only the kind.
      logger(
        "Could not allocate a Windows notification id "
        "(${error.runtimeType}); using a per-process fallback.",
        stack,
        2,
      );
      return 1 + Random.secure().nextInt(toast_ids.maxWindowsNotificationId);
    }
  }
}
