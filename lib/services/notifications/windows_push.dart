import 'windows_push_platform_stub.dart'
    if (dart.library.io) 'windows_push_platform_io.dart' as platform;

export 'windows_push_service.dart';

/// Entry point for Windows Notification Services (WNS) pushes.
///
/// Windows is the one platform whose transport is not Firebase. Receiving is
/// started from [Messaging.initializeReceiving] before login; registration and
/// toast-click promotion are requested separately, so no non-Windows build
/// imports the channel plumbing.
abstract final class WindowsPush {
  /// Whether this build can use WNS at all: only a native Windows build can.
  static bool get isSupportedPlatform => platform.isWindowsPlatform;

  /// Starts the native receiver and launch-payload capture. Safe to call before
  /// any session exists.
  static Future<void> startReceiving() => platform.startWindowsPushReceiving();

  /// Requests registration for the current kind of session. The service waits
  /// for the session coordinator to publish a usable session, then registers in
  /// the background; this method does not wait for the network.
  static void requestRegistration({required bool isPatient}) =>
      platform.requestWindowsPushRegistration(isPatient: isPatient);

  /// Reveals a hidden push process and cancels its pending exit. A no-op when
  /// there is no hidden process (or this is not Windows).
  static Future<void> promoteToInteractive() =>
      platform.promoteWindowsPushInstance();
}
