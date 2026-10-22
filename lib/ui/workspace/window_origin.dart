import 'package:flutter/gestures.dart';

/// Where the last tap or click landed.
///
/// A window opened from a row, a cell or a menu item belongs at that row, not at
/// the panel's side of the screen — and the row does not have to thread its own
/// position through every opener to say so. One recorder notes the pointer, and
/// [WindowsManager.showStandalone] reads it.
///
/// The recording is **global** rather than per-widget, and that is the whole
/// point: a context menu lives in the navigator's overlay, *above* the app's own
/// widgets, so a listener inside the app never sees the tap that chose a menu
/// item. The window such a tap opens would then appear where some earlier,
/// unrelated tap was — the common path, since a row's menu is how most windows
/// are asked for.
///
/// The position is in the app's own coordinates; whoever places a window brings
/// it into its own frame first.
///
/// Deliberately view state, not model state: nothing is persisted, and a window
/// that has been placed keeps its own place however the pointer moves afterwards.
abstract final class WindowOrigin {
  static Offset? _last;
  static bool _installed = false;

  /// Starts recording where the pointer lands. Safe to call more than once.
  ///
  /// The route is global rather than per-widget, so it sees the taps that land
  /// on the navigator's overlay as well as the ones that land on the app.
  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_record);
  }

  static void _record(PointerEvent event) {
    if (event is PointerDownEvent) _last = event.position;
  }

  /// The last recorded position, in the app's own coordinates, or null before
  /// the first tap.
  static Offset? get last => _last;

  /// Records [position], in the app's own coordinates.
  static void record(Offset position) => _last = position;

  /// Forgets the recorded position — for a test that opens windows with no tap
  /// behind them.
  static void clear() => _last = null;
}
