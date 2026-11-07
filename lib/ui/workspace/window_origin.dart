import 'package:flutter/gestures.dart';

/// Where the last tap or click landed, in the app's own coordinates.
/// Recording is global because context menus live in the navigator overlay, above
/// the app's widgets, so a per-widget listener never sees the tap that chose one.
abstract final class WindowOrigin {
  static Offset? _last;
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_record);
  }

  static void _record(PointerEvent event) {
    if (event is PointerDownEvent) _last = event.position;
  }

  static Offset? get last => _last;

  /// Records [position], in the app's own coordinates.
  static void record(Offset position) => _last = position;

  static void clear() => _last = null;
}
