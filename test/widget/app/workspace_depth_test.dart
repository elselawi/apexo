@Tags(['serial'])
library;

import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/ui/design/mica_backdrop.dart';
import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_shell.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// The first box in [host] that paints its own shadow — a panel's frame.
BoxDecoration frameOf(WidgetTester tester, Finder host) {
  final frame = find
      .descendant(
        of: host,
        matching: find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            ((widget.decoration! as BoxDecoration).boxShadow?.isNotEmpty ??
                false)),
      )
      .first;
  return tester.widget<Container>(frame).decoration! as BoxDecoration;
}

/// A window's acrylic surface, which is a [AcrylicSurface] rather than a plain
/// box: the frame and the fill are painted by different widgets.
AcrylicSurface surfaceOf(WidgetTester tester, Finder host) {
  return tester.widget<AcrylicSurface>(
    find.descendant(of: host, matching: find.byType(AcrylicSurface)).first,
  );
}

/// The decoration of the first box in [host], shadow or not.
BoxDecoration decorationOf(WidgetTester tester, Finder host) {
  final frame = find
      .descendant(
        of: host,
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration is BoxDecoration,
        ),
      )
      .first;
  return tester.widget<Container>(frame).decoration! as BoxDecoration;
}

void main() {
  setUp(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('workspace surfaces use Fluent depth in ${mode.name} mode',
        (tester) async {
      final panel = DelegatedPanel(
        itemId: 'depth-panel',
        singularName: 'patient',
        unicodeSymbol: 'P',
        icon: FluentIcons.contact,
        newTitle: 'Depth panel',
        checkUnsavedChanges: () => false,
        onSave: () async => ['depth-panel'],
        showBottomControls: false,
        windows: const [
          PanelWindow(
            id: 'details',
            title: 'Details',
            icon: FluentIcons.contact,
            body: Text('Panel editor'),
          ),
        ],
      );
      await pumpApexoApp(
        tester,
        Stack(children: [
          Row(children: [
            Expanded(child: PanelScreen(panel: panel, layoutWidth: 1600)),
            const Expanded(
              child: WindowShell(
                icon: FluentIcons.photo,
                title: 'Depth window',
                child: Text('Window editor'),
              ),
            ),
          ]),
          const BottomNavBar(),
        ]),
        theme: mode,
      );

      final materials = FluentMaterials.of(
        tester.element(find.byType(WindowShell)),
      );
      final panelFrame = frameOf(tester, find.byType(PanelScreen));
      final windowSurface = surfaceOf(tester, find.byType(WindowShell));
      final navFrame = decorationOf(tester, find.byType(BottomNavBar));
      expect(panelFrame.color, materials.layer,
          reason: 'a panel is the screen layer: Mica reads through it');
      expect(windowSurface.color, materials.acrylic,
          reason: 'a floating window is acrylic, denser than the layer');
      expect(navFrame.color, materials.acrylicBar,
          reason: 'the phone bar is glass, not a solid strip');
      expect(materials.layer.a, lessThan(0.6),
          reason: 'the screen layer must let the window material through');
      expect(windowSurface.color!.a, greaterThan(0.85),
          reason: 'editors behind a window must not make its text unreadable');
      expect(windowSurface.shadows!.first.blurRadius,
          greaterThan(panelFrame.boxShadow!.first.blurRadius),
          reason: 'the window floats above the panel, so it casts further');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a phone panel is opaque so the app bar cannot read through in '
        '${mode.name} mode', (tester) async {
      final panel = DelegatedPanel(
        itemId: 'phone-panel',
        singularName: 'patient',
        unicodeSymbol: 'P',
        icon: FluentIcons.contact,
        newTitle: 'Phone panel',
        checkUnsavedChanges: () => false,
        onSave: () async => ['phone-panel'],
        showBottomControls: false,
        windows: const [
          PanelWindow(
            id: 'details',
            title: 'Details',
            icon: FluentIcons.contact,
            body: Text('Panel editor'),
          ),
        ],
      );
      await pumpApexoApp(
        tester,
        Stack(children: [PanelScreen(panel: panel, layoutWidth: 390)]),
        theme: mode,
      );

      final materials = FluentMaterials.of(
        tester.element(find.byType(PanelScreen)),
      );
      final panelFrame = frameOf(tester, find.byType(PanelScreen));
      expect(panelFrame.color, materials.layerOpaque,
          reason: 'below the breakpoint the panel covers the app bar, so it '
              'must hide it rather than tint it');
      expect(panelFrame.color!.a, 1.0,
          reason: 'nothing behind a full-screen panel may read through');

      // The shell leaves the status bar over a full-width panel: the surface
      // covers it, and the header steps below it.
      tester.view.padding = const FakeViewPadding(top: 26);
      addTearDown(tester.view.resetPadding);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(PanelScreen)).dy, 0,
          reason: 'the panel surface runs to the top edge');
      expect(tester.getTopLeft(find.byKey(WK.panelClose)).dy,
          greaterThanOrEqualTo(26),
          reason: 'the panel header starts below the status bar');
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone sheets use Fluent scrims in ${mode.name} mode',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      WindowsManager.show(const FloatingWindow(
        window: PanelWindow(
          id: 'sheet',
          title: 'Sheet',
          icon: FluentIcons.photo,
          body: SizedBox(height: 100, child: Text('Sheet editor')),
        ),
      ));
      await pumpApexoApp(
        tester,
        const Stack(children: [
          WindowsLayer(visible: true, screenWidth: 390),
        ]),
        theme: mode,
      );
      final shell = find.byType(WindowShell);
      final resources = FluentTheme.of(tester.element(shell)).resources;
      expect(tester.widget<WindowShell>(shell).active, isTrue);
      expect(
        find.byWidgetPredicate((widget) =>
            widget is ColoredBox &&
            widget.color == resources.smokeFillColorDefault),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(4, 700));
      await tester.pumpAndSettle();
      expect(shell, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'raising and closing windows updates depth in ${mode.name} mode',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FloatingWindow window(String id) => FloatingWindow(
            window: PanelWindow(
              id: id,
              title: id,
              icon: FluentIcons.photo,
              preferredWidth: 400,
              matchesPanelWidth: false,
              body: SizedBox(height: 100, child: Text('Editor $id')),
            ),
          );
      final first = window('First');
      final second = window('Second');
      WindowsManager.show(first);
      WindowsManager.show(second);
      await pumpApexoApp(
        tester,
        const Stack(children: [
          WindowsLayer(visible: true, screenWidth: 1600),
        ]),
        theme: mode,
      );
      Finder shell(String title) => find.byWidgetPredicate(
          (widget) => widget is WindowShell && widget.title == title);
      bool active(String title) =>
          tester.widget<WindowShell>(shell(title)).active;

      expect(active('First'), isFalse);
      expect(active('Second'), isTrue);
      final materials = FluentMaterials.of(tester.element(shell('First')));
      final backSurface = surfaceOf(tester, shell('First'));
      final frontSurface = surfaceOf(tester, shell('Second'));
      expect(backSurface.color, materials.card,
          reason: 'a window behind another steps back to a plain layer');
      expect(frontSurface.color, materials.acrylic,
          reason: 'the front window is the one holding the acrylic');
      expect(frontSurface.shadows!.first.blurRadius,
          greaterThan(backSurface.shadows!.first.blurRadius));
      expect(frontSurface.borderColor, backSurface.borderColor,
          reason: 'all window surfaces share the same raised-edge stroke');

      await tester.tap(find.text('Editor First'));
      await tester.pumpAndSettle();
      expect(active('First'), isTrue);
      expect(active('Second'), isFalse);
      expect(surfaceOf(tester, shell('First')).color, frontSurface.color);
      expect(surfaceOf(tester, shell('Second')).color, backSurface.color);

      WindowsManager.close(first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(active('Second'), isTrue,
          reason: 'a closing window must not keep the live window inactive');
      await tester.pumpAndSettle();
      expect(shell('First'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
