@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_attachments.dart';
import 'package:apexo/ui/workspace/window_dock.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_session.dart';
import '../../helpers/pump_app.dart';

void main() {
  setUp(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  Panel hostPanel({Widget? footer}) => DelegatedPanel(
        itemId: 'patient-1',
        singularName: 'patient',
        unicodeSymbol: '👤',
        icon: WindowsIcons.contact,
        saveLabel: 'savePatient',
        carriedDraftWindowId: 'chart',
        carriedBandFooter: footer,
        attachmentLayout: true,
        workspaceWindows: const ['chart', 'appointments'],
        checkUnsavedChanges: () => false,
        onSave: () async => const ['patient-1'],
        opensWithWindows: false,
        windows: [
          const PanelWindow(
            id: 'details',
            title: 'details',
            icon: WindowsIcons.contact,
            body: SizedBox(height: 40),
          ),
          const PanelWindow(
            id: 'chart',
            title: 'dentalChart',
            icon: FluentIcons.teeth,
            body: SizedBox(height: 40),
          ),
          const PanelWindow(
            id: 'appointments',
            title: 'allAppointments',
            icon: WindowsIcons.calendar,
            body: SizedBox(height: 40),
            byDefault: false,
          ),
          const PanelWindow(
            id: 'gallery',
            title: 'gallery',
            icon: FluentIcons.photo,
            body: SizedBox(height: 40),
            attachedTo: PanelWindow.panelAttachment,
          ),
          const PanelWindow(
            id: 'page',
            title: 'patientPage',
            icon: FluentIcons.q_r_code,
            body: SizedBox(height: 40),
            attachedTo: PanelWindow.panelAttachment,
          ),
        ],
      );

  FakeSession visit({bool dirty = false, bool done = false}) {
    final session = FakeSession(
      itemId: 'visit-1',
      windows: [
        FakeSession.window('chart', saveLabel: 'saveVisit'),
        FakeSession.window('labwork',
            saveLabel: 'saveVisit', attachedTo: 'chart'),
      ],
      displayTitleText: 'Ali Karim · 24/10 · pending',
      hasWork: dirty,
    );
    session.bandLabelText = 'Visit · 24/10';
    // The record's own compact form, as a real session supplies one.
    session.band = const SizedBox(
      height: 30,
      child: Text('date · time · duration · doctors'),
    );
    session.done = done;
    session.refreshDirty();
    return session;
  }

  Future<void> pumpShell(WidgetTester tester, Panel panel) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PanelsManager.active([panel]);
    await pumpApexoApp(
      tester,
      Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: 350,
              height: double.infinity,
              child: PanelScreen(panel: panel, layoutWidth: 1600),
            ),
          ),
          const WindowsLayer(visible: true, screenWidth: 1600),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a visit draws its own band, its own form and its own Save',
      (tester) async {
    final panel = hostPanel();
    final session = visit(dirty: true);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    expect(find.byKey(WK.visitBand), findsOneWidget);
    expect(find.text('Visit · 24/10'), findsWidgets,
        reason: 'the band names the visit, not the patient above it');
    // The appointment's form lives in the band: no window, no row slot.
    expect(find.byKey(WK.visitContent), findsOneWidget);
    // The footer carries the record's actions, not the identity line.
    expect(find.byKey(WK.visitDetach), findsOneWidget);
    expect(find.byKey(WK.visitDelete), findsOneWidget);
    expect(find.byKey(WK.visitMenu), findsOneWidget);
    // Two Saves, each saying which record it writes.
    expect(find.text(txt('savePatient')), findsWidgets);
    expect(find.text(txt('saveVisit')), findsWidgets);
    // With attachments and header buttons, the workspaces row is the only dock.
    expect(find.byType(WindowDock), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WindowDock),
        matching: find.byKey(WK.workspaceWindowToggle('chart')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the record\'s forward field sits under the band and stays live',
      (tester) async {
    var tapped = 0;
    final panel = hostPanel(
      footer: GestureDetector(
        key: WK.patientFollowUpSet,
        behavior: HitTestBehavior.opaque,
        onTap: () => tapped++,
        child: const SizedBox(height: 32, width: 120),
      ),
    );
    panel.attach(visit());
    await pumpShell(tester, panel);

    final footer = find.byKey(WK.patientFollowUpSet);
    expect(footer, findsOneWidget);
    // The follow-up row sits below the band, outside the visit's bubble.
    expect(
      tester.getTopLeft(footer).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(WK.visitBand)).dy),
    );
    // The record turns read-only while a visit is open; this row stays live
    // because a visit is exactly where a follow-up is decided.
    await tester.tap(footer);
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });

  for (final allowed in [false, true]) {
    testWidgets('visit band archive capability is $allowed', (tester) async {
      final panel = hostPanel();
      final session = visit()..canArchive = allowed;
      panel.attach(session);
      await pumpShell(tester, panel);

      expect(
          find.byKey(WK.visitDelete), allowed ? findsOneWidget : findsNothing);
      expect(find.byKey(WK.visitDetach), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('archiving a previous visit does not detach the current visit',
      (tester) async {
    final panel = hostPanel();
    final session = visit();
    final archiving = Completer<void>();
    session.archive = (_) => archiving.future;
    panel.attach(session);
    await pumpShell(tester, panel);
    tester.widget<DeleteButton>(find.byKey(WK.visitDelete)).onConfirm();
    final next = FakeSession(itemId: 'next-visit', windows: const []);
    panel.attach(next);
    await tester.pumpAndSettle();
    archiving.complete();
    await tester.pumpAndSettle();

    expect(panel.attached, same(next));
    expect(session.archived, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save all does not discard edits made during the save',
      (tester) async {
    final saving = Completer<void>();
    var dirty = true;
    final panel = DelegatedPanel(
      itemId: 'saving-patient',
      singularName: 'patient',
      unicodeSymbol: '👤',
      icon: WindowsIcons.contact,
      checkUnsavedChanges: () => dirty,
      onSave: () async {
        dirty = false;
        await saving.future;
        return ['saving-patient'];
      },
      windows: const [
        PanelWindow(
          id: 'details',
          title: 'details',
          icon: WindowsIcons.contact,
          body: SizedBox(height: 40),
        ),
      ],
    );
    await pumpShell(tester, panel);
    await tester.tap(find.byKey(WK.panelClose));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt('closePromptSaveAll')).last);
    await tester.pump();
    expect(panel.inProgress(), isTrue);
    dirty = true;
    saving.complete();
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), contains(panel));
    expect(panel.hasPendingEdits, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save all does not close a record already being saved',
      (tester) async {
    final panel = hostPanel();
    final session = visit(dirty: true);
    panel.attach(session);
    await pumpShell(tester, panel);
    await tester.tap(find.byKey(WK.panelClose));
    await tester.pumpAndSettle();
    session.inProgress(true);
    await tester.tap(find.text(txt('closePromptSaveAll')).last);
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), contains(panel));
    expect(session.saves, isEmpty);
    expect(session.isDisposed, isFalse);
    session.inProgress(false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel\'s workspaces sit inside it, its photos under it',
      (tester) async {
    final panel = hostPanel();
    await pumpShell(tester, panel);

    expect(find.byKey(WK.workspaceWindowToggle('chart')), findsOneWidget);
    expect(
        find.byKey(WK.workspaceWindowToggle('appointments')), findsOneWidget);

    final tray = find.byType(WindowAttachments);
    expect(tray, findsOneWidget, reason: 'the record has attachments');
    expect(
      find.descendant(
          of: tray, matching: find.byKey(WK.attachmentToggle('gallery'))),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: tray, matching: find.byKey(WK.attachmentToggle('page'))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an attachment chip opens its editor in the row', (tester) async {
    final panel = hostPanel();
    await pumpShell(tester, panel);

    await tester.tap(find.byKey(WK.attachmentToggle('gallery')));
    await tester.pumpAndSettle();

    expect(panel.workspace.isOpen('gallery'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the band shows pending, and flips to completed as it is typed',
      (tester) async {
    final panel = hostPanel();
    final session = visit();
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    expect(
      find.descendant(
          of: find.byKey(WK.visitState), matching: find.text(txt('pending'))),
      findsWidgets,
    );

    session.markDone(true);
    session.hasWork = true;
    session.refreshDirty();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: find.byKey(WK.visitState), matching: find.text(txt('completed'))),
      findsWidgets,
    );
    expect(find.byKey(WK.visitMarkedCompleted), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the band counts the visits that hold unsaved work',
      (tester) async {
    final panel = hostPanel();
    final first = visit(dirty: true);
    final second = FakeSession(
      itemId: 'visit-2',
      windows: [FakeSession.window('chart')],
      hasWork: true,
    );
    second.refreshDirty();
    panel.attach(first);
    panel.attach(second, focus: 'chart');
    await pumpShell(tester, panel);

    expect(
      find.text(
        txt('unsavedVisitsCount').replaceAll('{count}', '2'),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retained draft is marked on the chart button and the band',
      (tester) async {
    final panel = hostPanel();
    final session = visit(dirty: true);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    expect(
      find.descendant(
        of: find.byKey(WK.workspaceWindowToggle('chart')),
        matching: find.byKey(WK.unsavedDot),
      ),
      findsOneWidget,
      reason: 'the draft is the visit\'s chart, and the chart button is where '
          'it is reopened',
    );
    expect(
      find.descendant(
        of: find.byKey(WK.workspaceWindowToggle('appointments')),
        matching: find.byKey(WK.unsavedDot),
      ),
      findsNothing,
      reason: 'the visits list only lists records; it is not where the work is',
    );
  });

  testWidgets('closing the visit keeps the draft, and the dot keeps saying so',
      (tester) async {
    final panel = hostPanel();
    final session = visit(dirty: true);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    await tester.tap(find.byKey(WK.visitDetach));
    await tester.pumpAndSettle();

    expect(find.byKey(WK.visitBand), findsNothing);
    expect(panel.attached, isNull);
    expect(panel.owned, [session], reason: 'closing is not disposing');
    expect(
      find.descendant(
        of: find.byKey(WK.workspaceWindowToggle('chart')),
        matching: find.byKey(WK.unsavedDot),
      ),
      findsOneWidget,
      reason: 'the draft is still unsaved and still this panel\'s',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel\'s unsaved dot counts a dirty visit it carries',
      (tester) async {
    final panel = hostPanel();
    final session = visit(dirty: true);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);
    panel.refreshDirty();

    expect(panel.hasUnsavedChanges(), isTrue,
        reason: 'closing the panel closes the visit with it');
    expect(panel.hasPendingEdits, isFalse,
        reason: 'the panel\'s own Save still has nothing of its own to write');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visit\'s attachments draw on its chart, not in the panel',
      (tester) async {
    final panel = hostPanel();
    final session = visit(dirty: true);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    // The visit chart is in the row; its labwork hangs off the chart's frame.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('window-card-chart')),
        matching: find.byKey(WK.attachmentToggle('labwork', owner: 'chart')),
      ),
      findsOneWidget,
      reason: 'a visit\'s editors are attachments of its chart',
    );
    // The panel's own tray is not the visit's: two records, two trays.
    expect(find.byKey(WK.attachmentToggle('gallery')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the band offers its attachments at its foot, not in its dock',
      (tester) async {
    final panel = hostPanel();
    final session = FakeSession(
      itemId: 'visit-banded',
      windows: [
        FakeSession.window('chart', saveLabel: 'saveVisit'),
        FakeSession.window(
          'labwork',
          saveLabel: 'saveVisit',
          attachedTo: PanelWindow.bandAttachment,
        ),
      ],
    );
    session.band = const SizedBox(height: 30);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    final tray = find.byKey(WK.visitBandAttachments);
    expect(tray, findsOneWidget, reason: 'the band carries a visit\'s editors');
    final chip = find.descendant(
      of: tray,
      matching: find.byKey(
        WK.attachmentToggle('labwork', owner: PanelWindow.bandAttachment),
      ),
    );
    expect(chip, findsOneWidget);
    expect(find.byKey(WK.visitBandWindow('labwork')), findsNothing,
        reason: 'an attachment is not a tool in the dock');

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(panel.workspace.isOpen('labwork', slot: kAttachedSlot), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chip says what its attachment holds, not only its name',
      (tester) async {
    final panel = hostPanel();
    Widget preview(String key) => SizedBox.square(
          key: ValueKey(key),
          dimension: 14,
          child: const ColoredBox(color: Color(0xFF3366CC)),
        );
    final session = FakeSession(
      itemId: 'visit-previewed',
      windows: [
        FakeSession.window('chart', saveLabel: 'saveVisit'),
        FakeSession.window(
          'labwork',
          saveLabel: 'saveVisit',
          attachedTo: PanelWindow.bandAttachment,
          chipPreview: () => preview('order-state'),
        ),
        FakeSession.window(
          'gallery',
          saveLabel: 'saveVisit',
          attachedTo: PanelWindow.bandAttachment,
          chipPreview: () => preview('picture'),
        ),
      ],
    );
    session.band = const SizedBox(height: 30);
    panel.attach(session, focus: 'chart');
    await pumpShell(tester, panel);

    for (final (windowId, key) in [
      ('labwork', 'order-state'),
      ('gallery', 'picture'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(
            WK.attachmentToggle(windowId, owner: PanelWindow.bandAttachment),
          ),
          matching: find.byKey(ValueKey(key)),
        ),
        findsOneWidget,
        reason: 'a chip previews its record inside the chip, not beside it',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a patient context strip is not drawn: the record is the context',
      (tester) async {
    final panel = hostPanel();
    await pumpShell(tester, panel);

    expect(find.text('1989 · 37y · Penicillin allergy'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a slot names the block, a group id names the record', () {
    // Layout memory is keyed by slot, never by record id, so every visit opens
    // the way the last one was left.
    expect(rowKey(kAttachedSlot, 'operative'), 'attached/operative');
    expect(slotOfRowKey('attached/operative'), kAttachedSlot);
    expect(windowIdOfRowKey('attached/operative'), 'operative');
  });

  test('the band answers the panel\'s dirty question through the session', () {
    final panel = hostPanel();
    final session = visit();
    panel.attach(session);
    expect(panel.anyUnsavedChanges, isFalse);

    session.hasWork = true;
    panel.refreshDirty();

    expect(panel.anyUnsavedChanges, isTrue);
    expect(panel.hasUnsavedChanges(), isTrue);
  });
}
