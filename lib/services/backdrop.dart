import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The window's own material on Windows.
///
/// The runner asks DWM for Mica — the desktop wallpaper, blurred and tinted,
/// composed behind the window — and Flutter draws on top of it. That only
/// shows when the app leaves its own root unpainted, so [native] is read once
/// at startup and gates every background the shell paints. Everywhere else,
/// and on a Windows build where DWM refused, the app paints its own stand-in
/// material instead.
class Backdrop {
  Backdrop._();

  static const MethodChannel _channel = MethodChannel('apexo/backdrop');

  /// Whether the window behind the app is translucent.
  static bool native = false;

  /// Asks the runner to apply the backdrop and remembers whether it did.
  static Future<void> initialize({required bool dark}) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      native = await _channel.invokeMethod<bool>('isNativeMica') ?? false;
    } on PlatformException {
      native = false;
    } on MissingPluginException {
      native = false;
    }
    await setDark(dark);
  }

  /// Follows the app's own theme; the system's is not consulted.
  static Future<void> setDark(bool dark) async {
    if (!native) return;
    try {
      await _channel.invokeMethod<void>('setDark', {'dark': dark});
    } on PlatformException {
      // Only the caption colour is lost.
    } on MissingPluginException {
      // Not a Windows build.
    }
  }
}
