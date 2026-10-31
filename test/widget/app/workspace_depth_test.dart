@Tags(['serial'])
library;

import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_shell.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

BoxDecoration frameOf(WidgetTester tester, Finder host) {
  final frame = find.descendant(
    of: host,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          (decoration.boxShadow?.isNotEmpty ?? false);
    }),
  );
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
            Expanded(child: PanelScreen(panel: panel)),
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

      final resources = FluentTheme.of(
        tester.element(find.byType(WindowShell)),
      ).resources;
      final panelFrame = frameOf(tester, find.byType(PanelScreen));
      final windowFrame = frameOf(tester, find.byType(WindowShell));
      final navFrame = frameOf(tester, find.byType(BottomNavBar));
      expect(panelFrame.color, resources.solidBackgroundFillColorSecondary);
      final editorSurface = tester.widget<ColoredBox>(find
          .ancestor(
            of: find.text('Panel editor'),
            matching: find.byType(ColoredBox),
          )
          .first);
      expect(editorSurface.color, panelFrame.color);
      expect(panelFrame.color!.computeLuminance(),
          lessThan(resources.solidBackgroundFillColorBase.computeLuminance()));
      expect(windowFrame.color, resources.solidBackgroundFillColorBase);
      expect(navFrame.color, resources.solidBackgroundFillColorSecondary);
      for (final frame in [panelFrame, windowFrame, navFrame]) {
        expect(frame.color!.a, 1,
            reason: 'editors below must not show through');
        expect(frame.boxShadow!.first.color, resources.smokeFillColorDefault);
      }
      if (mode == ThemeMode.dark) {
        expect(windowFrame.color!.computeLuminance(),
            greaterThan(panelFrame.color!.computeLuminance()));
      }
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
      final backFrame = frameOf(tester, shell('First'));
      final frontFrame = frameOf(tester, shell('Second'));
      final resources = FluentTheme.of(tester.element(shell('First'))).resources;
      expect(backFrame.color, resources.solidBackgroundFillColorSecondary);
      expect(frontFrame.color, resources.solidBackgroundFillColorBase);
      expect(frontFrame.boxShadow!.first.blurRadius,
          greaterThan(backFrame.boxShadow!.first.blurRadius));
      expect(frontFrame.border, isNot(backFrame.border));

      await tester.tap(find.text('Editor First'));
      await tester.pumpAndSettle();
      expect(active('First'), isTrue);
      expect(active('Second'), isFalse);
      expect(frameOf(tester, shell('First')).color, frontFrame.color);
      expect(frameOf(tester, shell('Second')).color, backFrame.color);

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
