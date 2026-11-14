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

  // Apple platforms only issue an FCM token once APNs registers the app.
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

    // The app posts its own local notification for foreground pushes, so iOS must
    // not also present FCM's alert (no-op elsewhere).
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    // Listen for messages when the app is in background
    FirebaseMessaging.onBackgroundMessage(backgroundMsg);

    // Listen for messages when the app is open (foreground)
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(
        PushListeners.foregroundMsg(message).catchError(
          (Object error, StackTrace stack) => logger(
            'Could not handle a foreground push notification: $error',
            stack,
          ),
        ),
      );
    });

    // 3. listen for when a message caused the app to open
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(
        PushListeners.causedTheAppToOpen(message).catchError(
          (Object error, StackTrace stack) => logger(
            'Could not open the record from a push notification: $error',
            stack,
          ),
        ),
      );
    });
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Cannot be awaited: it waits for the session restore and this runs before
      // the first frame.
      unawaited(
        PushListeners.causedTheAppToOpen(initialMessage).catchError(
          (Object error, StackTrace stack) => logger(
            'Could not open the notification that launched the app: $error',
            stack,
          ),
        ),
      );
    }

    // Not awaited: Apple registration can take seconds and init() runs before the
    // first frame; a late token is still registered by the refresh listener.
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
    // Subscribed before fetching: FCM also emits the first token on this stream,
    // and one arriving while APNs still registers must not be missed.
    //
    // firebase_messaging 17 deprecates token access in favour of the Firebase
    // installation id (`register()`/`onRegistered`), which the relay cannot
    // address yet, so the token stays until the relay supports direct-send.
    // ignore: deprecated_member_use
    FirebaseMessaging.instance.onTokenRefresh.listen((newFCMToken) {
      if (newFCMToken.isEmpty) return;
      final previousToken = login.pushNotificationsToken;
      login.pushNotificationsToken = newFCMToken;
      // Empty previous token: registers the device instead of replacing one the relay never saw.
      unawaited(PushRelay.replaceToken(previousToken, newFCMToken));
    }).onError((Object error) {
      logger('Error refreshing FCM token: $error', StackTrace.current);
    });

    if (_isApplePlatform && await _waitForAPNSToken() == null) {
      // Not fatal: `getToken` throws `apns-token-not-set` until APNs registers; the
      // refresh listener, or identifyDevice on the next login, registers the device.
      logger(
        'No APNs token yet; waiting for the FCM token refresh.',
        StackTrace.current,
        2,
      );
      return;
    }

    // No vapidKey: it identifies a web push subscription (web/fcm/constants.js)
    // and the native plugins ignore it.
    final String? token;
    try {
      // ignore: deprecated_member_use
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
    try {
      authStatus = (await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ))
          .authorizationStatus;
    } catch (error, stack) {
      // macOS answers `UNErrorCodeNotificationsNotAllowed` (reported by the
      // plugin as `unknown`) instead of prompting when it will not ask again,
      // e.g. after the prompt was shown once and the app quit unanswered.
      // Staying `denied` keeps startup alive; init() then skips the token.
      logger('Could not request notification permission: $error', stack, 2);
    }
  }
}
