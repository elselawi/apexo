import 'package:fluent_ui/fluent_ui.dart';

/// A [FlyoutController] that only gives up its flyout for metric changes that
/// actually invalidate where the flyout was placed.
///
/// [FlyoutController] closes on every [WidgetsBindingObserver.didChangeMetrics]
/// notification. iOS sends those for changes that never move a flyout: the
/// keyboard finishing the dismissal animation, and the status bar and home
/// indicator settling around a touch. A flyout opened while one of those
/// notifications is in flight is popped on its first frame, which reads as
/// every flyout in the app refusing to open (bdlukaa/fluent_ui#1326).
///
/// A view resize still closes the flyout, because the placement it was given no
/// longer holds, and so does a keyboard rising under it.
class AppFlyoutController extends FlyoutController {
  AppFlyoutController() {
    _rememberView();
  }

  double? _width;
  double? _height;
  double? _inset;

  void _rememberView() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final size = view.physicalSize / view.devicePixelRatio;
    _width = size.width;
    _height = size.height;
    _inset = view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;

    final size = view.physicalSize / view.devicePixelRatio;
    final inset = view.viewInsets.bottom / view.devicePixelRatio;

    final resized = (_width != null && _width != size.width) ||
        (_height != null && _height != size.height);
    final keyboardOpened = _inset != null && inset > _inset!;

    _width = size.width;
    _height = size.height;
    _inset = inset;

    if (isOpen && (resized || keyboardOpened)) close<void>();
  }
}
