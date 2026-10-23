import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/close_all_button.dart';
import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// The "close all windows" command: out only while the workspace is clean,
/// beside the panel rather than over it, and one press away from an empty desk.
void main() {
  setUp(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  Panel panel({required bool dirty}) => DelegatedPanel(
        itemId: 'close-all-panel',
        singularName: 'patient',
        unicodeSymbol: '👤',
        icon: FluentIcons.medication_admin,
        checkUnsavedChanges: () => dirty,
        onSave: () async => const [],
        windows: [
          const PanelWindow(
            id: 'details',
            title: 'patientDetails',
            icon: FluentIcons.medication_admin,
            body: SizedBox.shrink(),
          ),
        ],
      );

  PanelWindow windowModel() => const PanelWindow(
        id: 'photo',
        title: 'xRayViewer',
        icon: WindowsIcons.cancel,
        body: SizedBox.shrink(),
      );

  /// How far the button is out of its corner: 0 while it is away, 1 when it has
  /// arrived.
  double presence(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(CloseAllButton),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  Future<void> pumpButton(
    WidgetTester tester, {
    double screenWidth = 1400,
    double panelWidth = 350,
    TextDirection direction = TextDirection.ltr,
    ThemeMode theme = ThemeMode.light,
  }) =>
      pumpApexoApp(
        tester,
        Directionality(
          textDirection: direction,
          child: Stack(
            children: [
              CloseAllButton(
                screenWidth: screenWidth,
                panelWidth: panelWidth,
              ),
            ],
          ),
        ),
        theme: theme,
      );

  testWidgets('stays away while nothing is open', (tester) async {
    await pumpButton(tester);

    expect(presence(tester), 0,
        reason: 'the button appeared with no panel and no window to close');
  });

  testWidgets('comes out when a clean panel is open', (tester) async {
    PanelsManager.active([panel(dirty: false)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    expect(presence(tester), 1,
        reason: 'a clean panel is exactly what the button is for');
  });

  testWidgets('spells the action out beside its glyph', (tester) async {
    PanelsManager.active([panel(dirty: false)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(WK.closeAllWindows),
        matching: find.text(txt('closeAllWindows')),
      ),
      findsWidgets,
      reason: 'a command glyph on its own leaves the action to be guessed',
    );
  });

  testWidgets('wears the Close buttons\' grey and white in either theme',
      (tester) async {
    PanelsManager.active([panel(dirty: false)]);

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      await pumpButton(tester, theme: themeMode);
      await tester.pumpAndSettle();

      final style =
          tester.widget<Button>(find.byKey(WK.closeAllWindows)).style!;
      expect(style.backgroundColor!.resolve({}), Colors.grey,
          reason:
              '${themeMode.name}: the button left the Close buttons\' grey');
      expect(style.foregroundColor!.resolve({}), Colors.white,
          reason: '${themeMode.name}: its label must read on that grey');
    }
  });

  testWidgets('lifts under the pointer, and points at itself', (tester) async {
    PanelsManager.active([panel(dirty: false)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    // Only the lift's container is a plain box; the button's own is shaped.
    BoxShadow lift() => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(CloseAllButton),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .single
        .boxShadow!
        .single;

    final rest = lift();
    double scaleNow() => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byType(CloseAllButton),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;
    final restingScale = scaleNow();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(WK.closeAllWindows)));
    await tester.pumpAndSettle();

    final lifted = lift();
    expect(lifted.blurRadius, greaterThan(rest.blurRadius),
        reason: 'the pointer did not reach the shadow outward');
    expect(lifted.offset.distance, greaterThan(rest.offset.distance),
        reason: 'the pointer did not reach the shadow outward');

    final grown = scaleNow();
    expect(grown, greaterThan(restingScale),
        reason: 'the whole control, glyph and label with it, did not grow');

    expect(
      tester
          .widgetList<MouseRegion>(
            find.descendant(
              of: find.byType(CloseAllButton),
              matching: find.byType(MouseRegion),
            ),
          )
          .map((region) => region.cursor),
      contains(SystemMouseCursors.click),
      reason: 'a button the pointer cannot see itself in reads as a picture',
    );
  });

  testWidgets('stays away while a panel holds unsaved work', (tester) async {
    PanelsManager.active([panel(dirty: true)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    expect(presence(tester), 0,
        reason: 'a dirty panel must be closed by its own asking Close');
  });

  testWidgets('comes out for a standing window with nothing unsaved',
      (tester) async {
    WindowsManager.showStandalone(
      windowModel(),
      onSave: () async {},
      hasChanges: () => false,
    );
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();

    expect(presence(tester), 1,
        reason: 'a clean window standing alone can be put away by the button');
  });

  testWidgets('stays away while a standing window holds unsaved work',
      (tester) async {
    WindowsManager.showStandalone(
      windowModel(),
      onSave: () async {},
      hasChanges: () => true,
    );
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();

    expect(presence(tester), 0,
        reason: 'closing it here would throw the work away without asking');
  });

  testWidgets('sits beside the panel, never over it', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PanelsManager.active([panel(dirty: false)]);
    await pumpButton(tester, screenWidth: 1400);
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byKey(WK.closeAllWindows));
    expect(button.right, lessThanOrEqualTo(1400 - 350),
        reason: 'the button is drawn over the panel it sits beside');
    expect(button.bottom, lessThanOrEqualTo(900));
  });

  testWidgets('floats on the panel\'s start side in a right-to-left layout',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PanelsManager.active([panel(dirty: false)]);
    await pumpButton(tester, direction: TextDirection.rtl);
    await tester.pumpAndSettle();

    // The panel takes the left column there, so the content — and the button —
    // is on its right.
    final button = tester.getRect(find.byKey(WK.closeAllWindows));
    expect(button.left, greaterThanOrEqualTo(350),
        reason: 'the button is drawn over the panel it sits beside');
  });

  testWidgets('waits out a phone, where the panel fills the screen',
      (tester) async {
    PanelsManager.active([panel(dirty: false)]);
    await pumpButton(tester, screenWidth: 600, panelWidth: 600);
    await tester.pumpAndSettle();

    expect(presence(tester), 0,
        reason: 'there is no corner beside a panel that fills the screen');
  });

  testWidgets('one press closes every panel and every standing window',
      (tester) async {
    PanelsManager.active([panel(dirty: false)]);
    WindowsManager.showStandalone(
      windowModel(),
      onSave: () async {},
      hasChanges: () => false,
    );
    await pumpButton(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.closeAllWindows));
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), isEmpty,
        reason: 'the panel is still on screen');
    expect(WindowsManager.open(), isEmpty,
        reason: 'the standing window is still on screen');
    expect(presence(tester), 0, reason: 'the button stayed after closing all');
  });
}
