import 'package:apexo/services/notifications/listeners.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  LocalNotificationsService._internal();

  //Singleton instance
  static final LocalNotificationsService _instance =
      LocalNotificationsService._internal();

  //Factory constructor to return singleton instance
  factory LocalNotificationsService.instance() => _instance;

  //Main plugin instance for handling notifications
  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

  //Android-specific initialization settings using app launcher icon
  final _androidInitializationSettings =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  final _iosInitializationSettings = const DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
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

  /// Initializes the local notifications plugin for Android and iOS.
  Future<void> init() async {
    if (_isFlutterLocalNotificationInitialized) {
      return;
    }

    // Create plugin instance
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Combine platform-specific settings
    final initializationSettings = InitializationSettings(
      android: _androidInitializationSettings,
      iOS: _iosInitializationSettings,
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
    // Android-specific notification details
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.max,
      priority: Priority.high,
    );

    // iOS-specific notification details
    const iosDetails = DarwinNotificationDetails();

    // Combine platform-specific details
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

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
