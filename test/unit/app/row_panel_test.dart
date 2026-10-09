import 'package:apexo/app/panels/panel_tab.dart';
import 'package:apexo/app/panels/row_panel.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved panel drafts remain isolated from stored records', () async {
    final store = Store<Note>(modeling: Note.fromJson);
    addTearDown(store.observableMap.dispose);
    final draft = Note.fromJson({
      'id': 'note',
      'attachments': ['saved']
    });
    final panel = RowPanel<Note>(
      item: draft,
      store: store,
      title: 'note',
      singularName: 'note',
      unicodeSymbol: '',
      icon: FluentIcons.edit,
      tabs: [
        PanelTab(title: 'note', icon: FluentIcons.edit, body: const SizedBox())
      ],
    );
    await panel.save();
    draft.attachments.add('unsaved');
    expect(store.get('note')!.attachments, ['saved']);
    expect(panel.hasPendingEdits, isTrue);
    // Archiving persists the **whole draft**, unsaved edits included: the panel
    // is deleted the moment the archive lands, so a later close must not ask
    // about work that was just stored (`appointments 11` is that regression).
    await panel.setArchived(true);
    expect(draft.archived, isTrue);
    expect(store.get('note')!.archived, isTrue);
    expect(store.get('note')!.attachments, ['saved', 'unsaved']);
    expect(panel.hasPendingEdits, isFalse);
    // …and a change made *after* the archive stays a draft again.
    draft.attachments.add('after-archive');
    expect(store.get('note')!.attachments, ['saved', 'unsaved']);
    expect(panel.hasPendingEdits, isTrue);
    await panel.setArchived(false);
    expect(draft.archived, isFalse);
    expect(store.get('note')!.archived, isFalse);
  });
}
