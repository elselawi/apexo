// The notes board: columns, cards, inline editing, drag between columns.
//
// The board is addressed by *name* rather than by key: a column carries its
// record's id and a card carries the note's id, so both are anonymous to a
// test. `Fixtures.boardColumn` / `Fixtures.noteCard` find them by the only
// thing a user names them by, and every card assertion is scoped to the card
// under test — the suite shares one database, so another test's "e2e" note is
// on the same board.
//
// Notes are stored in the same store as columns (`kind` tells them apart), and
// deleting is **archiving** (restorable), which is why nothing here asserts a
// row is gone from the database.
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

void registerNotesTests() {
  group('notes', () {
    testWidgets('01: the board renders its columns', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      expect(find.byKey(WK.btnAddColumn), findsOneWidget,
          reason: 'the board offers no way to add a column');
      expect(find.byKey(WK.btnNewNote), findsOneWidget,
          reason: 'the board offers no way to add a note');
      await E2E.waitFor(
        tester,
        await Fixtures.boardColumn(txt('uncategorized')),
        description: 'the uncategorized column',
      );

      // A column created through the UI becomes a board column.
      final column = Fixtures.stamp('e2e col');
      await Fixtures.addColumn(tester, column);
      expect(await Fixtures.boardColumn(column), findsOneWidget,
          reason: 'a column that was just added is not on the board');
    });

    testWidgets('02: a column can be added, renamed and archived',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      final first = Fixtures.stamp('e2e col');
      final second = Fixtures.stamp('e2e renamed');
      await Fixtures.addColumn(tester, first);
      await Fixtures.renameColumn(tester, first, second);
      expect(await Fixtures.columnExists(first), isFalse,
          reason: 'the old column name is still on the board');
      expect(await Fixtures.columnExists(second), isTrue,
          reason: 'the renamed column is not on the board');

      // Archiving is the board's delete; the archived column leaves the board.
      await Fixtures.archiveColumn(tester, second);
      expect(await Fixtures.columnExists(second), isFalse,
          reason: 'an archived column is still on the board');
    });

    testWidgets('03: a note can be created in a column', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      final column = Fixtures.stamp('e2e col');
      final title = Fixtures.stamp('e2e note');
      await Fixtures.addColumn(tester, column);
      await Fixtures.createNote(tester, title,
          note: 'a body written by the e2e suite', column: column);

      expect(
        find.descendant(
            of: await Fixtures.boardColumn(column), matching: find.text(title)),
        findsOneWidget,
        reason: 'a note created in a column is not shown in it',
      );

      final stored = await Fixtures.storedNote(title);
      expect(stored, isNotNull, reason: 'the note was not stored');
      expect(stored!.columnID, isNotEmpty,
          reason: 'the note was stored without the column it was created in');
      expect(stored.note, 'a body written by the e2e suite',
          reason: 'the note body was not stored');
    });

    testWidgets('04: a note can be created from the command bar',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      // No column: the note belongs to the uncategorized column.
      final title = Fixtures.stamp('e2e note');
      await Fixtures.createNote(tester, title);
      expect(
        find.descendant(
          of: await Fixtures.boardColumn(txt('uncategorized')),
          matching: find.text(title),
        ),
        findsOneWidget,
        reason: 'a note with no column is not shown in the uncategorized one',
      );

      final stored = await Fixtures.storedNote(title);
      expect(stored?.columnID, isEmpty,
          reason: 'a note created without a column was filed under one');
    });

    testWidgets('05: a note can be renamed and commented inline',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      final title = Fixtures.stamp('e2e note');
      final renamed = Fixtures.stamp('e2e renamed');
      await Fixtures.createNote(tester, title);
      await Fixtures.expandCard(tester, title);
      await Fixtures.renameNote(tester, title, renamed);
      await Fixtures.commentNote(tester, renamed, 'commented by the e2e suite');

      // The card is still on the board, now showing the new title in its
      // inline field — an expanded card has no title *label* to match anymore,
      // so it is found by its note id.
      final card =
          Fixtures.noteCardById((await Fixtures.noteNamed(renamed)).id);
      expect(
        find.descendant(of: card, matching: find.byKey(WK.noteCardTitle)),
        findsOneWidget,
        reason: 'the renamed card is no longer on the board',
      );
      final stored = await Fixtures.storedNote(renamed);
      expect(stored, isNotNull, reason: 'the renamed note is not stored');
      expect(stored!.note, 'commented by the e2e suite',
          reason: 'the inline comment was not stored');
    });

    testWidgets('06: a note can be dragged between columns', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      final from = Fixtures.stamp('e2e col');
      final to = Fixtures.stamp('e2e col');
      final title = Fixtures.stamp('e2e note');
      await Fixtures.addColumn(tester, from);
      await Fixtures.addColumn(tester, to);
      await Fixtures.createNote(tester, title, column: from);

      await Fixtures.dragNoteToColumn(tester, title, to);
      expect(
        find.descendant(
            of: await Fixtures.boardColumn(from), matching: find.text(title)),
        findsNothing,
        reason: 'the note is still shown in the column it came from',
      );

      final stored = await Fixtures.storedNote(title);
      expect(stored, isNotNull, reason: 'the moved note is not stored');
      final columns = notes.columns;
      expect(stored!.columnID, columns.firstWhere((c) => c.columnName == to).id,
          reason: 'the note did not move to the column it was dropped in');
    });

    testWidgets('07: a note can be deleted', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      final title = Fixtures.stamp('e2e note');
      await Fixtures.createNote(tester, title);
      // The card is found by its note id: once it is archived the title is not
      // something the board can be asked about at all.
      final id = (await Fixtures.noteNamed(title)).id;
      await Fixtures.deleteNote(tester, title);

      expect(Fixtures.noteCardById(id), findsNothing,
          reason: 'a deleted note is still on the board');
      expect(await Fixtures.storedNote(title), isNull,
          reason: 'a deleted note is still on the board it is read from');
    });

    testWidgets(
        '08: a staff account without the notes permission still sees its own '
        'notes', (tester) async {
      // Needs a second account with a restricted `notes` permission and its own
      // login — the accounts/permissions group (§2.7) is where a non-admin
      // session becomes available. The behaviour under test is the read clamp
      // in `NotesQueries.boardNotes` plus `notesArePersonal`, and the legacy
      // regression it guards against (the filtered getter mutating state and
      // rebuilding forever) cannot be reproduced without that session.
      expect(true, isTrue);
    }, skip: true);
  });
}
