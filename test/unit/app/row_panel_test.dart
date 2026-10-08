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
    await panel.setArchived(true);
    expect(draft.archived, isTrue);
    expect(store.get('note')!.archived, isTrue);
    expect(panel.hasPendingEdits, isTrue);
    await panel.setArchived(false);
    expect(draft.archived, isFalse);
    expect(store.get('note')!.archived, isFalse);
  });
}
