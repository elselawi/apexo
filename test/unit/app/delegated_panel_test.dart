/// Pins the contract of a panel that keeps its own drafts: every question the
/// panel host asks about persistence — is there work to save, save it, is it
/// archived — is answered by the callbacks the caller supplied, and a caller
/// that cannot archive is offered no archive button rather than a dead one.
library;

import 'package:apexo/app/panels/delegated_panel.dart';
import 'package:apexo/app/panels/panel_tab.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DelegatedPanel panelFor({
    bool isNew = false,
    String? newTitle,
    bool Function()? checkArchived,
    Future<void> Function(bool archived)? onSetArchived,
    Widget? archiveButtonReplacement,
    Future<List<String>> Function()? onSave,
    bool Function()? checkUnsavedChanges,
    Future<String?> Function()? recordTitle,
  }) =>
      DelegatedPanel(
        itemId: 'supplier1',
        singularName: 'orders',
        unicodeSymbol: '📁',
        icon: WindowsIcons.folder,
        isNew: isNew,
        newTitle: newTitle,
        checkArchived: checkArchived,
        onSetArchived: onSetArchived,
        archiveButtonReplacement: archiveButtonReplacement,
        checkUnsavedChanges: checkUnsavedChanges ?? () => false,
        onSave: onSave ?? () async => const [],
        recordTitle: recordTitle,
        tabs: [
          PanelTab(
            title: 'orders',
            icon: WindowsIcons.folder,
            body: const SizedBox.shrink(),
          ),
        ],
      );

  test('pending edits are whatever the callback reports', () {
    var dirty = false;
    final panel = panelFor(checkUnsavedChanges: () => dirty);

    expect(panel.hasPendingEdits, isFalse);
    dirty = true;
    expect(panel.hasPendingEdits, isTrue,
        reason: 'the panel has no snapshot of its own to compare');
  });

  test('save is the caller\'s save, so it can never be a silent no-op',
      () async {
    var saves = 0;
    final panel = panelFor(onSave: () async {
      saves++;
      return const [];
    });

    await panel.save();

    expect(saves, 1);
  });

  test('an archived record greys the title through the callback', () {
    expect(panelFor().isArchived, isFalse,
        reason: 'a panel that reports no archive flag is not archived');
    expect(panelFor(checkArchived: () => true).isArchived, isTrue);
  });

  test('archiving is the caller\'s archive', () async {
    final archived = <bool>[];
    final panel = panelFor(onSetArchived: (value) async => archived.add(value));

    await panel.setArchived(true);
    await panel.setArchived(false);

    expect(archived, [true, false]);
  });

  test('a caller who cannot archive is offered no archive button', () {
    expect(panelFor().archiveButtonReplacement, isA<SizedBox>(),
        reason: 'the host would otherwise draw a delete that deletes nothing');
  });

  test('the host draws its own archive button once archiving works', () async {
    final panel = panelFor(onSetArchived: (value) async {});

    // `null` means "no replacement": the host's own button calls setArchived.
    expect(panel.archiveButtonReplacement, isNull);
    await panel.setArchived(true);
  });

  test('a replacement fills the archive slot when it is given', () {
    const replacement = SizedBox(width: 42);
    expect(
        panelFor(archiveButtonReplacement: replacement)
            .archiveButtonReplacement,
        same(replacement));
    expect(
        panelFor(
          archiveButtonReplacement: replacement,
          onSetArchived: (value) async {},
        ).archiveButtonReplacement,
        same(replacement),
        reason: 'a deliberate replacement wins over the default button');
  });

  test('a new record is identified before it is stored', () {
    final stored = panelFor();
    expect(stored.isNew, isFalse);
    expect(stored.itemId, 'supplier1');
    expect(stored.identifier, 'supplier1');

    final unsaved = panelFor(isNew: true);
    expect(unsaved.isNew, isTrue);
    expect(unsaved.identifier, 'new+orders',
        reason: 'a record that does not exist yet has no id to be found by');
  });

  test('saving cannot re-baseline the caller\'s verdict', () async {
    final panel = panelFor(checkUnsavedChanges: () => true);

    await panel.save();

    expect(panel.hasPendingEdits, isTrue,
        reason: 'the panel keeps no snapshot of its own to clear: when the '
            'caller\'s drafts go clean the callback says so, and until then a '
            'save changes nothing');
  });

  test('records what the caller\'s save answered with', () async {
    // The caller holds the drafts, so its save is what says which records were
    // written; the panel records the answer, so no caller has to report it.
    final panel = panelFor(onSave: () async => ['order1', 'order2', 'order1']);

    expect(panel.savedId, isNull, reason: 'nothing has been saved yet');
    expect(panel.savedIds, isEmpty);

    await panel.save();

    expect(panel.savedIds, ['order1', 'order2'],
        reason: 'every record the save wrote, once each, in the order written');
    expect(panel.savedId, 'order1',
        reason: 'the one id an opener hands back for a panel that wrote two');
  });

  test('hands back nothing when the caller\'s save wrote nothing', () async {
    final panel = panelFor(checkUnsavedChanges: () => false);

    await panel.save();

    expect(panel.savedId, isNull,
        reason: 'the user closed with no changes: same answer as a cancel');
  });

  test('names the record its caller pointed it at', () async {
    final panel = panelFor(recordTitle: () async => 'Supplier One');

    expect(panel.displayTitle, 'supplier1',
        reason: 'nothing named the record yet, so the id is all there is');

    await panel.readTitle();
    expect(panel.displayTitle, 'Supplier One');

    // Re-read on every save, so a name that only becomes real when the record is
    // written shows too.
    await panel.save();
    expect(panel.displayTitle, 'Supplier One',
        reason: 'never `itemId`, which is an id whenever the caller had one');
  });

  test('shows the placeholder while the record does not exist yet', () {
    expect(
        panelFor(isNew: true, newTitle: 'New order').displayTitle, 'New order');
  });

  test('an empty title does not blank the header', () async {
    final panel = panelFor(recordTitle: () async => '   ');

    await panel.save();

    expect(panel.displayTitle, 'supplier1',
        reason: 'an empty answer counts as none, so the fallback shows');
  });

  test('a delegated panel has no edit signal, so the host samples it', () {
    expect(panelFor().pendingEditsSignal, isNull,
        reason: 'its verdict is the caller\'s callback: nothing to push');
  });
}
