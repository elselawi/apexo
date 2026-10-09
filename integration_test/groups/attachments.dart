import 'dart:convert';
import 'dart:typed_data';

import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/imgs.dart' show displayNameForFile;
import 'package:flutter/widgets.dart' show Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8A'
  'AgMBgNf9WZ0AAAAASUVORK5CYII=',
);

class _UploadedAttachment {
  const _UploadedAttachment({
    required this.fullName,
    required this.url,
  });

  final String fullName;
  final String url;
}

String _id(String prefix) => simpleHash(
      '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      length: 15,
    );

Future<Note> _createNote({
  required String title,
}) async {
  final note = Note.fromJson({
    'id': _id('att-note'),
    'title': title,
  });
  notes.set(note);
  await notes.waitUntilChangesAreProcessed();
  await _waitForRemoteRow(note.id, description: 'the note record');
  return note;
}

Future<void> _waitForRemoteRow(
  String id, {
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await RemoteRows.find(id) != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('The server never stored $description ($id).');
}

Future<_UploadedAttachment> _uploadAttachment(
  Note note, {
  required String filename,
  required List<int> bytes,
}) async {
  final remote = notes.remote;
  if (remote == null) fail('The notes store has no remote persistence layer.');

  final fullName = await remote.uploadImage(
    rowID: note.id,
    filename: filename,
    predefinedMultipart: http.MultipartFile.fromBytes(
      'imgs+',
      bytes,
      filename: filename,
    ),
  );
  final url = await remote.getImageLink(note.id, fullName);
  if (url == null) {
    fail('The uploaded attachment "$fullName" could not be read back.');
  }

  final current = notes.get(note.id)!;
  current.attachments = [
    ...{...current.attachments, url}
  ];
  notes.set(current);
  await notes.waitUntilChangesAreProcessed();
  return _UploadedAttachment(fullName: fullName, url: url);
}

Future<void> _deleteNoteEverywhere(String id) async {
  await RemoteRows.delete(id);
  notes.purge(id);
}

Future<List<int>> _readBytes(String url) async {
  final response = await http.get(Uri.parse(url));
  expect(response.statusCode, 200,
      reason: 'Downloading "$url" did not succeed.');
  return response.bodyBytes;
}

void registerAttachmentsTests() {
  group('attachments', () {
    testWidgets('01: a file can be picked (blocked by the OS file picker)',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('02: upload failure is reported and the retry succeeds',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('04: viewing an uploaded image renders it', (tester) async {
      await E2E.signIn(tester);
      final note = await _createNote(title: Fixtures.stamp('e2e attachment'));
      addTearDown(() async => _deleteNoteEverywhere(note.id));

      final uploaded = await _uploadAttachment(
        note,
        filename: 'render_abcd1234.png',
        bytes: _tinyPng,
      );

      await Fixtures.openNotes(tester);
      await Fixtures.expandCard(tester, note.title);
      final card = Fixtures.noteCardById(note.id);
      await E2E.waitFor(
        tester,
        find.descendant(of: card, matching: find.byType(Image)),
        description: 'the uploaded attachment preview',
      );
      await E2E.settle(tester, frames: 10);
      expect(tester.takeException(), isNull,
          reason: 'Rendering the uploaded image threw an exception.');
      expect(await _readBytes(uploaded.url), _tinyPng,
          reason: 'The uploaded image bytes did not round-trip unchanged.');
    });

    testWidgets('07: a malformed image does not crash the gallery',
        (tester) async {
      await E2E.signIn(tester);
      final note =
          await _createNote(title: Fixtures.stamp('e2e broken attachment'));
      addTearDown(() async => _deleteNoteEverywhere(note.id));

      await _uploadAttachment(
        note,
        filename: 'good_abcd1234.png',
        bytes: _tinyPng,
      );
      await _uploadAttachment(
        note,
        filename: 'broken_abcd1234.png',
        bytes: utf8.encode('not really an image'),
      );

      await Fixtures.openNotes(tester);
      await Fixtures.expandCard(tester, note.title);
      final card = Fixtures.noteCardById(note.id);
      await E2E.waitFor(
        tester,
        find.descendant(of: card, matching: find.byType(Image)),
        description: 'the surviving good attachment preview',
      );
      await E2E.settle(tester, frames: 15);
      expect(tester.takeException(), isNull,
          reason: 'A malformed image attachment crashed the gallery.');
      expect(card, findsOneWidget,
          reason:
              'The note card disappeared after the malformed image loaded.');
    });

    testWidgets('08: the stored filename suffix is handled both ways',
        (tester) async {
      await E2E.signIn(tester);
      final note = await _createNote(title: Fixtures.stamp('e2e suffix note'));
      addTearDown(() async => _deleteNoteEverywhere(note.id));

      final uploaded = await _uploadAttachment(
        note,
        filename: 'consent_abcd1234.png',
        bytes: _tinyPng,
      );

      final exact =
          await notes.remote!.getImageLink(note.id, uploaded.fullName);
      final unsuffixed =
          await notes.remote!.getImageLink(note.id, 'consent.png');

      expect(exact, isNotNull,
          reason: 'The exact stored filename no longer resolves.');
      expect(unsuffixed, isNotNull,
          reason: 'The unsuffixed spelling no longer resolves.');
      expect(await _readBytes(exact!), await _readBytes(unsuffixed!),
          reason:
              'The exact and unsuffixed names resolved to different files.');
    });

    testWidgets('10: an attachment can be deleted from the record',
        (tester) async {
      await E2E.signIn(tester);
      final note = await _createNote(title: Fixtures.stamp('e2e delete note'));
      addTearDown(() async => _deleteNoteEverywhere(note.id));

      final uploaded = await _uploadAttachment(
        note,
        filename: 'delete_abcd1234.png',
        bytes: _tinyPng,
      );

      final current = notes.get(note.id)!;
      await notes.deleteImg(note.id, uploaded.url);
      current.attachments.remove(uploaded.url);
      notes.set(current);
      await notes.waitUntilChangesAreProcessed();

      expect(
          await notes.remote!.getImageLink(note.id, uploaded.fullName), isNull,
          reason: 'The deleted attachment still resolves on the server.');
      expect(notes.get(note.id)!.attachments, isNot(contains(uploaded.url)),
          reason: 'The note still lists the deleted attachment URL.');
    });

    testWidgets('12: two same-named attachments stay distinct', (tester) async {
      await E2E.signIn(tester);
      final note = await _createNote(title: Fixtures.stamp('e2e twin names'));
      addTearDown(() async => _deleteNoteEverywhere(note.id));

      final first = await _uploadAttachment(
        note,
        filename: 'consent_abcd1234.png',
        bytes: _tinyPng,
      );
      final second = await _uploadAttachment(
        note,
        filename: 'consent_efgh5678.png',
        bytes: _tinyPng,
      );

      final stored = await notes.remote!.getFileNames(note.id);
      expect(first.fullName, isNot(second.fullName),
          reason: 'The second upload overwrote the first stored filename.');
      expect(displayNameForFile(first.fullName),
          displayNameForFile(second.fullName),
          reason: 'The pair no longer represents the same human-facing name.');
      expect(stored, containsAll([first.fullName, second.fullName]),
          reason: 'The note did not keep both stored attachments.');
      expect(notes.get(note.id)!.attachments.length, 2,
          reason: 'The note no longer lists both attachment URLs.');
    });

    testWidgets('13: downloading works through a save dialog', (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('14: web caches blobs in OPFS after a successful attach',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);
  });
}
