import 'dart:async';
import 'dart:io';

import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/apns_token.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/utils/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FirebaseMessagingService {
  factory FirebaseMessagingService.instance() => _instance;
  FirebaseMessagingService._internal();
  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();
  AuthorizationStatus? authStatus = AuthorizationStatus.denied;

  /// Apple platforms only hand out an FCM token once APNs has registered this
  /// app, which happens asynchronously after launch.
  static bool get _isApplePlatform => Platform.isIOS || Platform.isMacOS;

  /// Initialize Firebase Messaging and sets up all message listeners
  Future<bool> init() async {
    // 1. Request permission
    await _requestPermission();
    if (authStatus != AuthorizationStatus.authorized &&
        authStatus != AuthorizationStatus.provisional) {
      return false;
    }
    // 2. register listeners

    // The app posts its own local notification for a foreground push, so iOS
    // must not also present the alert FCM carries (no-op elsewhere).
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    // Listen for messages when the app is in background
    FirebaseMessaging.onBackgroundMessage(backgroundMsg);

    // Listen for messages when the app is open (foreground)
    FirebaseMessaging.onMessage.listen(PushListeners.foregroundMsg);

    // 3. listen for when a message caused the app to open
    FirebaseMessaging.onMessageOpenedApp
        .listen(PushListeners.causedTheAppToOpen);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Awaits the session restore, so it cannot be awaited here: this runs
      // before the first frame.
      unawaited(
        PushListeners.causedTheAppToOpen(initialMessage).catchError(
          (Object error, StackTrace stack) => logger(
            'Could not open the notification that launched the app: $error',
            stack,
          ),
        ),
      );
    }

    // 4. Generate (and upload) token. This is not awaited: Apple platforms can
    // take seconds to register with APNs, and init() runs before the first
    // frame. A token that arrives later is still registered with the relay.
    unawaited(
      _handlePushNotificationsToken().catchError(
        (Object error, StackTrace stack) => logger(
          'Could not set up the push notifications token: $error',
          stack,
        ),
      ),
    );

    return true;
  }

  Future<void> _handlePushNotificationsToken() async {
    // Subscribed before the token is fetched: FCM also emits a token through
    // this stream the first time it issues one, and a token that arrives while
    // APNs is still registering must not be missed.
    FirebaseMessaging.instance.onTokenRefresh.listen((newFCMToken) {
      if (newFCMToken.isEmpty) return;
      final previousToken = login.pushNotificationsToken;
      login.pushNotificationsToken = newFCMToken;
      // An empty previous token registers this device for the first time
      // instead of replacing one the relay never saw.
      unawaited(PushRelay.replaceToken(previousToken, newFCMToken));
    }).onError((Object error) {
      logger('Error refreshing FCM token: $error', StackTrace.current);
    });

    if (_isApplePlatform && await _waitForAPNSToken() == null) {
      // Not fatal: `getToken` throws `apns-token-not-set` until APNs registers,
      // and the refresh listener above registers the device once FCM issues a
      // token. identifyDevice() also retries on the next login.
      logger(
        'No APNs token yet; waiting for the FCM token refresh.',
        StackTrace.current,
        2,
      );
      return;
    }

    // No vapidKey: it identifies a web push subscription
    // (web/fcm/constants.js) and the native plugins ignore it.
    final String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (error) {
      logger('Could not read the FCM token: $error', StackTrace.current, 2);
      return;
    }

    if (token == null || token.isEmpty) {
      logger(
        'FCM has not issued a token yet; waiting for the token refresh.',
        StackTrace.current,
        2,
      );
      return;
    }

    login.pushNotificationsToken = token;
  }

  Future<String?> _waitForAPNSToken() async {
    try {
      return await waitForAPNSToken(FirebaseMessaging.instance.getAPNSToken);
    } catch (error) {
      logger('Could not read the APNs token: $error', StackTrace.current, 2);
      return null;
    }
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
