@Tags(['serial'])
library;

import 'package:apexo/core/observable.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Notes store', () {
    late List<int> originalPermissions;
    setUpAll(() {
      notes.init();
    });
    setUp(() {
      originalPermissions = login.savedPermissions;
      login.savedPermissions = Perm.full;
      notes.observableMap.clear();
      notes.filterByAccountId('');
      notes.showIncoming(false);
      notes.observableMap.setAll([]);
    });
    tearDown(() {
      login.savedPermissions = originalPermissions;
    });

    test('singleton is Notes instance', () {
      expect(notes, isA<Notes>());
    });

    test('observableMap is ObservableDict', () {
      expect(notes.observableMap, isA<ObservableDict<Note>>());
    });

    test('observableMap values returns list', () {
      expect(notes.observableMap.values, isA<List<Note>>());
    });

    test('present returns a map', () {
      expect(notes.present, isA<Map<String, Note>>());
    });

    test('columns returns a list', () {
      expect(notes.columns, isA<List<Note>>());
    });

    test('filtered returns a map', () {
      expect(notes.filtered, isA<Map<String, Note>>());
    });

    test('getChildInstances returns a list', () {
      expect(notes.getChildInstances('nonexistent'), isA<List<Note>>());
    });

    test('getChildInstances returns empty for unknown parent', () {
      expect(notes.getChildInstances('nonexistent'), isEmpty);
    });

    test('columns are sorted by order and exclude archived columns', () {
      notes.setAll([
        testNote(id: 'column-2', isColumn: true, order: 2),
        testNote(id: 'column-1', isColumn: true, order: 1),
        testNote(
            id: 'archived-column', isColumn: true, order: 0, archived: true),
      ]);

      expect(notes.columns.map((x) => x.id), ['column-1', 'column-2']);
    });

    test('parent and sibling indexes return date-ordered children', () async {
      notes.setAll([
        testNote(
            id: 'child-late', parentID: 'parent', date: DateTime(2026, 1, 3)),
        testNote(
            id: 'child-early', parentID: 'parent', date: DateTime(2026, 1, 1)),
        testNote(
            id: 'child-middle', parentID: 'parent', date: DateTime(2026, 1, 2)),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(notes.getChildInstances('parent').map((x) => x.id),
          ['child-early', 'child-middle', 'child-late']);
      expect(
          notes.getSiblingInstances('parent', 'child-middle').map((x) => x.id),
          ['child-early', 'child-late']);
    });

    test('filtered supports account and incoming filters', () {
      notes.setAll([
        testNote(id: 'created', createdBy: 'account'),
        testNote(id: 'assigned', assignedTo: 'account'),
        testNote(id: 'unrelated', createdBy: 'other', assignedTo: 'another'),
      ]);

      notes.filterByAccountId('account');
      expect(notes.filtered.keys, {'created', 'assigned'});

      notes.filterByAccountId('');
      notes.showIncoming(true);
      login.email = '';
      notes.set(testNote(id: 'incoming', assignedTo: ''));
      expect(notes.filtered.keys, contains('incoming'));
    });

    test('index rebuilds when a child is inserted after first lookup',
        () async {
      expect(notes.getChildInstances('parent'), isEmpty);
      notes.set(testNote(id: 'new-child', parentID: 'parent'));
      await Future<void>.delayed(Duration.zero);

      expect(notes.getChildInstances('parent').map((x) => x.id), ['new-child']);
    });
  });
}
