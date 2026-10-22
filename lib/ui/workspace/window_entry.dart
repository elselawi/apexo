part of 'windows_layer.dart';

class _WindowEntry {
  const _WindowEntry.standalone(this.floating)
      : window = null,
        id = '';

  const _WindowEntry.hosted(this.window, this.id) : floating = null;

  final FloatingWindow? floating;
  final PanelWindow? window;

  /// The id the window has inside its owner, for minimizing it.
  final String id;

  String get key => floating?.key ?? id;

  bool get isHosted => floating == null;

  PanelWindow get model => floating?.window ?? window!;

  /// The width it is drawn at in an area [available] wide beside a panel
  /// [panelWidth] wide.
  double widthIn(double available, double panelWidth) =>
      windowWidth(model, available, panelWidth: panelWidth);
}

final class _AreaMetrics {
  const _AreaMetrics({
    required this.panelWidth,
    required this.bounds,
    required this.room,
  });

  final double panelWidth;

  /// The column windows live in: beside the panel when one is open, the screen
  /// when none is.
  final WindowBounds bounds;

  /// The height between the top and the bottom, less a margin: the tallest a
  /// window is drawn.
  final double room;

  double get maxHeight => math.max(120.0, room - 16);
}

/// Fades and lifts a window out of [from] when it arrives, and folds it back
/// when it leaves.
///
/// The animation is driven by a controller rather than by an implicit tween, so
/// the state can never get out of step with the window it draws: a window that
/// is not leaving is *always* fully on screen — a window drawn at zero opacity
/// would still take clicks while showing nothing.
