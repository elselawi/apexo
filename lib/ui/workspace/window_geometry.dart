import 'dart:math' as math;

/// The least of a window that must stay on screen when dragged: its header and
/// a strip of body below it.
const double kWindowMinVisible = 96.0;

final class WindowDemand {
  const WindowDemand({
    required this.width,
    required this.minHeight,
    this.maxHeight = double.infinity,
  });

  /// The width the window is drawn at — already capped to the room available.
  final double width;

  /// Shorter than this and the body scrolls, which a floating window must not do.
  final double minHeight;

  /// Infinity by default, for windows that follow their content; capped for ones
  /// like the dental chart and the visit list.
  final double maxHeight;
}

/// A window's screen coordinates. The reading direction decides where a row
/// starts, never where an already-placed window sits.
final class WindowPlacement {
  const WindowPlacement({required this.left, required this.top});

  final double left;
  final double top;

  WindowPlacement moved({required double dx, required double dy}) =>
      WindowPlacement(left: left + dx, top: top + dy);

  @override
  bool operator ==(Object other) =>
      other is WindowPlacement && other.left == left && other.top == top;

  @override
  int get hashCode => Object.hash(left, top);

  @override
  String toString() => 'WindowPlacement(left: $left, top: $top)';
}

final class WindowBounds {
  const WindowBounds({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  /// The two limits a window may not cross.
  final double left;
  final double right;

  final double top;
  final double bottom;

  double get width => math.max(0.0, right - left);

  /// The room between the top and the bottom of the screen.
  double get height => math.max(0.0, bottom - top);

  /// Keeps [placement] inside these bounds: fully inside horizontally, but only
  /// [kWindowMinVisible] of it vertically, so it cannot be dragged off screen.
  WindowPlacement clamp(WindowPlacement placement, {required double width}) {
    final maxLeft = math.max(left, right - width);
    final maxTop = math.max(top, bottom - kWindowMinVisible);
    return WindowPlacement(
      left: placement.left.clamp(left, maxLeft),
      top: placement.top.clamp(top, maxTop),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WindowBounds &&
      other.left == left &&
      other.right == right &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, right, top, bottom);
}

final class WindowSlot {
  const WindowSlot({required this.placement, required this.height});

  final WindowPlacement placement;

  /// The tallest a window in this place may be drawn — the room one row has.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is WindowSlot &&
      other.placement == placement &&
      other.height == height;

  @override
  int get hashCode => Object.hash(placement, height);

  @override
  String toString() => 'WindowSlot($placement, ${height}px)';
}
