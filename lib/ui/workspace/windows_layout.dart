import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_geometry.dart';

export 'package:apexo/ui/workspace/window_geometry.dart';

/// Below this width a panel fills the screen: nothing fits beside it, so its
/// floating windows come over it one at a time, as sheets.
const double kWindowsBreakpoint = 710.0;

/// The gap between two floating windows, and between them and the panel.
const double kWindowGap = 12.0;

/// The space the windows area keeps from the far edge of the screen, so a window
/// never touches it.
const double kWindowEdgeInset = 8.0;

/// How far above the tap a window opened from it is put, so the finger or the
/// pointer does not cover the window's own header.
const double kWindowTapLift = 20.0;

/// The room a window opened at a tap keeps under it: a window that would hang
/// off the bottom of the screen is lifted to keep at least this much of itself
/// visible, and scrolls its body if that is less than it wanted.
const double kWindowMinOpeningHeight = 320.0;

/// The width the windows area has on [screenWidth]: what the panel and the gaps
/// leave beside it.
///
/// One function for it, because the panel decides how many windows fit by it and
/// the layer decides how wide to draw them by it — two formulas would drift a
/// few pixels apart and clip the last window in the row.
double windowAreaWidth({
  required double screenWidth,
  required double panelWidth,
  double gap = kWindowGap,
  double edgeInset = kWindowEdgeInset,
}) =>
    math.max(0.0, screenWidth - panelWidth - gap - edgeInset);

/// What a screen can do with a panel's floating windows.
///
/// Pure arithmetic, so the panel's dock and the layer that draws the windows
/// always agree on what is on screen. The width a window is drawn at is not kept
/// here: it is [windowAreaWidth] of the live screen, asked where the geometry is
/// known, so a resize cannot leave a stale number behind.
final class WindowsLayout {
  const WindowsLayout({required this.compact, required this.capacity});

  /// One window over the panel at a time.
  final bool compact;

  /// How many floating windows the screen opens by itself. A window the user
  /// opens afterwards takes its own place — it never pushes another one out.
  final int capacity;
}

/// The layout [floating] get on a screen [screenWidth] wide and [screenHeight]
/// tall, beside a panel [panelWidth] wide.
///
/// Windows are priority-ordered, and they are shown **side by side in one row**:
/// the first ones that fit across the screen open by themselves, and the rest stay
/// in the dock. A window is never opened into a place too short for it either —
/// one that would have to scroll is one to leave in the dock — so nothing is ever
/// stacked, and nothing has to be scrolled to.
WindowsLayout computeWindowsLayout({
  required List<PanelWindow> floating,
  required double screenWidth,
  required double panelWidth,
  required double screenHeight,
  double gap = kWindowGap,
}) {
  if (floating.isEmpty) {
    return const WindowsLayout(compact: false, capacity: 0);
  }
  if (screenWidth < kWindowsBreakpoint) {
    return const WindowsLayout(compact: true, capacity: 1);
  }
  final available = windowAreaWidth(
    screenWidth: screenWidth,
    panelWidth: panelWidth,
    gap: gap,
  );
  // The room one row has to itself: the screen between its two insets.
  final height = math.max(0.0, screenHeight - 2 * kWindowEdgeInset);
  var capacity = 0;
  var used = 0.0;
  for (final window in floating) {
    // A window taller than the screen would have to scroll: it is not one to
    // open, and neither is anything after it (the list is in priority order).
    if (window.minHeight > height + 0.5) break;
    final width = windowWidth(window, available, panelWidth: panelWidth);
    final next = used + (capacity == 0 ? 0 : gap) + width;
    if (next > available + 0.5) break;
    used = next;
    capacity++;
  }
  return WindowsLayout(compact: false, capacity: capacity);
}

/// The width [window] takes in an area [available] wide.
///
/// A side window is exactly as wide as the panel it belongs to — the same
/// column of the screen, mirrored — so a panel and its windows read as one
/// surface. A window that needs more room says so (`matchesPanelWidth: false`)
/// and asks for its own width; either way it never takes more than the area has.
double windowWidth(
  PanelWindow window,
  double available, {
  double panelWidth = 0,
}) {
  final wanted = window.matchesPanelWidth && panelWidth > 0
      ? panelWidth
      : window.preferredWidth;
  return math.min(wanted, available);
}

/// Where the windows a panel opens go: one row, side by side, starting at the
/// edge the panel is on — the trailing side in a left-to-right app, the leading
/// side in a right-to-left one.
///
/// One row, because that is the only arrangement in which every window keeps the
/// height its content needs: two rows halve it, and a window half its height
/// scrolls. The screen opens exactly as many as the row holds
/// ([computeWindowsLayout]), so the row is not expected to overflow at all; a
/// window that arrives anyway — one the user asked for that was placed at a tap,
/// say — keeps its own place rather than being laid over its neighbours.
List<WindowSlot> arrangeWindows({
  required List<WindowDemand> demands,
  required WindowBounds bounds,
  required bool rtl,
  double gap = kWindowGap,
}) {
  if (demands.isEmpty) return const <WindowSlot>[];

  /// The leading edge of a window [width] wide, [offset] in from the edge the
  /// row starts at.
  double leftOf(double offset, double width) =>
      rtl ? bounds.left + offset : bounds.right - offset - width;

  final slots = <WindowSlot>[];
  var offset = 0.0;
  var rowIsFull = false;
  for (final demand in demands) {
    if (offset > 0) offset += gap;
    if (!rowIsFull && offset + demand.width <= bounds.width + 0.5) {
      slots.add(
        WindowSlot(
          placement: bounds.clamp(
            WindowPlacement(
                left: leftOf(offset, demand.width), top: bounds.top),
            width: demand.width,
          ),
          height: bounds.height,
        ),
      );
      offset += demand.width;
      continue;
    }
    // The row is full. The window still gets a place — the caller asked for it —
    // but at the row's edge, within the screen. It lands on the window already
    // there: the row is one row, and a window that does not fit has nowhere
    // else to go. The caller is the one that keeps such a window in the dock.
    rowIsFull = true;
    slots.add(
      WindowSlot(
        placement: bounds.clamp(
          WindowPlacement(left: leftOf(0, demand.width), top: bounds.top),
          width: demand.width,
        ),
        height: bounds.height,
      ),
    );
  }
  return slots;
}

/// Where a window opened from something on the screen appears: at what was
/// tapped, so a list a row asked for comes from that row rather than from the
/// panel's side of the screen.
WindowPlacement placementAt({
  required Offset origin,
  required double width,
  required WindowBounds bounds,
  required bool rtl,
}) {
  // The window opens at the tap and grows away from it, in reading order.
  final left = rtl ? origin.dx - width : origin.dx;
  // A tap near the bottom would open a window that hangs off the screen: lift
  // it to keep a usable part of it — header, body and buttons — in view.
  final maxTop = math.max(bounds.top, bounds.bottom - kWindowMinOpeningHeight);
  return bounds.clamp(
    WindowPlacement(
      left: left,
      top: (origin.dy - kWindowTapLift).clamp(bounds.top, maxTop),
    ),
    width: width,
  );
}
