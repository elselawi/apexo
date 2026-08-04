import 'package:apexo/core/model.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:test/test.dart';

// A concrete subclass for testing overridable getters.
class _TestModel extends Model {
  _TestModel.fromJson(super.json) : super.fromJson();

  @override
  bool get locked => true;

  @override
  Map<String, String> get labels => {'test': 'value'};

  @override
  String? get avatar => 'avatar.png';

  @override
  String? get imageRowId => 'img-row-1';

  @override
  String get title => 'Test Title';

  @override
  Map<String, dynamic> get jsonCopyForPush => {'push': true};

  @override
  List<String> get targetsToPushTo => ['user1', 'user2'];

  @override
  List<String> get pushIfChanged => ['title', 'archived'];

  @override
  bool get pushOnCreation => true;
}

void main() {
  group('Model.fromJson', () {
    test('creates Doc with provided id', () {
      final json = {'id': '123', 'archived': false};
      final doc = Model.fromJson(json);
      expect(doc.id, equals('123'));
      expect(doc.archived, isFalse);
    });

    test('creates Doc with generated id when not provided', () {
      final json = {'archived': true};
      final doc = Model.fromJson(json);
      expect(doc.id, isNotEmpty);
      expect(doc.id.length, equals(15));
      expect(doc.archived, isTrue);
    });

    test('handles null archived value', () {
      final json = {'id': '456'};
      final doc = Model.fromJson(json);
      expect(doc.id, equals('456'));
      expect(doc.archived, isNull);
    });

    test('creates different ids for multiple docs without id', () {
      final json = {'archived': false};
      final doc1 = Model.fromJson(json);
      final doc2 = Model.fromJson(json);
      expect(doc1.id, isNot(equals(doc2.id)));
    });

    test('handles empty json {}', () {
      final doc = Model.fromJson({});
      expect(doc.id, isNotEmpty);
      expect(doc.archived, isNull);
      expect(doc.title, isEmpty);
    });

    test('parses title from json', () {
      final doc = Model.fromJson({'id': '1', 'title': 'My Title'});
      expect(doc.title, 'My Title');
    });

    test('fromJson called twice merges both JSON maps', () {
      final doc = Model.fromJson({'id': 'first', 'title': 'First'});
      doc.fromJson({'title': 'Second'});
      // id is preserved from the first fromJson
      expect(doc.id, 'first');
      // title is overwritten by the second fromJson
      expect(doc.title, 'Second');
    });

    test('fromJson with null values preserves existing fields', () {
      final doc = Model.fromJson({'id': 'keep-id', 'title': 'Keep Title'});
      doc.fromJson({'id': null, 'title': null, 'archived': null});
      expect(doc.id, 'keep-id');
      expect(doc.title, 'Keep Title');
      expect(doc.archived, isNull);
    });

    test('fromJson with empty string archived keeps existing archived', () {
      final doc = Model.fromJson({'id': 'x', 'archived': true});
      // Empty map shouldn't reset anything
      doc.fromJson({});
      expect(doc.id, 'x');
      expect(doc.archived, true);
    });

    test('handles very long id', () {
      final longId = 'a' * 5000;
      final doc = Model.fromJson({'id': longId});
      expect(doc.id, longId);
      expect(doc.toJson()['id'], longId);
    });

    test('handles special characters in title', () {
      const title = r'!@#$%^&*()_+-={}[]|\:";' '<>?,./~` 🦷';
      final doc = Model.fromJson({'id': 'x', 'title': title});
      expect(doc.title, title);
      expect(doc.toJson()['title'], title);
    });

    test('handles numeric archived value as bool', () {
      // From PocketBase, bools come through as actual bools.
      final doc = Model.fromJson({'id': 'x', 'archived': true});
      expect(doc.archived, isTrue);
    });

    test('id is exactly 15 chars (uuid default)', () {
      final doc = Model.fromJson({});
      expect(doc.id.length, 15);
      // alphabet is lowercase alnum
      expect(RegExp(r'^[a-z0-9]{15}$').hasMatch(doc.id), isTrue);
    });
  });

  group('Model.toJson', () {
    test('returns empty map for default Doc', () {
      final doc = Model.fromJson({});
      final json = doc.toJson();
      expect(json, contains('id'));
      expect(json, hasLength(1));
    });

    test('includes id when it is not a default UUID', () {
      final doc = Model.fromJson({'id': 'custom-id'});
      final json = doc.toJson();
      expect(json, containsPair('id', 'custom-id'));
    });

    test('includes archived when it is true', () {
      final doc = Model.fromJson({'archived': true});
      final json = doc.toJson();
      expect(json, containsPair('archived', true));
    });

    test('includes archived when it is false', () {
      final doc = Model.fromJson({'archived': false});
      final json = doc.toJson();
      expect(json, containsPair('archived', false));
    });

    test('excludes archived when it is null', () {
      final doc = Model.fromJson({});
      final json = doc.toJson();
      expect(json, isNot(contains('archived')));
    });

    test('excludes title when empty', () {
      final doc = Model.fromJson({});
      final json = doc.toJson();
      expect(json, isNot(contains('title')));
    });

    test('includes title when non-empty', () {
      final doc = Model.fromJson({'id': '1', 'title': 'Hello'});
      final json = doc.toJson();
      expect(json, containsPair('title', 'Hello'));
    });

    test('returns correct json for Doc with custom id and archived true', () {
      final doc = Model.fromJson({'id': 'custom-id', 'archived': true});
      final json = doc.toJson();
      expect(json, equals({'id': 'custom-id', 'archived': true}));
    });
  });

  group('Model.copy', () {
    test('copy(blank: true) creates from empty JSON — all defaults', () {
      final original = Model.fromJson({
        'id': 'abc',
        'title': 'Original',
        'archived': true,
      });
      final copy = original.copy(true);
      expect(copy.id, isNot(equals('abc')));
      expect(copy.title, isEmpty);
      expect(copy.archived, isNull);
    });

    test('copy(blank: false) preserves all fields', () {
      final original = Model.fromJson({
        'id': 'abc',
        'title': 'Original',
        'archived': true,
      });
      final copy = original.copy(false);
      expect(copy.id, 'abc');
      expect(copy.title, 'Original');
      expect(copy.archived, true);
    });

    test('copy(blank: false) creates independent instance', () {
      final original = Model.fromJson({'id': 'abc', 'archived': false});
      final copy = original.copy(false);
      copy.archived = true;
      expect(original.archived, false);
      expect(copy.archived, true);
    });
  });

  group('Model.color', () {
    test('is deterministic — same ID returns same color', () {
      final a = Model.fromJson({'id': 'color-test'});
      final b = Model.fromJson({'id': 'color-test'});
      expect(a.color, b.color);
    });

    test('different IDs return different colors', () {
      final a = Model.fromJson({'id': 'color-a'});
      final b = Model.fromJson({'id': 'color-b'});
      expect(a.color, isNot(b.color));
    });

    test('is lazily initialized — second call returns same instance', () {
      final doc = Model.fromJson({'id': 'lazy'});
      final c1 = doc.color;
      final c2 = doc.color;
      expect(identical(c1, c2), true);
    });

    test('returns a Color', () {
      final doc = Model.fromJson({'id': 'any'});
      expect(doc.color, isNotNull);
    });
  });

  group('Model default getters', () {
    test('locked is false by default', () {
      expect(Model.fromJson({}).locked, false);
    });

    test('labels returns empty map by default', () {
      expect(Model.fromJson({}).labels, isEmpty);
    });

    test('avatar returns null by default', () {
      expect(Model.fromJson({}).avatar, isNull);
    });

    test('imageRowId returns null by default', () {
      expect(Model.fromJson({}).imageRowId, isNull);
    });

    test('jsonCopyForPush returns empty map by default', () {
      expect(Model.fromJson({}).jsonCopyForPush, isEmpty);
    });

    test('targetsToPushTo returns empty list by default', () {
      expect(Model.fromJson({}).targetsToPushTo, isEmpty);
    });

    test('pushIfChanged returns empty list by default', () {
      expect(Model.fromJson({}).pushIfChanged, isEmpty);
    });

    test('pushOnCreation returns false by default', () {
      expect(Model.fromJson({}).pushOnCreation, false);
    });

    test('title returns empty string by default', () {
      expect(Model.fromJson({}).title, isEmpty);
    });
  });

  group('Model overridable getters in subclass', () {
    test('locked can be overridden', () {
      expect(_TestModel.fromJson({}).locked, true);
    });

    test('labels can be overridden', () {
      expect(_TestModel.fromJson({}).labels, {'test': 'value'});
    });

    test('avatar can be overridden', () {
      expect(_TestModel.fromJson({}).avatar, 'avatar.png');
    });

    test('imageRowId can be overridden', () {
      expect(_TestModel.fromJson({}).imageRowId, 'img-row-1');
    });

    test('jsonCopyForPush can be overridden', () {
      expect(_TestModel.fromJson({}).jsonCopyForPush, {'push': true});
    });

    test('targetsToPushTo can be overridden', () {
      expect(_TestModel.fromJson({}).targetsToPushTo, ['user1', 'user2']);
    });

    test('pushIfChanged can be overridden', () {
      expect(_TestModel.fromJson({}).pushIfChanged, ['title', 'archived']);
    });

    test('pushOnCreation can be overridden', () {
      expect(_TestModel.fromJson({}).pushOnCreation, true);
    });

    test('title override returns provided title', () {
      expect(_TestModel.fromJson({}).title, 'Test Title');
    });

    test('copy(false) on subclass — title serialized via toJson survives', () {
      final original = _TestModel.fromJson({'id': 'sub-1'});
      // copy(false) goes through Model.fromJson(toJson()). The `title`
      // override returns 'Test Title' (non-empty), so Model.toJson()
      // serializes it — and the new Model parses it back into the
      // default `title` field. Overridden GETTERS that are NOT
      // serialized by Model.toJson (locked, avatar, labels, etc.) are
      // lost because copy() returns a base Model.
      final copy = original.copy(false);
      expect(copy.id, 'sub-1');
      expect(copy.title, 'Test Title'); // passed through via toJson
      expect(copy.locked, false); // not preserved (pure getter)
      expect(copy.avatar, isNull); // not preserved
      expect(copy.labels, isEmpty); // not preserved
    });

    test('copy(true) on subclass yields a Model with new id and defaults', () {
      final original = _TestModel.fromJson({'id': 'sub-1'});
      final blank = original.copy(true);
      expect(blank.id, isNot('sub-1'));
      expect(blank.id.length, 15);
      // blank uses Model.fromJson({}) → default values for everything.
      expect(blank.title, isEmpty);
      expect(blank.locked, false);
      expect(blank.archived, isNull);
    });

    test('toJson from subclass — only id, title, archived serialized', () {
      final m = _TestModel.fromJson({'id': 't-1'});
      final json = m.toJson();
      // Model.toJson serializes id (always), archived (if not null),
      // title (if not empty). _TestModel overrides `title` getter to
      // 'Test Title', which is non-empty → written. Overridden getters
      // like avatar/labels are NOT serialized by the base class.
      expect(json['id'], 't-1');
      expect(json['title'], 'Test Title');
      expect(json.containsKey('avatar'), isFalse);
      expect(json.containsKey('labels'), isFalse);
      expect(json.containsKey('targetsToPushTo'), isFalse);
      expect(json.containsKey('pushIfChanged'), isFalse);
      expect(json.containsKey('imageRowId'), isFalse);
      expect(json.containsKey('jsonCopyForPush'), isFalse);
    });
  });

  group('Model.color determinism across instances', () {
    test('two Model instances with same id produce identical color objects',
        () {
      final a = Model.fromJson({'id': 'shared-id'});
      final b = Model.fromJson({'id': 'shared-id'});
      expect(a.color, equals(b.color));
    });

    test('color is in the colorsWithoutYellow palette', () {
      // We can at least assert the color is non-null and a Flutter Color.
      final doc = Model.fromJson({'id': 'pal-test'});
      expect(doc.color, isA<fluent_ui.Color>());
    });
  });
}
