/// Pins the contract that makes a panel awaitable: a panel is finished when it
/// is saved or when it leaves the screen, and its future always resolves.
///
/// `RowPanel`'s half — the stored row a save hands back — is in
/// `row_panel_test.dart`.
@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/app/panels/delegated_panel.dart';
import 'package:apexo/app/panels/panel.dart';
import 'package:apexo/app/panels/panel_tab.dart';
import 'package:apexo/app/panels/panels_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A panel that owns nothing, so the tests never touch a store: everything
  /// this file asserts is the base class's machinery.
  DelegatedPanel panelFor({String itemId = 'supplier1'}) => DelegatedPanel(
        itemId: itemId,
        singularName: 'orders',
        unicodeSymbol: '📁',
        icon: WindowsIcons.folder,
        checkUnsavedChanges: () => false,
        onSave: () async => const [],
        tabs: [
          PanelTab(
            title: 'orders',
            icon: WindowsIcons.folder,
            body: const SizedBox.shrink(),
          ),
        ],
      );

  /// Whether [panel]'s result has settled.
  ///
  /// The public contract is the future, not the completer behind it, so the
  /// question is asked the way a caller asks it: does a listener run?
  Future<bool> settled(Panel panel) async {
    var done = false;
    unawaited(panel.result.whenComplete(() {
      done = true;
    }));
    await pumpEventQueue();
    return done;
  }

  setUp(PanelsManager.closeAll);
  tearDown(PanelsManager.closeAll);

  group('a panel is finished when', () {
    test('it is saved', () async {
      final panel = panelFor();
      expect(await settled(panel), isFalse,
          reason: 'nothing has been saved or closed yet');

      await panel.save();

      expect(await settled(panel), isTrue);
    });

    test('it is closed, save or no save', () async {
      final panel = panelFor();
      PanelsManager.open(panel);

      PanelsManager.close(panel.itemId);

      expect(PanelsManager.active(), isEmpty);
      expect(await settled(panel), isTrue,
          reason: 'a closed panel will never be saved');
    });

    test('every panel is closed at once', () async {
      final first = panelFor(itemId: 'supplier1');
      final second = panelFor(itemId: 'supplier2');
      PanelsManager.open(first);
      PanelsManager.open(second);

      PanelsManager.closeAll();

      expect(await settled(first), isTrue);
      expect(await settled(second), isTrue);
    });
  });

  test('saving blocks duplicate writes and clears progress after failure', () async {
    final write = Completer<List<String>>();
    var calls = 0;
    final panel = DelegatedPanel(
      itemId: 'new-record',
      singularName: 'orders',
      unicodeSymbol: '📁',
      icon: WindowsIcons.folder,
      isNew: true,
      checkUnsavedChanges: () => true,
      onSave: () {
        calls++;
        return write.future;
      },
      tabs: [],
    );

    final saving = panel.save();
    expect(panel.inProgress(), isTrue);
    await panel.save();
    expect(calls, 1);
    final failure = expectLater(saving, throwsStateError);
    write.completeError(StateError('write failed'));
    await failure;
    expect(panel.inProgress(), isFalse);
    expect(panel.isNew, isTrue);
    expect(await settled(panel), isFalse);
  });

  test('a successful delegated save changes a new panel into an existing one', () async {
    final panel = DelegatedPanel(
      itemId: 'new-record',
      singularName: 'orders',
      unicodeSymbol: '📁',
      icon: WindowsIcons.folder,
      isNew: true,
      checkUnsavedChanges: () => true,
      onSave: () async => ['new-record'],
      tabs: [],
    );

    await panel.save();
    expect(panel.inProgress(), isFalse);
    expect(panel.isNew, isFalse);
    expect(panel.identifier, 'new-record');
    expect(panel.savedId, 'new-record');
  });

  group('finishing is idempotent', () {
    test('a second finish adds nothing', () async {
      final panel = panelFor();

      panel.settle();
      panel.settle();

      await panel.result;
    });

    test('saving and then closing is still one answer', () async {
      final panel = panelFor();
      PanelsManager.open(panel);

      await panel.save();
      PanelsManager.close(panel.itemId);

      await panel.result;
      expect(await settled(panel), isTrue);
    });
  });

  group('the manager', () {
    test('shows one panel per record and finishes the one it merged', () async {
      final first = panelFor();
      final second = panelFor();

      expect(PanelsManager.open(first), same(first),
          reason: 'a panel with no duplicate is the one on screen');
      expect(PanelsManager.open(second), same(first),
          reason: 'the caller must be handed the panel that stays, because the '
              'duplicate is finished on the spot and its own future resolves '
              'as if the user had cancelled');

      expect(PanelsManager.active(), [first],
          reason: 'a record is edited in one panel; the second is merged into '
              'the first rather than stacked');
      expect(await settled(second), isTrue,
          reason: 'a merged panel is never saved, so nobody may wait on it');
      expect(await settled(first), isFalse,
          reason: 'the panel on screen is still open and still editable');
    });

    test('leaves an open panel alone when another one closes', () async {
      final open = panelFor(itemId: 'supplier1');
      final other = panelFor(itemId: 'supplier2');
      PanelsManager.open(open);
      PanelsManager.open(other);

      PanelsManager.close(other.itemId);

      expect(PanelsManager.active(), [open]);
      expect(await settled(open), isFalse);
    });
  });
}
