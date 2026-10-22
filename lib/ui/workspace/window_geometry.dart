import 'dart:math' as math;

/// The arithmetic a floating window is placed by: where it sits, how much room
/// it may be put in, and what it asks of the row it is opened in.
///
/// Pure values, kept apart from the layout that arranges them, so a caller that
/// only needs to move or clamp a window does not import the arrangement policy.

/// The least of a window that must stay on screen when it is dragged — its
/// header, and enough under it to know it is a window.
const double kWindowMinVisible = 96.0;

/// What one window asks of the row it is put in: how wide it is drawn, the height
/// below which its body would have to scroll, and the height it stops growing at.
final class WindowDemand {
  const WindowDemand({
    required this.width,
    required this.minHeight,
    this.maxHeight = double.infinity,
  });

  /// The width the window is drawn at — already capped to the room available.
  final double width;

  /// The height it stays usable at: shorter and it scrolls, which no floating
  /// window may do.
  final double minHeight;

  /// The height it stops growing at. A window with no ceiling follows its
  /// content, so more room is always welcome; one with a ceiling (the dental
  /// chart, the visit list) is happy at that height and no higher.
  final double maxHeight;
}

/// Where a window sits on the screen: how far its leading edge is from the
/// screen's leading edge, and how far its top is from the top of the screen.
///
/// Screen coordinates, so a drag moves a window the way the pointer moves it,
/// and a window put at the row it was opened from stays at that row. The reading
/// direction only decides where windows *start* — a row begins at the edge the
/// panel is on — never where a window already placed lives.
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

/// Where a window may be put: the column beside the panel — or the whole screen
/// when no panel is open — between the top and the bottom of the screen.
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

  /// Keeps [placement] inside these bounds: a window dragged past an edge comes
  /// back, so it can never be lost off the screen.
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

/// One place a window may be put: where its corner goes, and how much room the
/// place has.
///
/// The height is what keeps a window honest: a window is as tall as its content
/// up to [maxHeight], and the layer caps it at the room it was given, so no window
/// runs past the bottom of the screen.
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
