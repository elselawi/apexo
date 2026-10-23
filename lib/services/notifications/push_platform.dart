import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

/// How a device says it receives pushes, as the relay's `platform` field.
///
/// The relay keeps the transport and the OS apart: FCM carries the pushes for
/// phones, the web and Apple's platforms, while Windows uses Windows
/// Notification Services (WNS). The OS is recorded separately so the relay can
/// shape an FCM message — an iOS alert the system displays, an Android
/// high-priority data message — without changing what carries it.
///
/// These are the only values the relay accepts, besides omitting the field.
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

  /// The platform this build runs on, or `null` when it is not one the relay
  /// knows (Linux).
  ///
  /// Unknown is never guessed: the caller omits the field, and the relay keeps
  /// its [fcm] default instead of being told an OS this build cannot verify.
  static String? get current => resolve();

  /// The real detection.
  ///
  /// `kIsWeb` comes first because on the web `defaultTargetPlatform` reports
  /// the host OS, not the browser.
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
