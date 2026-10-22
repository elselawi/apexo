@Tags(['serial'])
library;

import 'package:apexo/features/notes/note_card_widget.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

/// The note card's context menu: right click only — the long press belongs to
/// the drag — with the note's own actions, and only the ones this user may do.
void main() {
  late List<Note> previousNotes;
  late List<int> previousPermissions;

  setUp(() {
    previousNotes = notes.docs.values.toList();
    previousPermissions = login.savedPermissions;
    notes.observableMap.clear();
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    notes.observableMap.clear();
    notes.setAll(previousNotes);
    login.savedPermissions = previousPermissions;
  });

  Future<void> pumpCard(WidgetTester tester, Note note) async {
    notes.set(note);
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 320,
          height: 600,
          child: NoteCard(note: note),
        ),
      ),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    expect(find.byType(MenuFlyout), findsNothing);
    await tester.tap(find.byType(NoteCard), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  Finder item(String text) => find.descendant(
        of: find.byType(MenuFlyout),
        matching: find.text(text),
      );

  String downloadAttachments() => "${txt("download")} ${txt("attachments")}";

  testWidgets('right clicking a note opens its menu', (tester) async {
    await pumpCard(
      tester,
      testNote(
        id: 'note-menu',
        note: 'Call the lab',
        attachments: ['a.png', 'b.pdf'],
      ),
    );

    await openMenu(tester);

    expect(item(txt("open")), findsWidgets);
    expect(item(downloadAttachments()), findsWidgets);
    expect(item(txt("assignedTo")), findsWidgets);
    expect(item(txt("changeDueDate")), findsWidgets);
    expect(item(txt("delete")), findsWidgets);
    // The attachment count rides in the suffix slot, parenthesised like the
    // other counts.
    expect(item('(2)'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a note without attachments offers no download', (tester) async {
    await pumpCard(tester, testNote(id: 'note-no-files', note: 'No files'));

    await openMenu(tester);

    expect(item(downloadAttachments()), findsNothing);
    expect(item(txt("delete")), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a user who may not edit sees only the view actions',
      (tester) async {
    login.savedPermissions = Perm.zeroes;
    await pumpCard(
      tester,
      testNote(
        id: 'note-read-only',
        note: 'Someone else wrote this',
        createdBy: 'another-account',
        attachments: ['a.png'],
      ),
    );

    await openMenu(tester);

    // Opening the card and taking a file are reads: still there.
    expect(item(txt("open")), findsWidgets);
    expect(item(downloadAttachments()), findsWidgets);
    // Assignment, due date and delete are writes: not there at all, not greyed.
    expect(item(txt("assignedTo")), findsNothing);
    expect(item(txt("changeDueDate")), findsNothing);
    expect(item(txt("delete")), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
