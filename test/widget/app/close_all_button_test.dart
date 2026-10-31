@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/close_all_button.dart';
import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/workspace_close_dialog.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

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

  Panel panel({
    bool dirty = false,
    bool Function()? hasChanges,
    Future<List<String>> Function()? onSave,
    String id = 'close-all-panel',
  }) =>
      DelegatedPanel(
        itemId: id,
        singularName: 'patient',
        unicodeSymbol: '👤',
        icon: FluentIcons.medication_admin,
        checkUnsavedChanges: hasChanges ?? () => dirty,
        onSave: onSave ?? () async => const [],
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

  testWidgets('stays visible and counts a panel with unsaved work',
      (tester) async {
    PanelsManager.active([panel(dirty: true)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    expect(presence(tester), 1);
    expect(find.text('1'), findsOneWidget);
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

  testWidgets('stays visible while a standing window holds unsaved work',
      (tester) async {
    WindowsManager.showStandalone(
      windowModel(),
      onSave: () async {},
      hasChanges: () => true,
    );
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();

    expect(presence(tester), 1);
    expect(find.text('1'), findsOneWidget);
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
    expect(button.top, kWindowEdgeInset);
    expect(button.bottom, lessThan(kWorkspaceCommandHeight));
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

  Future<void> openConfirmation(WidgetTester tester) async {
    await tester.tap(find.byKey(WK.closeAllWindows));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceCloseDialog), findsOneWidget);
  }

  Finder itemMenu(String title) =>
      find.widgetWithText(DropDownButton, title).last;

  Future<void> itemAction(
    WidgetTester tester,
    String title,
    String action, {
    bool settle = true,
  }) async {
    await tester.tap(itemMenu(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt(action)).last);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }
  }

  testWidgets('record dropdown titles align to the start edge in LTR and RTL',
      (tester) async {
    final draft = panel(id: 'Short title', dirty: true);
    PanelsManager.active([draft]);
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      await pumpApexoApp(
        tester,
        Directionality(
          textDirection: direction,
          child: WorkspaceCloseDialog(request: WorkspaceCloseRequest()),
        ),
      );
      final dropdown = tester.getRect(find.byKey(ObjectKey(draft)));
      final title = find.text(draft.displayTitle).last;
      final rect = tester.getRect(title);
      expect(tester.widget<Text>(title).textAlign, TextAlign.start);
      if (direction == TextDirection.ltr) {
        expect(rect.left - dropdown.left, lessThan(48));
      } else {
        expect(dropdown.right - rect.right, lessThan(48));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('item actions resolve only the chosen panel and close when empty',
      (tester) async {
    var dirty = true;
    var saves = 0;
    final first = panel(
      id: 'First record',
      hasChanges: () => dirty,
      onSave: () async {
        saves++;
        dirty = false;
        return ['saved'];
      },
    );
    final second = panel(id: 'Second record', dirty: true);
    PanelsManager.active([first, second]);
    final cleanWindow = WindowsManager.showStandalone(windowModel());
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);

    await itemAction(tester, first.displayTitle, 'workspaceSaveItemAndClose');
    expect(saves, 1);
    expect(PanelsManager.active(), [second]);
    expect(WindowsManager.open(), [cleanWindow]);
    expect(find.byKey(ObjectKey(first)), findsNothing);
    expect(find.byKey(ObjectKey(second)), findsOneWidget);
    expect(find.byType(WorkspaceCloseDialog), findsOneWidget);

    await itemAction(
        tester, second.displayTitle, 'workspaceIgnoreItemAndClose');
    expect(saves, 1);
    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open(), isEmpty);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets('parent close waits until each unsaved visit is resolved',
      (tester) async {
    var dirty = true;
    final parent = panel(
      id: 'Parent record',
      hasChanges: () => dirty,
      onSave: () async {
        dirty = false;
        return ['saved'];
      },
    );
    final retained = FakeSession(
      itemId: 'retained',
      displayTitleText: 'Retained visit',
      windows: [],
      hasWork: true,
    );
    final attached = FakeSession(
      itemId: 'attached',
      displayTitleText: 'Attached visit',
      windows: [],
      hasWork: true,
    );
    parent.attach(retained);
    parent.detach();
    parent.attach(attached);
    PanelsManager.active([parent]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);

    List<MenuFlyoutItem> parentActions() => tester
        .widget<DropDownButton>(find.byKey(ObjectKey(parent)))
        .items
        .whereType<MenuFlyoutItem>()
        .toList();
    expect(parentActions()[0].onPressed, isNotNull);
    expect(parentActions()[1].onPressed, isNull);
    expect(parentActions()[2].onPressed, isNull);
    expect(find.text(txt('workspaceResolveVisitsFirst')), findsWidgets);

    await itemAction(
        tester, retained.displayTitle, 'workspaceSaveItemAndClose');
    expect(retained.saves, ['retained']);
    expect(retained.isDisposed, isTrue);
    expect(parent.owned, [attached]);
    expect(parentActions()[1].onPressed, isNull);
    expect(find.byKey(ObjectKey(retained)), findsNothing);

    await itemAction(
        tester, attached.displayTitle, 'workspaceIgnoreItemAndClose');
    expect(attached.saves, isEmpty);
    expect(attached.isDisposed, isTrue);
    expect(parent.owned, isEmpty);
    expect(parentActions()[1].onPressed, isNotNull);
    expect(parentActions()[2].onPressed, isNotNull);
    expect(find.byType(WorkspaceCloseDialog), findsOneWidget);

    await itemAction(tester, parent.displayTitle, 'workspaceSaveItemAndClose');
    expect(PanelsManager.active(), isEmpty);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets('failed individual save keeps its item and other drafts open',
      (tester) async {
    final failed = panel(id: 'Failed record', dirty: true);
    final other = panel(id: 'Other record', dirty: true);
    PanelsManager.active([failed, other]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await itemAction(tester, failed.displayTitle, 'workspaceSaveItemAndClose');
    expect(find.byType(InfoBar), findsOneWidget);
    expect(PanelsManager.active(), [failed, other]);
    expect(find.byKey(ObjectKey(failed)), findsOneWidget);
    expect(find.byKey(ObjectKey(other)), findsOneWidget);

    await itemAction(
        tester, failed.displayTitle, 'workspaceIgnoreItemAndClose');
    expect(find.byType(InfoBar), findsNothing);
    expect(PanelsManager.active(), [other]);
    expect(find.byKey(ObjectKey(failed)), findsNothing);
  });

  testWidgets('standalone item saves or ignores only its own draft',
      (tester) async {
    var dirty = true;
    var saves = 0;
    final first = WindowsManager.showStandalone(
      const PanelWindow(
          id: 'first',
          title: 'First window',
          icon: FluentIcons.edit,
          body: SizedBox.shrink()),
      hasChanges: () => dirty,
      onSave: () async {
        saves++;
        dirty = false;
      },
    );
    final second = WindowsManager.showStandalone(
      const PanelWindow(
          id: 'second',
          title: 'Second window',
          icon: FluentIcons.edit,
          body: SizedBox.shrink()),
      hasChanges: () => true,
    );
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    final secondActions = tester
        .widget<DropDownButton>(find.byKey(ObjectKey(second)))
        .items
        .whereType<MenuFlyoutItem>()
        .toList();
    expect(secondActions[1].onPressed, isNull);
    expect(secondActions[2].onPressed, isNotNull);

    await itemAction(tester, WorkspaceCloseRequest.windowTitle(first),
        'workspaceSaveItemAndClose');
    expect(saves, 1);
    expect(WindowsManager.open(), [second]);
    expect(find.byKey(ObjectKey(first)), findsNothing);
    expect(find.byType(WorkspaceCloseDialog), findsOneWidget);

    await itemAction(tester, WorkspaceCloseRequest.windowTitle(second),
        'workspaceIgnoreItemAndClose');
    expect(WindowsManager.open(), isEmpty);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets('individual save disables all menus until it finishes',
      (tester) async {
    var dirty = true;
    final pending = Completer<void>();
    final first = panel(
      id: 'Saving record',
      hasChanges: () => dirty,
      onSave: () async {
        await pending.future;
        dirty = false;
        return ['saved'];
      },
    );
    final second = panel(id: 'Waiting record', dirty: true);
    PanelsManager.active([first, second]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await itemAction(tester, first.displayTitle, 'workspaceSaveItemAndClose',
        settle: false);

    expect(PanelsManager.active(), [first, second]);
    for (final dropdown
        in tester.widgetList<DropDownButton>(find.byType(DropDownButton))) {
      expect(dropdown.disabled, isTrue);
    }
    pending.complete();
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), [second]);
    expect(
        tester.widget<DropDownButton>(find.byKey(ObjectKey(second))).disabled,
        isFalse);
  });

  testWidgets('dialog closes automatically when its last draft becomes clean',
      (tester) async {
    var dirty = true;
    PanelsManager.active([panel(hasChanges: () => dirty)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    dirty = false;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), isEmpty);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets('review brings the existing panel forward without saving',
      (tester) async {
    var saves = 0;
    final draft = panel(
        dirty: true,
        onSave: () async {
          saves++;
          return [];
        });
    final foreground = panel(id: 'foreground');
    PanelsManager.active([draft, foreground]);
    PanelsManager.minimize(true);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);

    await itemAction(tester, draft.displayTitle, 'openRecord');

    expect(find.byType(WorkspaceCloseDialog), findsNothing);
    expect(PanelsManager.active(), [foreground, draft]);
    expect(PanelsManager.minimize(), isFalse);
    expect(draft.hasPendingEdits, isTrue);
    expect(saves, 0);
  });

  testWidgets('review reattaches a retained visit without replacing any draft',
      (tester) async {
    final draft = panel();
    final retained = FakeSession(
      itemId: 'retained',
      displayTitleText: 'Retained visit',
      windows: [FakeSession.window('retained-editor')],
      hasWork: true,
    );
    final selected = FakeSession(
      itemId: 'selected',
      displayTitleText: 'Selected visit',
      windows: [],
      hasWork: true,
    );
    draft.attach(retained);
    draft.detach();
    draft.attach(selected);
    final foreground = panel(id: 'foreground');
    PanelsManager.active([draft, foreground]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);

    await itemAction(tester, retained.displayTitle, 'openRecord');

    expect(PanelsManager.active(), [foreground, draft]);
    expect(draft.attached, same(retained));
    expect(draft.attachedFocus, 'retained-editor');
    expect(draft.owned, [retained, selected]);
    expect(retained.hasPendingEdits, isTrue);
    expect(selected.hasPendingEdits, isTrue);
    expect(retained.saves, isEmpty);
    expect(selected.saves, isEmpty);
    expect(retained.isDisposed, isFalse);
    expect(selected.isDisposed, isFalse);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets(
      'review raises the same standalone window instead of reopening it',
      (tester) async {
    var saves = 0;
    var recordOpens = 0;
    final target = WindowsManager.showStandalone(
      windowModel(),
      scope: 'target',
      hasChanges: () => true,
      onSave: () async => saves++,
      onOpenRecord: () async => recordOpens++,
    );
    final foreground =
        WindowsManager.showStandalone(windowModel(), scope: 'front');
    WindowsManager.takeFocus();
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();
    await openConfirmation(tester);

    await itemAction(
        tester, WorkspaceCloseRequest.windowTitle(target), 'openRecord');

    expect(WindowsManager.open(), [foreground, target]);
    expect(WindowsManager.open().last, same(target));
    expect(WindowsManager.takeFocus(), target.key);
    expect(target.hasChanges!(), isTrue);
    expect(saves, 0);
    expect(recordOpens, 0);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets('review does not reopen a record removed after the dialog opened',
      (tester) async {
    final draft = panel(dirty: true);
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    PanelsManager.close(draft.identifier);
    final incoming = panel(id: 'incoming', dirty: true);
    PanelsManager.open(incoming);

    await itemAction(tester, draft.displayTitle, 'openRecord');

    expect(find.text(txt('workspaceChanged')), findsOneWidget);
    expect(PanelsManager.active(), [incoming]);
    expect(find.byType(WorkspaceCloseDialog), findsOneWidget);
  });

  testWidgets('Cancel and Escape preserve every draft', (tester) async {
    final draft = panel(dirty: true);
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    await openConfirmation(tester);
    expect(itemMenu(draft.displayTitle), findsOneWidget);
    await tester.tap(find.text(txt('cancel')).last);
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), [draft]);
    expect(draft.hasPendingEdits, isTrue);

    await openConfirmation(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
    expect(PanelsManager.active(), [draft]);
  });

  testWidgets('Discard closes everything without saving', (tester) async {
    var saves = 0;
    final draft = panel(
        dirty: true,
        onSave: () async {
          saves++;
          return [];
        });
    final visit = FakeSession(itemId: 'retained', windows: [], hasWork: true);
    draft.attach(visit);
    draft.detach();
    PanelsManager.active([draft]);
    WindowsManager.showStandalone(windowModel(),
        hasChanges: () => true, onSave: () async => saves++);
    await pumpButton(tester);
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    await openConfirmation(tester);
    expect(itemMenu(visit.displayTitle), findsOneWidget);
    await tester.tap(find.text(txt('workspaceDiscardAndClose')).last);
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(visit.saves, isEmpty);
    expect(visit.isDisposed, isTrue);
    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open(), isEmpty);
  });

  testWidgets('saves owners once, including detached visits, before closing',
      (tester) async {
    var dirty = true;
    var windowDirty = true;
    final writes = <String>[];
    final draft = panel(
        hasChanges: () => dirty,
        onSave: () async {
          writes.add('panel');
          dirty = false;
          return ['saved'];
        });
    final visit = FakeSession(itemId: 'retained', windows: [], hasWork: true);
    draft.attach(visit);
    draft.detach();
    final attached =
        FakeSession(itemId: 'attached', windows: [], hasWork: true);
    draft.attach(attached);
    PanelsManager.active([draft]);
    WindowsManager.showStandalone(windowModel(),
        hasChanges: () => windowDirty,
        onSave: () async {
          expect(dirty, isFalse);
          expect(visit.saves, ['retained']);
          expect(attached.saves, ['attached']);
          expect(PanelsManager.active(), [draft]);
          writes.add('window');
          windowDirty = false;
        });
    await pumpButton(tester);
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    await openConfirmation(tester);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pumpAndSettle();

    expect(writes, ['panel', 'window']);
    expect(visit.isDisposed, isTrue);
    expect(attached.isDisposed, isTrue);
    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open(), isEmpty);
    expect(find.byType(WorkspaceCloseDialog), findsNothing);
  });

  testWidgets('a failed save closes nothing and retry skips saved owners',
      (tester) async {
    var dirty = true;
    var fail = true;
    var windowDirty = true;
    var panelSaves = 0;
    final draft = panel(
        hasChanges: () => dirty,
        onSave: () async {
          panelSaves++;
          dirty = false;
          return ['saved'];
        });
    PanelsManager.active([draft]);
    final floating = WindowsManager.showStandalone(windowModel(),
        hasChanges: () => windowDirty,
        onSave: () async {
          if (fail) throw StateError('write failed');
          windowDirty = false;
        });
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pumpAndSettle();

    expect(find.byType(InfoBar), findsOneWidget);
    expect(PanelsManager.active(), [draft]);
    expect(WindowsManager.open(), [floating]);
    expect(panelSaves, 1);
    expect(windowDirty, isTrue);

    fail = false;
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pumpAndSettle();
    expect(panelSaves, 1);
    expect(PanelsManager.active(), isEmpty);
    expect(WindowsManager.open(), isEmpty);
  });

  testWidgets('a save that leaves validation errors never closes the workspace',
      (tester) async {
    final draft = panel(dirty: true);
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pumpAndSettle();

    expect(find.byType(InfoBar), findsOneWidget);
    expect(PanelsManager.active(), [draft]);
    expect(draft.hasPendingEdits, isTrue);
  });

  testWidgets('rechecks changes on activation, before the next sample',
      (tester) async {
    var dirty = false;
    final draft = panel(hasChanges: () => dirty);
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    dirty = true;
    await openConfirmation(tester);
    expect(PanelsManager.active(), [draft]);
  });

  testWidgets('updates the badge without hiding the command', (tester) async {
    var dirty = false;
    PanelsManager.active([panel(hasChanges: () => dirty)]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
    dirty = true;
    await tester.pump(const Duration(milliseconds: 400));
    expect(presence(tester), 1);
    expect(find.text('1'), findsOneWidget);
    dirty = false;
    await tester.pump(const Duration(milliseconds: 400));
    expect(presence(tester), 1);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('prevents repeated saves, discard and Escape while saving',
      (tester) async {
    var dirty = true;
    final pending = Completer<void>();
    var saves = 0;
    final draft = panel(
        hasChanges: () => dirty,
        onSave: () async {
          saves++;
          await pending.future;
          dirty = false;
          return ['saved'];
        });
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pump();

    final dialog = find.byType(WorkspaceCloseDialog);
    final dropdown =
        tester.widget<DropDownButton>(itemMenu(draft.displayTitle));
    expect(dropdown.disabled, isTrue);
    for (final button in tester.widgetList<Button>(find.descendant(
      of: dialog,
      matching: find.byType(Button),
    ))) {
      expect(button.onPressed, isNull);
    }
    expect(
        tester
            .widget<FilledButton>(find.descendant(
              of: dialog,
              matching: find.byType(FilledButton),
            ))
            .onPressed,
        isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(dialog, findsOneWidget);
    expect(PanelsManager.active(), [draft]);
    expect(saves, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), isEmpty);
  });

  testWidgets('does not close a workspace changed during an asynchronous save',
      (tester) async {
    var dirty = true;
    final pending = Completer<void>();
    final draft = panel(
        hasChanges: () => dirty,
        onSave: () async {
          await pending.future;
          dirty = false;
          return ['saved'];
        });
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pump();
    final incoming = panel(id: 'incoming', dirty: true);
    PanelsManager.open(incoming);
    pending.complete();
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), [draft, incoming]);
    expect(find.text(txt('workspaceChanged')), findsOneWidget);
  });

  testWidgets('does not discard a visit attached after confirmation opened',
      (tester) async {
    final draft = panel(dirty: true);
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    final incoming =
        FakeSession(itemId: 'incoming', windows: [], hasWork: true);
    draft.attach(incoming);
    await tester.tap(find.text(txt('workspaceDiscardAndClose')).last);
    await tester.pumpAndSettle();

    expect(incoming.isDisposed, isFalse);
    expect(PanelsManager.active(), [draft]);
    expect(find.text(txt('workspaceChanged')), findsOneWidget);
  });

  testWidgets('does not close a panel while its own save is running',
      (tester) async {
    final draft = panel();
    PanelsManager.active([draft]);
    await pumpButton(tester);
    await tester.pumpAndSettle();
    draft.inProgress(true);
    // Even an enabled button from the last sample must recheck the live owner.
    await tester.tap(find.byKey(WK.closeAllWindows));
    await tester.pump();
    expect(PanelsManager.active(), [draft]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Button>(find.byKey(WK.closeAllWindows)).onPressed,
        isNull);
    draft.inProgress(false);
  });

  testWidgets('windows stay below the command, including after dragging upward',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WindowsManager.showStandalone(windowModel());
    await pumpApexoApp(
        tester,
        const Stack(children: [
          WindowsLayer(visible: true, screenWidth: 1400),
          CloseAllButton(screenWidth: 1400, panelWidth: 0),
        ]));
    await tester.pumpAndSettle();

    final title = find.text(txt('xRayViewer')).last;
    final command = tester.getRect(find.byKey(WK.closeAllWindows));
    expect(tester.getTopLeft(title).dy, greaterThan(command.bottom));
    await tester.drag(title, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, greaterThan(command.bottom));
  });

  testWidgets('saves a standalone draft and names its record in confirmation',
      (tester) async {
    var dirty = true;
    WindowsManager.showStandalone(
      PanelWindow(
        id: 'standalone',
        title: 'patientDetails',
        subtitle: () => 'Patient A',
        icon: FluentIcons.edit,
        body: const SizedBox.shrink(),
      ),
      hasChanges: () => dirty,
      onSave: () async => dirty = false,
    );
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    expect(itemMenu('${txt('patientDetails')} — Patient A'), findsOneWidget);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pumpAndSettle();
    expect(dirty, isFalse);
    expect(WindowsManager.open(), isEmpty);
  });

  testWidgets('a dirty window without a save callback cannot be silently lost',
      (tester) async {
    final floating =
        WindowsManager.showStandalone(windowModel(), hasChanges: () => true);
    await pumpButton(tester, panelWidth: 0);
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    await tester.tap(find.text(txt('workspaceSaveAndClose')).last);
    await tester.pumpAndSettle();
    expect(find.byType(InfoBar), findsOneWidget);
    expect(WindowsManager.open(), [floating]);
  });

  testWidgets('phone sheets with no panel leave space for the command',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WindowsManager.showStandalone(windowModel());
    await pumpApexoApp(
        tester,
        const Stack(children: [
          WindowsLayer(visible: true, screenWidth: 390),
          CloseAllButton(screenWidth: 390, panelWidth: 0),
        ]));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(txt('xRayViewer')).last).dy,
        greaterThan(tester.getBottomLeft(find.byKey(WK.closeAllWindows)).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'translated commands and long confirmation lists fit every locale',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initialLocale = locale.selected();
    addTearDown(() => locale.select(initialLocale));
    PanelsManager.active([
      for (var i = 0; i < 12; i++)
        panel(id: '$i ${'Long record name ' * 5}', dirty: true),
    ]);
    for (var i = 0; i < locale.list.length; i++) {
      locale.select(i);
      await pumpApexoApp(
        tester,
        Directionality(
          textDirection: locale.s.$direction,
          child: WorkspaceCloseDialog(request: WorkspaceCloseRequest()),
        ),
      );
      expect(tester.takeException(), isNull, reason: locale.s.$code);
    }
  });

  testWidgets('top command stays within narrow workspace at large text sizes',
      (tester) async {
    tester.view.physicalSize = const Size(710, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PanelsManager.active([panel(dirty: true)]);
    await pumpApexoApp(
      tester,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(710, 700),
          textScaler: TextScaler.linear(2),
        ),
        child: Stack(children: [
          CloseAllButton(screenWidth: 710, panelWidth: 350),
        ]),
      ),
    );
    final rect = tester.getRect(find.byKey(WK.closeAllWindows));
    expect(rect.right, lessThan(710 - 350));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThan(kWorkspaceCommandHeight + kWindowEdgeInset));
    expect(tester.takeException(), isNull);
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
