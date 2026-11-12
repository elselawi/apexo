@Tags(['serial'])
library;

import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_shell.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// A phone panel whose second window is the sheet the dock opens.
DelegatedPanel _phonePanel() => DelegatedPanel(
      itemId: 'phone-panel',
      singularName: 'patient',
      unicodeSymbol: 'P',
      icon: WindowsIcons.contact,
      checkUnsavedChanges: () => false,
      onSave: () async => ['phone-panel'],
      windows: const [
        PanelWindow(
          id: 'details',
          title: 'details',
          icon: WindowsIcons.contact,
          body: SizedBox(height: 40, child: Text('inline-body')),
        ),
        PanelWindow(
          id: 'operative',
          title: 'operative',
          icon: WindowsIcons.contact,
          body: SizedBox(height: 2000, child: Text('sheet-body')),
        ),
      ],
    );

void main() {
  setUp(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  /// A phone with its home indicator, and the sheet its dock opened.
  Future<void> pumpPhoneSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);

    final panel = _phonePanel();
    PanelsManager.open(panel);
    await pumpApexoApp(
      tester,
      const Stack(children: [WindowsLayer(visible: true, screenWidth: 390)]),
    );
    panel.workspace.toggle('operative');
    await tester.pumpAndSettle();
    expect(find.text('sheet-body'), findsOneWidget);
  }

  testWidgets('the keyboard does not close a phone sheet', (tester) async {
    await pumpPhoneSheet(tester);

    // iOS reports the keyboard by growing viewInsets and giving up the bottom
    // safe-area padding; the screen itself keeps its size.
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(find.text('sheet-body'), findsOneWidget,
        reason: 'a keyboard is not a screen change: the sheet stays up');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resized screen does not close a phone sheet', (tester) async {
    await pumpPhoneSheet(tester);

    // A screen that shrinks instead — a rotation, or a platform that resizes
    // for the keyboard rather than reporting insets.
    tester.view.physicalSize = const Size(390, 544);
    await tester.pumpAndSettle();

    expect(find.text('sheet-body'), findsOneWidget,
        reason: 'the room changed, but the sheet the user opened did not');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone sheet keeps clear of the keyboard', (tester) async {
    await pumpPhoneSheet(tester);

    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final shell = tester.getRect(find.byType(WindowShell));
    expect(shell.bottom, lessThanOrEqualTo(844 - 300),
        reason: 'the editor must scroll above the keys, not sit under them');
    expect(tester.takeException(), isNull);
  });
}
