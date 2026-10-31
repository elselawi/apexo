import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_geometry.dart';
import 'package:apexo/ui/workspace/window_group.dart';

export 'package:apexo/ui/workspace/window_geometry.dart';

/// Below this width a panel fills the screen: nothing fits beside it, so its
/// floating windows come over it one at a time, as sheets.
const double kWindowsBreakpoint = 710.0;

/// The gap between two floating windows, and between them and the panel.
const double kWindowGap = 12.0;

/// The space the windows area keeps from the far edge of the screen, so a window
/// never touches it.
const double kWindowEdgeInset = 8.0;

/// Space above windows for the workspace command and its bottom gap.
const double kWorkspaceCommandHeight = 64.0;

/// How far above the tap a window opened from it is put, so the finger or the
/// pointer does not cover the window's own header.
const double kWindowTapLift = 20.0;

/// The room a window opened at a tap keeps under it **before its own height is
/// known**: such a window is lifted to keep at least this much of itself visible,
/// and a first frame that turns out taller than that scrolls until the layer has
/// measured it and lifted it by its real height ([placementAt]).
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

/// One record's windows, as a group the row is planned from.
///
/// The panel's own record and the record it carries beside itself are demanded
/// separately, because they have different widths and different memories — and
/// because a window in the row must always be able to say whose it is.
final class WindowGroupDemand {
  const WindowGroupDemand({
    required this.slot,
    required this.windows,
    this.remembered,
  });

  /// The block of the row this group fills — see [kHostSlot], [kAttachedSlot].
  final String slot;

  /// The windows the record offers, in the order it offers them.
  final List<PanelWindow> windows;

  /// The window ids the user left open in this slot: null when they never
  /// touched it (the group's own first picks open), an empty list when they
  /// chose to leave none (nothing of this group opens by itself).
  final List<String>? remembered;

  String keyOf(PanelWindow window) => rowKey(slot, window.id);
}

/// What one row shows, decided once and in full.
///
/// A count of windows cannot describe this row: the chart is 960 wide and a
/// pre-op form 560, so "three windows fit" says nothing about *which* three. The
/// plan names the windows, in row order, with the width each one takes — so the
/// layer draws exactly what the panel promised, and the dock puts away exactly
/// what did not fit (plan §6.2-5).
final class WindowsPlan {
  const WindowsPlan({
    required this.compact,
    required this.selected,
    required this.widths,
    required this.used,
    required this.available,
    required this.room,
  });

  /// Nothing on screen — what a panel with no windows at all gets.
  static const WindowsPlan none = WindowsPlan(
    compact: false,
    selected: <String>[],
    widths: <String, double>{},
    used: 0,
    available: 0,
    room: 0,
  );

  /// One window over the panel at a time: a phone draws sheets, not a row.
  final bool compact;

  /// The windows on screen, by row key ([rowKey]), **in row order** — the order
  /// they are drawn in, from the panel's edge outwards.
  final List<String> selected;

  /// The width every candidate window takes, by row key — the selected ones and
  /// the ones left in the dock, because opening one from the dock afterwards has
  /// to know whether it still fits.
  final Map<String, double> widths;

  /// The width the selected windows take, gaps included.
  final double used;

  /// The width the row has to work with.
  final double available;

  /// The height a window needs to be shown whole.
  final double room;

  bool isSelected(String key) => selected.contains(key);

  double widthOf(String key) => widths[key] ?? 0;

  /// Whether the same windows are on screen as [other] — the question a resize
  /// asks before rearranging.
  bool sameSelection(WindowsPlan other) =>
      compact == other.compact &&
      used == other.used &&
      selected.length == other.selected.length &&
      selected.every(other.selected.contains);
}

/// What the row shows beside a panel [panelWidth] wide on a screen
/// [screenWidth] wide and [screenHeight] tall, with the windows [groups] offer.
///
/// Rules, in order (plan §6.2-5):
///
/// 1. A phone draws one window: the one the opener asked for, else nothing —
///    a sheet the user did not ask for is in the way of the panel.
/// 2. Candidates are the focused window, then each group's remembered picks,
///    then the remaining windows of a group the user has never arranged.
/// 3. Each candidate is placed if it fits **and** if the row is tall enough for
///    it; a candidate that does not fit is skipped, not fatal — a narrower
///    window later in the list may still fit, which is the whole point of
///    mixed widths.
/// 4. What is left over stays in its dock. Nothing overflows, nothing scrolls,
///    and there is never a second row.
WindowsPlan computeWindowsPlan({
  required double screenWidth,
  required double screenHeight,
  required double panelWidth,
  required List<WindowGroupDemand> groups,
  String? focus,
  double gap = kWindowGap,
}) {
  final available = windowAreaWidth(
    screenWidth: screenWidth,
    panelWidth: panelWidth,
    gap: gap,
  );
  // The room one row has to itself: the screen between its two insets.
  final room = math.max(0.0, screenHeight - 2 * kWindowEdgeInset);

  /// Every window the row could show, and the order the record offers them in.
  final rowOrder = <String>[];
  final byKey = <String, ({PanelWindow window, WindowGroupDemand group})>{};
  for (final group in groups) {
    for (final window in group.windows) {
      final key = group.keyOf(window);
      if (byKey.containsKey(key)) continue;
      rowOrder.add(key);
      byKey[key] = (window: window, group: group);
    }
  }
  if (byKey.isEmpty) return WindowsPlan.none;

  final widths = <String, double>{
    for (final key in rowOrder)
      key: windowWidth(byKey[key]!.window, available, panelWidth: panelWidth),
  };

  if (screenWidth < kWindowsBreakpoint) {
    final selected = focus != null && byKey.containsKey(focus)
        ? <String>[focus]
        : const <String>[];
    return WindowsPlan(
      compact: true,
      selected: selected,
      widths: widths,
      used: selected.isEmpty ? 0 : (widths[selected.first] ?? 0),
      available: available,
      room: room,
    );
  }

  // The order candidates are *tried* in — not the order they are drawn in.
  final tried = <String>[];
  void tryWindow(String? key) {
    if (key == null || !byKey.containsKey(key) || tried.contains(key)) return;
    tried.add(key);
  }

  tryWindow(focus);
  for (final group in groups) {
    for (final id in group.remembered ?? const <String>[]) {
      tryWindow(rowKey(group.slot, id));
    }
  }
  for (final group in groups) {
    // A group the user has arranged opens exactly what they left open. One they
    // have never touched opens its own first picks, in its own order.
    if (group.remembered != null) continue;
    for (final window in group.windows) {
      // An attachment is never a first pick: it hangs off the window it belongs
      // to, behind that window's own chip. A record's workspace does open by
      // itself; a secondary editor does not.
      if (window.isAttachment || !window.byDefault) continue;
      tryWindow(group.keyOf(window));
    }
  }

  var used = 0.0;
  final chosen = <String>{};
  for (final key in tried) {
    final candidate = byKey[key]!;
    // Too short for it: it would have to scroll, so it stays in the dock. Not a
    // reason to stop — a later window may ask for less height.
    if (key != focus && candidate.window.minHeight > room + 0.5) continue;
    final width = widths[key] ?? 0;
    final next = used + (chosen.isEmpty ? 0 : gap) + width;
    if (next > available + 0.5) continue;
    used = next;
    chosen.add(key);
  }

  return WindowsPlan(
    compact: false,
    // Drawn in the record's own order, group by group: the visit's windows
    // nearest the panel, the patient's further out (plan §4.1).
    selected: <String>[
      for (final key in rowOrder)
        if (chosen.contains(key)) key
    ],
    widths: widths,
    used: used,
    available: available,
    room: room,
  );
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
///
/// A tap near the bottom would open a window that hangs off the screen, so the
/// window is lifted — but only as far as it has to be. Once its own [height] is
/// known, that is exactly far enough for the whole window to sit above the bottom
/// edge: put any lower, it would be scrolled before it was ever read. Until then
/// [kWindowMinOpeningHeight] stands in for the height.
WindowPlacement placementAt({
  required Offset origin,
  required double width,
  required WindowBounds bounds,
  required bool rtl,
  double? height,
}) {
  // The window opens at the tap and grows away from it, in reading order.
  final left = rtl ? origin.dx - width : origin.dx;
  final room = height ?? kWindowMinOpeningHeight;
  final maxTop = math.max(bounds.top, bounds.bottom - room);
  return bounds.clamp(
    WindowPlacement(
      left: left,
      top: (origin.dy - kWindowTapLift).clamp(bounds.top, maxTop),
    ),
    width: width,
  );
}
