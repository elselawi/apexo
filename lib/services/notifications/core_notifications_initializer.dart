import 'dart:io';

import 'package:apexo/firebase_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/core_firebase_messaging.dart';
import 'package:apexo/services/notifications/core_local_notification.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/services/notifications/windows_push.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/utils/logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:apexo/utils/js/js_bridge.dart';

class Messaging {
  static FirebaseMessagingService? firebase;
  static LocalNotificationsService? local;

  /// Starts the platform's notification stack. Windows has no Firebase, so its
  /// native receiving starts before login to catch a push that launched the app.
  static Future<void> initializeReceiving() async {
    if (PushPlatform.current == PushPlatform.wns) {
      // A cold toast click can arrive before `startReceiving`, so wire the
      // promotion hook first; it is a no-op unless the process started hidden.
      PushListeners.promoteWindowsInstanceIfApplicable =
          WindowsPush.promoteToInteractive;
      local = LocalNotificationsService.instance();
      try {
        await local!.init();
      } catch (error, stack) {
        logger("Could not initialize Windows notifications: $error", stack, 2);
      }
      try {
        await WindowsPush.startReceiving();
      } catch (error, stack) {
        logger("Could not start Windows push receiving: $error", stack, 2);
      }
      return;
    }

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebase = FirebaseMessagingService.instance();
      await firebase!.init();
      local = LocalNotificationsService.instance();
      await local!.init();
    }
  }

  static Future<void> identifyDevice({bool isPatient = false}) async {
    final platform = PushPlatform.current;

    // Windows registration runs in the background off login's critical path: it
    // needs a session snapshot and a native channel, not the relay key.
    if (platform == PushPlatform.wns) {
      WindowsPush.requestRegistration(isPatient: isPatient);
      return;
    }

    // ensure clinic key.. which is a key needed to communicate with the relay server
    final relayKey =
        isPatient ? patientSide.relayKey : await PushRelay.ensureKey();

    if (platform == PushPlatform.web) {
      final server = isPatient ? patientSide.server : login.url;
      final id = isPatient ? patientSide.patientID : login.currentAccountID;

      JSBridge.setGlobalVariable("clinicKey", relayKey);
      JSBridge.setGlobalVariable("clinicServer", server);
      JSBridge.setGlobalVariable("accountId", id);
      JSBridge.setGlobalVariable("lang", locale.s.$code);
      JSBridge.setGlobalVariable("shouldShowPrompt", "yes");
      return;
    }

    // A platform the app cannot name (`null`, e.g. Linux) is left out rather
    // than claimed, so the relay keeps its FCM default.
    if (firebase != null &&
        (firebase!.authStatus == AuthorizationStatus.authorized ||
            firebase!.authStatus == AuthorizationStatus.provisional)) {
      await PushRelay.putDevice(isPatient: isPatient, platform: platform);
    }
  }
}
