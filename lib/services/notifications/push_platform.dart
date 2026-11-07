import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

/// The relay's `platform` field: FCM carries phones, web and Apple, while
/// Windows uses WNS; the OS is recorded separately so the relay shapes the push.
abstract final class PushPlatform {
  /// The relay's default: a legacy FCM registration with no OS recorded.
  static const String fcm = "fcm";

  /// Windows Notification Services — a transport of its own, not FCM.
  static const String wns = "wns";

  static const String ios = "ios";
  static const String macos = "macos";
  static const String android = "android";
  static const String web = "web";

  /// The resolver [current] asks. Replaced in tests to simulate a platform.
  @visibleForTesting
  static String? Function() resolve = detect;

  /// Null for a platform the relay does not know (Linux); the caller omits the
  /// field and the relay keeps its [fcm] default.
  static String? get current => resolve();

  /// `kIsWeb` first: on the web `defaultTargetPlatform` reports the host OS, not
  /// the browser.
  static String? detect() {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return wns;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }
}
