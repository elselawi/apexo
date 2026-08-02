import 'package:apexo/core/model.dart';
import 'package:test/test.dart';

void main() {
  group("Model", () {
    group('Doc.fromJson', () {
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
        expect(doc.id.length, equals(15)); // UUID length as required by pocketbase
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
    });

    group('Doc.toJson', () {
      test('returns empty map for default Doc', () {
        final doc = Model.fromJson({});
        final json = doc.toJson();
        expect(json, contains("id"));
        expect(json, hasLength(1));
      });

      test('includes id when it is not a default UUID', () {
        final doc = Model.fromJson({'id': 'custom-id'});
        final json = doc.toJson();
        expect(json, containsPair('id', 'custom-id'));
      });

      test('includes archived when it is true', () {
        final doc = Model.fromJson({"archived": true});
        final json = doc.toJson();
        expect(json, containsPair('archived', true));
      });

      test('includes archived when it is false', () {
        final doc = Model.fromJson({"archived": false});
        final json = doc.toJson();
        expect(json, containsPair('archived', false));
      });

      test('excludes archived when it is null', () {
        final doc = Model.fromJson({});
        final json = doc.toJson();
        expect(json, isNot(contains('archived')));
      });

      test('returns correct json for Doc with custom id and archived true', () {
        final doc = Model.fromJson({'id': 'custom-id', 'archived': true});
        final json = doc.toJson();
        expect(json, equals({'id': 'custom-id', 'archived': true}));
      });
    });
  });
}
