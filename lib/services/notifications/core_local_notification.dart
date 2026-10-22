import 'package:apexo/services/notifications/listeners.dart';
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

  //Android notification channel configuration
  final _androidChannel = const AndroidNotificationChannel(
    'channel_id',
    'Channel name',
    description: 'Android push notification channel',
    importance: Importance.max,
  );

  //Flag to track initialization status
  bool _isFlutterLocalNotificationInitialized = false;

  //Counter for generating unique notification IDs
  int _notificationIdCounter = 0;

  /// The last notification handed to the OS.
  ///
  /// A device's notification centre cannot be read from Dart, so an end-to-end
  /// test asserts this instead: it is exactly what the platform was asked to
  /// display.
  @visibleForTesting
  ({String? title, String? body, String? payload})? lastShown;

  /// Initializes the local notifications plugin for Android, iOS and macOS.
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
    );

    // Initialize plugin with settings and callback for notification taps
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: PushListeners.foregroudRes,
      onDidReceiveBackgroundNotificationResponse:
          backgroundNotificationResponse,
    );

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

    // Combine platform-specific details
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    lastShown = (title: title, body: body, payload: payload);

    // Display the notification
    await _flutterLocalNotificationsPlugin.show(
      id: _notificationIdCounter++,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }
}
