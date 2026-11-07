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

  // Shared Darwin settings. FirebaseMessagingService requests the app-wide
  // display permission before this, so asking again would only repeat it.
  final _darwinInitializationSettings = const DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  // The AUMID and activation GUID must match what the packaging declares, so
  // both come from WindowsNotificationIdentity.
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

  // Non-Windows plugins do not treat the id as a persistent tag, so a counter
  // is enough.
  int _notificationIdCounter = 0;

  /// Windows toast id allocation. A test replaces this to avoid Hive.
  @visibleForTesting
  static Future<int> Function() windowsNotificationId =
      toast_ids.nextWindowsNotificationId;

  /// The last notification handed to the OS. An end-to-end test asserts this
  /// because the notification centre cannot be read from Dart.
  @visibleForTesting
  ({String? title, String? body, String? payload})? lastShown;

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

    // A cold toast click can arrive before the session is restored, so do not
    // inspect credentials here; the handler waits at the session boundary.
    var callbackSeen = false;
    String? launchDetailsPayload;
    Timer? launchDetailsTimer;
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        callbackSeen = true;
        if (launchDetailsPayload != null &&
            launchDetailsPayload == response.payload) {
          // Launch-details recovery already handled this exact cold click.
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

    // The Windows plugin reports a cold click through the callback or, on some
    // builds, only through `getNotificationAppLaunchDetails`; handle it once.
    try {
      final launch = await _flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (!callbackSeen &&
          (launch?.didNotificationLaunchApp ?? false) &&
          response != null) {
        launchDetailsPayload = response.payload;
        PushListeners.foregroudRes(response);
        // The duplicate callback arrives during startup; expire the suppression
        // so a later click on the same toast still works.
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

    // Banner/list cover newer Apple systems, where `presentAlert` no longer
    // applies.
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
    );

    // Windows defaults are enough: the toast uses the AUMID registered at init.
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
      // A failed allocation must not fall back to tag zero, the collision the
      // persistent allocator prevents; use a random 31-bit id for this toast.
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
