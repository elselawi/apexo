import 'windows_push_platform_stub.dart'
    if (dart.library.io) 'windows_push_platform_io.dart' as platform;

export 'windows_push_service.dart';

/// WNS push entry point: Windows uses native WNS instead of Firebase, and
/// receiving starts before login while registration is requested separately.
abstract final class WindowsPush {
  /// Whether this build can use WNS at all: only a native Windows build can.
  static bool get isSupportedPlatform => platform.isWindowsPlatform;

  /// Safe to call before any session exists; receiving does not wait for login.
  static Future<void> startReceiving() => platform.startWindowsPushReceiving();

  /// Registers in the background once a matching session is published; it does
  /// not wait for the network.
  static void requestRegistration({required bool isPatient}) =>
      platform.requestWindowsPushRegistration(isPatient: isPatient);

  /// Cancels a hidden push process's pending exit; no-op when there is none.
  static Future<void> promoteToInteractive() =>
      platform.promoteWindowsPushInstance();
}
