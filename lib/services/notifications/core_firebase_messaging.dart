import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/utils/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FirebaseMessagingService {
  FirebaseMessagingService._internal();
  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();
  factory FirebaseMessagingService.instance() => _instance;
  AuthorizationStatus? authStatus = AuthorizationStatus.denied;

  /// Initialize Firebase Messaging and sets up all message listeners
  Future<bool> init() async {
    // 1. Request permission
    await _requestPermission();
    if (authStatus != AuthorizationStatus.authorized) {
      return false;
    }
    // 2. Generate (and upload) token
    await _handlePushNotificationsToken();

    // 3. register listeners

    // Listen for messages when the app is in background
    FirebaseMessaging.onBackgroundMessage(backgroundMsg);

    // Listen for messages when the app is open (foreground)
    FirebaseMessaging.onMessage.listen(PushListeners.foregroundMsg);

    // 4. listen for when a message caused the app to open
    FirebaseMessaging.onMessageOpenedApp
        .listen(PushListeners.causedTheAppToOpen);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      PushListeners.causedTheAppToOpen(initialMessage);
    }

    return true;
  }

  Future<void> _handlePushNotificationsToken() async {
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey:
          'BHWli6L0suAP_c70qr8IrPgMdvlXfxwOp6GGaI2cnZD5kfJN9kUBxeyUS5q31y3pffeKFK3wQZlB0VBQeDpkvJ0',
    );
    login.pushNotificationsToken = token ?? "";
    FirebaseMessaging.instance.onTokenRefresh.listen((newFCMToken) {
      PushRelay.replaceToken(login.pushNotificationsToken, newFCMToken);
      login.pushNotificationsToken = newFCMToken;
    }).onError((error) {
      logger('Error refreshing FCM token: $error', StackTrace.current);
    });
  }

  Future<void> _requestPermission() async {
    authStatus = (await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    ))
        .authorizationStatus;
  }
}
