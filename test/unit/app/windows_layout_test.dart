/// The arithmetic behind the window layout, pinned on its own: how wide a window
/// is drawn, how many open by themselves, and where a window is put. The widgets
/// only place what these answer, so a mistake here would show up as a clipped,
/// missing or unreachable window and nothing else could explain it.
library;

import 'package:apexo/ui/workspace/panel_width.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_group.dart';
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

    test('a window opened low with its height known is lifted by that height',
        () {
      // A tap near the foot of the screen: the window's own height, not the
      // least a window may be opened at, decides how far up it goes — so the
      // whole of it sits on the screen and none of it has to be scrolled to.
      final lifted = placementAt(
        origin: Offset(700, area.bottom - 20),
        width: 350,
        bounds: area,
        rtl: false,
        height: 600,
      );
      expect(lifted.top, area.bottom - 600);
      expect(lifted.left, 700);
    });

    test('a window that fits under the tap is not lifted by its height', () {
      final atTheTap = placementAt(
        origin: const Offset(700, 400),
        width: 350,
        bounds: area,
        rtl: false,
        height: 300,
      );
      expect(atTheTap.top, 400 - kWindowTapLift);
    });

    test('a window taller than the screen opens at the top of it', () {
      final tooTall = placementAt(
        origin: Offset(700, area.bottom - 20),
        width: 350,
        bounds: area,
        rtl: false,
        height: area.height + 200,
      );
      expect(tooTall.top, area.top,
          reason: 'it cannot be lifted past the top, so it scrolls — and only '
              'this window does');
    });

    test('before its height is known a window keeps the least room it needs',
        () {
      final unmeasured = placementAt(
        origin: Offset(700, area.bottom - 20),
        width: 350,
        bounds: area,
        rtl: false,
      );
      expect(unmeasured.top, area.bottom - kWindowMinOpeningHeight);
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

  // ── The plan: what one row holds when its windows are not all the same width
  //
  // The chart asks for 960, a pre-op form for 560 and a tool for the panel's own
  // 350, so a count of fitting windows describes one selection and says nothing
  // about the next. These are the six screen profiles §1 priced the design from
  // (plan §1, §4.3, §6.2-5).

  /// A window that asks for its own [width] and needs [minHeight] to be whole.
  PanelWindow sized(
    String id,
    double width, {
    double minHeight = 300,
  }) =>
      PanelWindow(
        id: id,
        title: id,
        icon: const IconData(0),
        body: const SizedBox.shrink(),
        matchesPanelWidth: false,
        preferredWidth: width,
        minHeight: minHeight,
      );

  WindowGroupDemand hostWindows(
    List<PanelWindow> windows, {
    List<String>? remembered,
  }) =>
      WindowGroupDemand(
        slot: kHostSlot,
        windows: windows,
        remembered: remembered,
      );

  WindowGroupDemand visitWindows(
    List<PanelWindow> windows, {
    List<String>? remembered,
  }) =>
      WindowGroupDemand(
        slot: kAttachedSlot,
        windows: windows,
        remembered: remembered,
      );

  WindowsPlan planAt(
    double screenWidth,
    List<WindowGroupDemand> groups, {
    String? focus,
    double screenHeight = 1000,
  }) =>
      computeWindowsPlan(
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        panelWidth: 350,
        groups: groups,
        focus: focus,
      );

  group('the six profiles of §1', () {
    test('1366: a 560 pre-op and one 350 tool fit, 922 of 996', () {
      final plan = planAt(1366, [
        visitWindows([
          sized('preOperative', 560),
          window('labwork'),
        ]),
      ]);

      expect(plan.available, 996);
      expect(plan.selected, ['attached/preOperative', 'attached/labwork']);
      expect(plan.used, 922);
    });

    test('1366: the chart takes the row alone', () {
      final plan = planAt(1366, [
        visitWindows([sized('chart', chartWidth, minHeight: 520)]),
      ]);

      expect(plan.selected, ['attached/chart']);
    });

    test('1366: the chart and the pre-op form cannot both fit', () {
      final plan = planAt(1366, [
        visitWindows([
          sized('preOperative', 560),
          sized('chart', chartWidth, minHeight: 520),
        ]),
      ]);

      // 560 + 12 + 960 = 1532 of 996: the chart stays in the dock, and the window
      // that does fit keeps its place.
      expect(plan.selected, ['attached/preOperative']);
    });

    test('1920: pre-op and the chart fit together, 1532 of 1550', () {
      final plan = planAt(1920, [
        visitWindows([
          sized('preOperative', 560),
          sized('chart', chartWidth, minHeight: 520),
        ]),
      ]);

      expect(plan.available, 1550);
      expect(plan.selected, ['attached/preOperative', 'attached/chart']);
      expect(plan.used, 1532);
    });

    test('1920: pre-op and two 350 tools fit, 1284 of 1550', () {
      final plan = planAt(1920, [
        visitWindows([
          sized('preOperative', 560),
          window('labwork'),
          window('gallery'),
        ]),
      ]);

      expect(plan.selected, hasLength(3));
      expect(plan.used, 1284);
    });

    test('1920: the chart and one 350 tool fit, 1322 of 1550', () {
      final plan = planAt(1920, [
        visitWindows([
          sized('chart', chartWidth, minHeight: 520),
          window('labwork'),
        ]),
      ]);

      expect(plan.selected, ['attached/chart', 'attached/labwork']);
      expect(plan.used, 1322);
    });
  });

  group('the plan walks candidates instead of counting them', () {
    test('a narrow window after a wide one that did not fit still opens', () {
      // The whole point of `continue` rather than `break`: the chart is too wide
      // for what is left of the row, and the tool behind it is not.
      final plan = planAt(1366, [
        visitWindows([
          sized('preOperative', 560),
          sized('chart', chartWidth, minHeight: 520),
          window('labwork'),
        ]),
      ]);

      expect(plan.selected, ['attached/preOperative', 'attached/labwork']);
      expect(plan.selected, isNot(contains('attached/chart')));
    });

    test('a window the screen is too short for is skipped, not fatal', () {
      final plan = planAt(
        1920,
        [
          visitWindows([
            sized('tallList', 350, minHeight: 900),
            window('operative'),
          ]),
        ],
        screenHeight: 600,
      );

      expect(plan.room, 600 - 2 * kWindowEdgeInset);
      expect(plan.selected, ['attached/operative']);
    });

    test('an explicitly requested tall editor remains reachable', () {
      final plan = planAt(
        1092,
        [
          visitWindows([sized('chart', chartWidth, minHeight: 700)])
        ],
        screenHeight: 550,
        focus: 'attached/chart',
      );

      expect(plan.selected, ['attached/chart']);
      expect(plan.used, lessThanOrEqualTo(plan.available));
    });

    test('every candidate has a width, on screen or not — a dock has to know',
        () {
      final plan = planAt(1366, [
        visitWindows([sized('chart', chartWidth, minHeight: 520)]),
        hostWindows([window('appointments')]),
      ]);

      expect(plan.widthOf('attached/chart'), chartWidth);
      expect(plan.widthOf('host/appointments'), 350,
          reason: 'a window left in the dock still has to fit if asked for');
    });

    test('the row is drawn in the records\' own order, not the trying order',
        () {
      final plan = planAt(2200, [
        visitWindows([window('operative')]),
        hostWindows([window('appointments')]),
      ]);

      // The visit is nearest the panel, the patient's record further out.
      expect(plan.selected, ['attached/operative', 'host/appointments']);
    });

    test('what is remembered comes up, and only what is remembered', () {
      final plan = planAt(
        2200,
        [
          hostWindows(
            [sized('chart', chartWidth), window('appointments')],
            remembered: ['appointments'],
          ),
        ],
      );

      expect(plan.selected, ['host/appointments'],
          reason:
              'the user left one window open; the panel does not reopen the '
              'others');
    });

    test('a group the user never arranged opens its own first picks', () {
      final plan = planAt(2200, [
        hostWindows([sized('chart', chartWidth), window('appointments')]),
      ]);

      expect(plan.selected, ['host/chart', 'host/appointments']);
    });

    test('a remembered window the record no longer offers is dropped', () {
      final plan = planAt(
        2200,
        [
          hostWindows([window('appointments')], remembered: ['gone'])
        ],
      );

      expect(plan.selected, isEmpty);
    });

    test('an empty memory is a choice: the group opens nothing', () {
      final plan = planAt(
        2200,
        [
          hostWindows([window('appointments')], remembered: const [])
        ],
      );

      expect(plan.selected, isEmpty);
    });
  });

  group('focus, in the plan', () {
    test('the focused window is placed even when it is not remembered', () {
      final plan = planAt(
        2200,
        [
          hostWindows(
            [sized('chart', chartWidth), window('appointments')],
            remembered: ['appointments'],
          ),
        ],
        focus: 'host/chart',
      );

      expect(plan.selected, containsAll(['host/chart', 'host/appointments']));
    });

    test('a phone draws the focused window, and nothing else', () {
      final plan = planAt(
        700,
        [
          hostWindows([sized('chart', chartWidth), window('appointments')])
        ],
        focus: 'host/appointments',
      );

      expect(plan.compact, isTrue);
      expect(plan.selected, ['host/appointments']);
    });

    test('a phone opens nothing until it is asked', () {
      final plan = planAt(700, [
        hostWindows([window('appointments')])
      ]);

      expect(plan.compact, isTrue);
      expect(plan.selected, isEmpty);
    });

    test('a focus that names no window is ignored', () {
      final plan = planAt(
        2200,
        [
          hostWindows([window('appointments')])
        ],
        focus: 'attached/operative',
      );

      expect(plan.selected, ['host/appointments']);
    });
  });

  test('a panel with no windows at all plans nothing', () {
    final plan = planAt(1920, const []);

    expect(plan.selected, isEmpty);
    expect(plan.widths, isEmpty);
    expect(plan.compact, isFalse);
  });

  group('the chart threshold', () {
    test('1902 is where the chart and the pre-op form first fit together', () {
      // 560 + 12 + 960 = 1532 = 1902 − 350 − 12 − 8: the exact screen the
      // threshold is derived from (plan §4.3).
      final plan = planAt(1902, [
        visitWindows([
          sized('preOperative', 560),
          sized('chart', chartWidth, minHeight: 520),
        ]),
      ]);

      expect(plan.available, 1532);
      expect(plan.selected, ['attached/preOperative', 'attached/chart']);
    });

    test('one pixel narrower, the pair no longer fit and the chart waits', () {
      final plan = planAt(1901, [
        visitWindows([
          sized('preOperative', 560),
          sized('chart', chartWidth, minHeight: 520),
        ]),
      ]);

      expect(plan.available, 1531);
      expect(plan.selected, ['attached/preOperative'],
          reason: 'the pre-op form keeps the row; the chart stays in the dock');
    });

    test('the chart is placed first when it is the window asked for', () {
      final plan = planAt(
        1901,
        [
          visitWindows([
            sized('preOperative', 560),
            sized('chart', chartWidth, minHeight: 520),
          ]),
        ],
        focus: 'attached/chart',
      );

      expect(plan.selected, ['attached/chart'],
          reason: 'below the threshold the chart takes the row alone');
    });
  });

  test('the same selection is recognised, so a rebuild is not a rearrange', () {
    final one = planAt(1920, [
      hostWindows([window('appointments')])
    ]);
    final two = planAt(1920, [
      hostWindows([window('appointments')])
    ]);

    expect(one.sameSelection(two), isTrue);
    expect(
      one.sameSelection(planAt(1366, [
        hostWindows([window('appointments')])
      ])),
      isTrue,
      reason: 'a narrower screen that still holds the same window rearranges '
          'nothing',
    );
    expect(
      one.sameSelection(planAt(700, [
        hostWindows([window('appointments')])
      ])),
      isFalse,
      reason: 'a phone draws sheets, which is a different row',
    );
  });
}
