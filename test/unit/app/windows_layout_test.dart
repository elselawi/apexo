/// The arithmetic behind the window layout, pinned on its own: how wide a window
/// is drawn, how many open by themselves, and where a window is put. The widgets
/// only place what these answer, so a mistake here would show up as a clipped,
/// missing or unreachable window and nothing else could explain it.
library;

import 'package:apexo/ui/workspace/panel_width.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wide window of its own — the chart's width, but the test's own number: a
/// test of the layout must not depend on a feature's chart.
const double chartWidth = 960.0;

void main() {
  PanelWindow window(
    String id, {
    double preferredWidth = 460,
    bool matchesPanelWidth = true,
  }) =>
      PanelWindow(
        id: id,
        title: id,
        icon: const IconData(0),
        body: const SizedBox.shrink(),
        preferredWidth: preferredWidth,
        matchesPanelWidth: matchesPanelWidth,
      );

  /// A chart-sized window: it asks for its own width instead of the panel's.
  final chart = window(
    'chart',
    preferredWidth: chartWidth,
    matchesPanelWidth: false,
  );

  group('windowWidth', () {
    test('a side window is exactly as wide as its panel', () {
      expect(windowWidth(window('form'), 1230, panelWidth: 350), 350);
      expect(windowWidth(window('form'), 1230, panelWidth: 420), 420);
    });

    test('a window that asks for its own width gets it', () {
      expect(
        windowWidth(chart, 1230, panelWidth: 350),
        chartWidth,
      );
    });

    test('neither grows past the room beside the panel', () {
      expect(windowWidth(window('form'), 300, panelWidth: 350), 300);
      expect(windowWidth(chart, 700, panelWidth: 350), 700);
    });
  });

  group('windowAreaWidth', () {
    test('it leaves the panel, a gap and the edge inset', () {
      expect(
        windowAreaWidth(screenWidth: 1600, panelWidth: 350),
        1600 - 350 - kWindowGap - kWindowEdgeInset,
      );
    });

    test('it never goes negative on a screen narrower than its panel', () {
      expect(windowAreaWidth(screenWidth: 300, panelWidth: 350), 0);
    });
  });

  group('computeWindowsLayout', () {
    test('a phone holds one window at a time', () {
      final layout = computeWindowsLayout(
        floating: [chart, window('form')],
        screenWidth: 600,
        panelWidth: 600,
        screenHeight: 800,
      );
      expect(layout.compact, isTrue);
      expect(layout.capacity, 1);
    });

    test('a wide screen opens as many windows as one row holds', () {
      final layout = computeWindowsLayout(
        floating: [window('a'), window('b'), window('c'), window('d')],
        screenWidth: 1600,
        panelWidth: 350,
        screenHeight: 1000,
      );
      expect(layout.compact, isFalse);
      // 350-wide windows in 1230: three share the row — and only three, because
      // a fourth would have to be stacked over one of them.
      expect(layout.capacity, 3);
    });

    test('a chart and a form do not share a row they cannot fit in', () {
      final layout = computeWindowsLayout(
        floating: [chart, window('form')],
        screenWidth: 1600,
        panelWidth: 350,
        screenHeight: 1000,
      );
      // 960 + 350 does not fit in 1230, so the form waits in the dock rather than
      // being laid over the chart.
      expect(layout.capacity, 1);
    });

    test('a window taller than the screen is not opened at all', () {
      final layout = computeWindowsLayout(
        floating: [
          const PanelWindow(
            id: 'tall',
            title: 'tall',
            icon: IconData(0),
            body: SizedBox.shrink(),
            minHeight: 1200,
          ),
          window('form'),
        ],
        screenWidth: 1600,
        panelWidth: 350,
        screenHeight: 1000,
      );
      // It would have to scroll, and so would anything after it.
      expect(layout.capacity, 0);
    });

    test('a window that needs little leaves room for the next one', () {
      final layout = computeWindowsLayout(
        floating: [window('a'), window('b'), window('c')],
        screenWidth: 1600,
        panelWidth: 350,
        // A screen only one window tall: height is not what limits the row here,
        // width is — three 350-wide windows share it.
        screenHeight: 400,
      );
      expect(layout.capacity, 3);
    });
    test('a wide screen always keeps one window, however tight', () {
      final layout = computeWindowsLayout(
        floating: [chart],
        screenWidth: 710,
        panelWidth: computePanelWidth(screenWidth: 710),
        screenHeight: 1000,
      );
      expect(layout.capacity, 1);
      expect(layout.compact, isFalse);
    });

    test('a panel with nothing to float has no capacity', () {
      final layout = computeWindowsLayout(
        floating: const [],
        screenWidth: 1600,
        panelWidth: 350,
        screenHeight: 1000,
      );
      expect(layout.capacity, 0);
    });
  });

  /// The column beside a 350-wide panel on a 1600-wide screen.
  const area = WindowBounds(left: 362, right: 1592, top: 8, bottom: 908);

  /// One 350-wide window that needs [min] and grows to [max].
  WindowDemand demand({
    double width = 350,
    double min = 300,
    double max = double.infinity,
  }) =>
      WindowDemand(width: width, minHeight: min, maxHeight: max);

  group('arrangeWindows', () {
    test('a row of windows sits side by side', () {
      final slots = arrangeWindows(
        demands: [demand(), demand(), demand()],
        bounds: area,
        rtl: false,
      );

      expect(slots, hasLength(3));
      // Right-aligned against the panel side, one gap apart…
      expect(slots[0].placement.left, 1592 - 350);
      expect(slots[1].placement.left, 1592 - 350 - 12 - 350);
      expect(slots[2].placement.left, 1592 - 2 * (350 + 12) - 350);
      // …all at the same height, and each as tall as the screen: one row, never
      // a pile and never a shorter window that would have to scroll.
      expect(slots.map((slot) => slot.placement.top), everyElement(8));
      expect(slots.map((slot) => slot.height), everyElement(area.height));
    });

    test('in a right-to-left app the row starts on the panel side too', () {
      final slots = arrangeWindows(
        demands: [demand(), demand()],
        bounds: area,
        rtl: true,
      );

      expect(slots[0].placement.left, 362);
      expect(slots[1].placement.left, 362 + 362);
    });

    test('a window wider than the row keeps its own width', () {
      final slots = arrangeWindows(
        demands: [
          demand(width: chartWidth, min: 520, max: 720),
          demand(),
        ],
        bounds: area,
        rtl: false,
      );

      // The chart is drawn at its own width…
      expect(slots[0].placement.left, 1592 - chartWidth);
      // …and the window that has no room beside it is still placed, at the
      // edge of the row — on top of the window already there, because the row
      // is one row. It is the caller that keeps such a window in the dock.
      expect(slots[1].placement.left, 1592 - 350);
      expect(slots[1].placement.top, slots[0].placement.top);
    });

    test('a window never leaves the screen', () {
      final slots = arrangeWindows(
        demands: [demand(width: chartWidth)],
        bounds: const WindowBounds(
          left: 362,
          right: 700,
          top: 8,
          bottom: 908,
        ),
        rtl: false,
      );

      expect(slots.single.placement.left, 362);
      expect(slots.single.placement.top, 8);
    });
  });
  group('WindowBounds.clamp', () {
    test('a placement inside the column is left alone', () {
      const inside = WindowPlacement(left: 500, top: 300);
      expect(area.clamp(inside, width: 350), inside);
    });

    test('a window dragged past either side comes back', () {
      expect(
          area
              .clamp(const WindowPlacement(left: -500, top: 300), width: 350)
              .left,
          area.left);
      expect(
        area
            .clamp(const WindowPlacement(left: 5000, top: 300), width: 350)
            .left,
        area.right - 350,
      );
    });

    test('a window dragged off the top or bottom keeps its header in reach',
        () {
      expect(
          area
              .clamp(const WindowPlacement(left: 500, top: -400), width: 350)
              .top,
          area.top);
      expect(
        area.clamp(const WindowPlacement(left: 500, top: 5000), width: 350).top,
        area.bottom - kWindowMinVisible,
      );
    });
  });

  group('placementAt', () {
    test('a window opens at the tap and grows away from it', () {
      final leftToRight = placementAt(
        origin: const Offset(700, 400),
        width: 350,
        bounds: area,
        rtl: false,
      );
      expect(leftToRight.left, 700);
      expect(leftToRight.top, 400 - kWindowTapLift);

      // In a right-to-left app the same tap opens the window to the left of it.
      final rightToLeft = placementAt(
        origin: const Offset(700, 400),
        width: 350,
        bounds: area,
        rtl: true,
      );
      // Near the panel side it is pulled back inside the column.
      expect(rightToLeft.left, area.left);
    });

    test('a tap near an edge still opens the window on the screen', () {
      final nearTheEdge = placementAt(
        origin: const Offset(1590, 10),
        width: 350,
        bounds: area,
        rtl: false,
      );
      expect(nearTheEdge.left, area.right - 350);
      expect(nearTheEdge.top, area.top);
    });
  });

  group('WindowPlacement.moved', () {
    test('it follows the pointer', () {
      const start = WindowPlacement(left: 100, top: 100);
      expect(
        start.moved(dx: 30, dy: 10),
        const WindowPlacement(left: 130, top: 110),
      );
    });
  });
}
