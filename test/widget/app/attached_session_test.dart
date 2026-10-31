@Tags(['serial'])
library;

import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel_open_builder.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_session.dart';
import '../../helpers/pump_app.dart';

/// A panel carrying a record beside itself (plan §0, §2.3, §6.2-2).
///
/// The visit is not a panel: it is a session whose windows are drawn in the
/// patient panel's own row. These tests prove the three things that make that
/// real rather than intended — that attaching repaints, that the patient stays,
/// and that a visit's window writes the visit.
void main() {
  setUp(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  /// A patient panel' panel: one inline window and one that floats.
  DelegatedPanel hostPanel({List<String>? saves}) => DelegatedPanel(
        itemId: 'patient-1',
        singularName: 'patient',
        unicodeSymbol: '👤',
        icon: WindowsIcons.contact,
        checkUnsavedChanges: () => false,
        onSave: () async {
          saves?.add('patient');
          return const ['patient-1'];
        },
        // The record came alone, so what appears on screen is the attach.
        opensWithWindows: false,
        windows: [
          const PanelWindow(
            id: 'details',
            title: 'details',
            icon: WindowsIcons.contact,
            body: SizedBox(height: 40, child: Text('body-details')),
          ),
          const PanelWindow(
            id: 'appointments',
            title: 'appointments',
            icon: WindowsIcons.calendar,
            body: SizedBox(height: 40, child: Text('body-appointments')),
          ),
        ],
      );

  FakeSession visitSession({String title = 'operativeDetails'}) => FakeSession(
        itemId: 'visit-1',
        windows: [
          FakeSession.window('operative', title: title),
          FakeSession.window('labwork'),
        ],
      );

  Future<void> pumpLayer(WidgetTester tester, {double width = 1600}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApexoApp(
      tester,
      Stack(children: [WindowsLayer(visible: true, screenWidth: width)]),
    );
  }

  testWidgets('record controls follow attach and detach without list changes',
      (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpApexoApp(
      tester,
      PanelOpenBuilder(
        itemId: 'visit-1',
        carries: (owner) => owner.attached?.itemId == 'visit-1',
        builder: (context, index) => Text(index == null ? 'closed' : 'open'),
      ),
    );
    expect(find.text('closed'), findsOneWidget);

    panel.attach(visitSession());
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    panel.detach();
    await tester.pumpAndSettle();
    expect(find.text('closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'attaching a visit puts its windows on screen, with no other '
      'rebuild', (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpLayer(tester);

    expect(find.text('body-operative'), findsNothing);
    expect(find.text('body-appointments'), findsNothing,
        reason: 'the panel came alone');

    final session = visitSession();
    panel.attach(session, focus: 'operative');
    // One frame: nothing else rebuilds this layer — the panel object is the same
    // object it always was — so an attach that shows nothing is the bug this
    // proves against.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('body-operative'), findsOneWidget);
    expect(PanelsManager.active(), [panel], reason: 'the visit is not a panel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the patient panel stays on screen while a visit is attached',
      (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpLayer(tester);

    panel.attach(visitSession(), focus: 'operative');
    await tester.pumpAndSettle();

    expect(PanelsManager.active().single, same(panel));
    expect(panel.attached, isNotNull);
    expect(panel.owned, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the window the opener asked for is the one that opens',
      (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpLayer(tester);

    panel.attach(visitSession(), focus: 'labwork');
    await tester.pumpAndSettle();

    expect(find.text('body-labwork'), findsOneWidget,
        reason: 'the opener came for this window, so it is on screen');
    expect(panel.workspace.isOpen('labwork', slot: kAttachedSlot), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visit window saves the visit and never the patient',
      (tester) async {
    final saves = <String>[];
    final panel = hostPanel(saves: saves);
    PanelsManager.open(panel);
    await pumpLayer(tester);

    final session = visitSession();
    session.hasWork = true;
    session.refreshDirty();
    panel.attach(session, focus: 'operative');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.windowSave).first);
    await tester.pumpAndSettle();

    expect(session.saves, ['visit-1'],
        reason: 'the window writes the record it edits');
    expect(saves, isEmpty,
        reason:
            'a visit window that reached the patient\'s Save would write the '
            'wrong record — the bug this whole design deletes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('detaching keeps the draft, and the panel keeps owning it',
      (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpLayer(tester);

    final session = visitSession();
    panel.attach(session, focus: 'operative');
    await tester.pumpAndSettle();
    expect(find.text('body-operative'), findsOneWidget);

    panel.detach();
    await tester.pumpAndSettle();

    expect(find.text('body-operative'), findsNothing);
    expect(panel.attached, isNull);
    expect(panel.owned, [session],
        reason: 'detaching is not disposing: the draft is still the user\'s');
    expect(session.isDisposed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a session drops it and finishes it for good',
      (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpLayer(tester);

    final session = visitSession();
    panel.attach(session, focus: 'operative');
    await tester.pumpAndSettle();

    panel.disposeSession(session);
    await tester.pumpAndSettle();

    expect(panel.owned, isEmpty);
    expect(session.isDisposed, isTrue);
    expect(find.text('body-operative'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two records in one row answer dirty for themselves',
      (tester) async {
    final panel = hostPanel();
    PanelsManager.open(panel);
    await pumpLayer(tester);
    final session = visitSession();
    session.hasWork = true;
    session.refreshDirty();
    panel.attach(session, focus: 'operative');
    await tester.pumpAndSettle();

    panel.refreshDirty();

    expect(panel.hasUnsavedChanges(), isTrue,
        reason: 'closing this panel would close the visit it carries');
    expect(panel.hasPendingEdits, isFalse,
        reason: 'the panel\'s own Save has nothing of its own to write');
    expect(tester.takeException(), isNull);
  });

  test('a session handed in is owned once, however often it is attached', () {
    final panel = hostPanel();
    final session = visitSession();

    panel.attach(session);
    panel.detach();
    panel.attach(session);

    expect(panel.owned, hasLength(1));
  });

  test('releasing a panel\'s sessions disposes them all', () {
    final panel = hostPanel();
    final session = visitSession();
    panel.attach(session);

    panel.releaseSessions();

    expect(panel.owned, isEmpty);
    expect(session.isDisposed, isTrue);
  });
}
