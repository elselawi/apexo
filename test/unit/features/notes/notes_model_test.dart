import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Note.fromJson', () {
    test('parses basic note', () {
      final n = Note.fromJson({
        'id': 'n1',
        'note': 'Order supplies',
        'createdBy': 'user1',
        'assignedTo': 'user2',
        'columnID': 'col1',
      });
      expect(n.id, 'n1');
      expect(n.note, 'Order supplies');
      expect(n.createdBy, 'user1');
      expect(n.assignedTo, 'user2');
      expect(n.columnID, 'col1');
    });

    test('parses column note', () {
      final n = Note.fromJson({
        'id': 'col1',
        'isColumn': true,
        'columnName': 'To Do',
        'order': 0.0,
      });
      expect(n.isColumn, true);
      expect(n.columnName, 'To Do');
      expect(n.order, 0.0);
    });

    test('parses recurring note', () {
      final n = Note.fromJson({
        'id': 'rec1',
        'recurringInterval': 7,
        'parentID': 'parent1',
      });
      expect(n.recurringInterval, 7);
      expect(n.parentID, 'parent1');
    });

    test('parses comments as nested list', () {
      final n = Note.fromJson({
        'id': 'n1',
        'comments': [
          ['user1', 'First comment'],
          ['user2', 'Second comment'],
        ],
      });
      expect(n.comments.length, 2);
      expect(n.comments[0][0], 'user1');
      expect(n.comments[0][1], 'First comment');
    });

    test('parses date in hours format', () {
      final n = Note.fromJson({
        'date': 4722, // hours since epoch
      });
      expect(n.date, isA<DateTime>());
    });

    test('handles missing fields with defaults', () {
      final n = Note.fromJson({});
      expect(n.isColumn, false);
      expect(n.note, '');
      expect(n.done, false);
      expect(n.comments, isEmpty);
      expect(n.attachments, isEmpty);
      expect(n.createdBy, '');
      expect(n.assignedTo, '');
      expect(n.forPatient, '');
      expect(n.recurringInterval, isNull);
      expect(n.parentID, isNull);
    });

    test('malformed order values throw a format exception', () {
      expect(
        () => Note.fromJson({'order': 'not-a-number'}),
        throwsFormatException,
      );
    });

    test('malformed comments do not silently create valid comments', () {
      expect(
        () => Note.fromJson({
          'comments': [
            ['only-one-value']
          ]
        }),
        throwsA(anything),
      );
    });
  });

  group('Note.toJson', () {
    test('round-trip preserves basic fields', () {
      final original = Note.fromJson({
        'id': 'n1',
        'note': 'Test',
        'done': false,
        'columnID': 'col1',
      });
      final restored = Note.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.note, original.note);
      expect(restored.done, original.done);
    });

    test('default collections are omitted while dates remain serialized', () {
      final json = Note.fromJson({'id': 'defaults'}).toJson();

      expect(json.containsKey('comments'), isFalse);
      expect(json.containsKey('attachments'), isFalse);
      expect(json['date'], isA<int>());
      expect(json['dueDate'], isA<int>());
    });

    test('copy deep-copies comments and attachments', () {
      final original = Note.fromJson({
        'id': 'deep-copy',
        'comments': [
          ['user', 'comment'],
        ],
        'attachments': ['file.pdf'],
      });
      final clone = original.copy(false);
      clone.comments.first[1] = 'changed';
      clone.attachments.add('second.pdf');

      expect(original.comments, [
        ['user', 'comment'],
      ]);
      expect(original.attachments, ['file.pdf']);
    });
  });

  group('Note computed getters', () {
    test('isNote is !isColumn', () {
      expect(Note.fromJson({}).isNote, true);
      expect(Note.fromJson({'isColumn': true}).isNote, false);
    });

    test('commentsCount returns comments length', () {
      final n = Note.fromJson({
        'comments': [
          ['u1', 'c1'],
          ['u2', 'c2'],
        ],
      });
      expect(n.commentsCount, 2);
    });

    test('hasComments / hasAttachments', () {
      final empty = Note.fromJson({});
      expect(empty.hasComments, false);
      expect(empty.hasAttachments, false);

      final withComments = Note.fromJson({
        'comments': [
          ['u', 'c']
        ],
      });
      expect(withComments.hasComments, true);
    });

    test('isRecurring true when interval set', () {
      expect(Note.fromJson({'recurringInterval': 7}).isRecurring, true);
      expect(Note.fromJson({}).isRecurring, false);
    });

    test('isRecurringInstance true when parentID set', () {
      expect(Note.fromJson({'parentID': 'p1'}).isRecurringInstance, true);
      expect(Note.fromJson({}).isRecurringInstance, false);
    });

    test('unCategorized when note has no column', () {
      expect(Note.fromJson({}).unCategorized, true);
      expect(Note.fromJson({'columnID': 'col1'}).unCategorized, false);
      // Columns themselves are not uncategorized
      expect(Note.fromJson({'isColumn': true}).unCategorized, false);
    });

    test('unAssigned when no assignee', () {
      expect(Note.fromJson({}).unAssigned, true);
      expect(Note.fromJson({'assignedTo': 'user1'}).unAssigned, false);
      expect(Note.fromJson({'isColumn': true}).unAssigned, false);
    });

    test('overdue when past due and not done', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final n = Note.fromJson({
        'dueDate': past.millisecondsSinceEpoch ~/ (60 * 60 * 1000),
        'done': false,
      });
      expect(n.overdue, true);
    });

    test('pending when not done and not overdue', () {
      final future = DateTime.now().add(const Duration(days: 7));
      final n = Note.fromJson({
        'dueDate': future.millisecondsSinceEpoch ~/ (60 * 60 * 1000),
        'done': false,
      });
      expect(n.pending, true);
      expect(n.overdue, false);
    });

    test('completed when done', () {
      final n = Note.fromJson({'done': true});
      expect(n.completed, true);
      expect(n.pending, false);
    });

    test('locked depends on permissions', () {
      final original = login.savedPermissions;
      try {
        login.savedPermissions = Perm.zeroes;
        expect(
          Note.fromJson({
            'createdBy': 'other',
            'assignedTo': 'another',
          }).locked,
          isTrue,
        );

        final some = Perm.zeroes;
        some[Perm.notes] = 1;
        login.savedPermissions = some;
        expect(
          Note.fromJson({
            'createdBy': 'other',
            'assignedTo': 'another',
          }).locked,
          isFalse,
        );
      } finally {
        login.savedPermissions = original;
      }
    });

    test('createChild produces linked instance', () {
      final parent = Note.fromJson({
        'id': 'parent1',
        'recurringInterval': 7,
        'date': DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ (60 * 60 * 1000),
      });
      final child = parent.createChild();
      expect(child.parentID, 'parent1');
      expect(child.id, isNotEmpty);
      expect(child.id.length, 15);
      expect(child.recurringInterval, isNull);
      expect(child.note, parent.note);
      expect(child.columnID, parent.columnID);
    });
  });
}
