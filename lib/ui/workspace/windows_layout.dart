import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_geometry.dart';
import 'package:apexo/ui/workspace/window_group.dart';

export 'package:apexo/ui/workspace/window_geometry.dart';

/// Below this width a panel fills the screen and its windows become sheets.
const double kWindowsBreakpoint = 710.0;

/// The gap between two floating windows, and between them and the panel.
const double kWindowGap = 12.0;

/// The space the windows area keeps from the far edge of the screen.
const double kWindowEdgeInset = 8.0;

/// Space above windows for the workspace command and its bottom gap.
const double kWorkspaceCommandHeight = 64.0;

/// How far above the tap a window opens, so the pointer does not cover its header.
const double kWindowTapLift = 20.0;

/// Room a tap-opened window keeps below its top before its real height is known;
/// the layer re-places it at the measured height ([placementAt]).
const double kWindowMinOpeningHeight = 320.0;

/// The width the windows area has on [screenWidth]. One function, because the
/// panel's fit count and the layer's drawing would otherwise drift apart.
double windowAreaWidth({
  required double screenWidth,
  required double panelWidth,
  double gap = kWindowGap,
  double edgeInset = kWindowEdgeInset,
}) =>
    math.max(0.0, screenWidth - panelWidth - gap - edgeInset);

/// What a screen can do with a panel's floating windows. Pure arithmetic, so the
/// panel's dock and the layer that draws the windows cannot disagree.
final class WindowsLayout {
  const WindowsLayout({required this.compact, required this.capacity});

  /// One window over the panel at a time.
  final bool compact;

  /// How many floating windows the screen opens by itself; one the user opens
  /// afterwards takes its own place.
  final int capacity;
}

/// How many of [floating] fit side by side beside the panel; the rest stay in the
/// dock, and a window too tall for the row is not opened either.
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
    // A window too tall for the row would scroll, so stop: the list is in
    // priority order.
    if (window.minHeight > height + 0.5) break;
    final width = windowWidth(window, available, panelWidth: panelWidth);
    final next = used + (capacity == 0 ? 0 : gap) + width;
    if (next > available + 0.5) break;
    used = next;
    capacity++;
  }
  return WindowsLayout(compact: false, capacity: capacity);
}

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

/// One record's windows as a block of the row; each slot keeps its own remembered
/// layout.
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

  /// Window ids the user left open here: null means never arranged (the group's
  /// first picks open), an empty list means they chose none.
  final List<String>? remembered;

  String keyOf(PanelWindow window) => rowKey(slot, window.id);
}

/// What one row shows: the window keys in draw order and the width each takes; a
/// bare count cannot say which of the mixed widths fit.
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

  /// The selected window keys in draw order, from the panel's edge outwards.
  final List<String> selected;

  /// Width of every candidate by row key, docked ones included, so opening one
  /// from the dock can tell whether it still fits.
  final Map<String, double> widths;

  /// The width the selected windows take, gaps included.
  final double used;

  /// The width the row has to work with.
  final double available;

  /// The height a window needs to be shown whole.
  final double room;

  bool isSelected(String key) => selected.contains(key);

  double widthOf(String key) => widths[key] ?? 0;

  bool sameSelection(WindowsPlan other) =>
      compact == other.compact &&
      used == other.used &&
      selected.length == other.selected.length &&
      selected.every(other.selected.contains);
}

/// Plans the row beside a panel: the focused window first, then each group's
/// remembered picks, then first picks; a candidate that does not fit is skipped.
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
    // An arranged group (remembered != null) opens only what the user left open.
    if (group.remembered != null) continue;
    for (final window in group.windows) {
      // Attachments are never first picks; only byDefault windows open alone.
      if (window.isAttachment || !window.byDefault) continue;
      tryWindow(group.keyOf(window));
    }
  }

  var used = 0.0;
  final chosen = <String>{};
  for (final key in tried) {
    final candidate = byKey[key]!;
    // Too short for the row, so it stays in the dock; a later window may ask for
    // less height.
    if (key != focus && candidate.window.minHeight > room + 0.5) continue;
    final width = widths[key] ?? 0;
    final next = used + (chosen.isEmpty ? 0 : gap) + width;
    if (next > available + 0.5) continue;
    used = next;
    chosen.add(key);
  }

  return WindowsPlan(
    compact: false,
    // Drawn in record order, group by group, not in the order they were tried.
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

/// Lays out the one row from the panel's edge (mirrored in RTL). A window past
/// the row's width still gets the first slot; callers keep those in the dock.
List<WindowSlot> arrangeWindows({
  required List<WindowDemand> demands,
  required WindowBounds bounds,
  required bool rtl,
  double gap = kWindowGap,
}) {
  if (demands.isEmpty) return const <WindowSlot>[];

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
    // Row is full: the window still gets the first slot, on top of what is there,
    // because the caller is what keeps an overflowing window in the dock.
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

/// Where a window from a tap goes: at the tap, lifted just enough to stay on
/// screen; [kWindowMinOpeningHeight] stands in until its real [height] is known.
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
