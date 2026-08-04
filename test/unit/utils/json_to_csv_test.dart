import 'package:apexo/utils/json_to_csv.dart';
import 'package:apexo/utils/csv_to_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jsonListToCsv', () {
    test('empty list returns empty string', () {
      expect(jsonListToCsv([]), '');
    });

    test('single flat object produces CSV with header', () {
      final result = jsonListToCsv([
        {'name': 'John', 'age': 30}
      ]);
      expect(result, isNotEmpty);
      expect(result, contains('name'));
      expect(result, contains('age'));
      expect(result, contains('John'));
      expect(result, contains('30'));
    });

    test('multiple rows', () {
      final result = jsonListToCsv([
        {'name': 'John', 'age': 30},
        {'name': 'Jane', 'age': 25},
      ]);
      final lines = result.trim().split('\n');
      expect(lines.length, 3); // header + 2 rows
      expect(lines[0], contains('name'));
      expect(lines[1], contains('John'));
      expect(lines[2], contains('Jane'));
    });

    test('withHeader: false suppresses header row', () {
      final result = jsonListToCsv([
        {'name': 'John', 'age': 30}
      ], withHeader: false);
      final lines = result.trim().split('\n');
      expect(lines.length, 1);
      expect(lines[0], isNot(contains('name')));
    });

    test('includeColumns filters output columns', () {
      final result = jsonListToCsv([
        {'a': 1, 'b': 2, 'c': 3}
      ], includeColumns: [
        0,
        2
      ]);
      // Should only include columns at index 0 and 2
      expect(result, contains('a'));
      expect(result, contains('c'));
      expect(result, isNot(contains('b')));
    });

    test('includeColumns with out-of-range skips safely', () {
      final result = jsonListToCsv([
        {'a': 1}
      ], includeColumns: [
        0,
        99,
        -1
      ]);
      // Should work fine — 99 and -1 filtered out
      expect(result, isNotEmpty);
    });

    test('null values become empty cells', () {
      final result = jsonListToCsv([
        {'name': 'John', 'age': null}
      ]);
      expect(result, 'name,age\nJohn,\n');
    });

    test('values with commas are quoted', () {
      final result = jsonListToCsv([
        {'name': 'Doe, John'}
      ]);
      expect(result, contains('"'));
      expect(result, contains('Doe, John'));
    });

    test('values with double-quotes are escaped', () {
      final result = jsonListToCsv([
        {'name': 'She said "hi"'}
      ]);
      expect(result, contains('""'));
    });

    test('values with newlines are quoted', () {
      final result = jsonListToCsv([
        {'note': 'Line1\nLine2'}
      ]);
      expect(result, contains('"'));
    });

    test('objects with different keys merge all keys', () {
      final result = jsonListToCsv([
        {'a': 1},
        {'b': 2},
      ]);
      // Headers should include both 'a' and 'b'
      expect(result, contains('a'));
      expect(result, contains('b'));
    });

    test('preserves empty cells when rows have different schemas', () {
      expect(
        jsonListToCsv([
          {'name': 'John', 'age': 30},
          {'name': 'Jane'},
        ]),
        'name,age\nJohn,30\nJane,\n',
      );
    });

    test('flattens nested maps and list values in stable discovery order', () {
      final result = jsonListToCsv([
        {
          'person': {'name': 'John'},
          'tags': ['a', null],
        }
      ]);

      expect(result, 'person/name,tags/0,tags/1\nJohn,a,\n');
    });

    test('serializes primitive and null roots with the value column', () {
      expect(jsonListToCsv(['hello', null]), 'value\nhello\n\n');
    });

    test('returns empty output when no requested column is valid', () {
      expect(
          jsonListToCsv([
            {'a': 1}
          ], includeColumns: []),
          isEmpty);
      expect(
          jsonListToCsv([
            {'a': 1}
          ], includeColumns: [
            -1,
            9
          ]),
          isEmpty);
    });

    test('preserves requested column order and duplicate selections', () {
      final result = jsonListToCsv([
        {'a': 1, 'b': 2, 'c': 3}
      ], includeColumns: [
        2,
        0,
        2
      ]);

      expect(result, 'c,a,c\n3,1,3\n');
    });

    test('escapes carriage-return and CRLF values exactly', () {
      expect(
          jsonListToCsv([
            {'note': 'one\rtwo'},
            {'note': 'three\r\nfour'},
          ]),
          'note\n"one\rtwo"\n"three\r\nfour"\n');
    });

    test('round-trips nested data through the compatible CSV importer', () {
      final source = [
        {
          'person': {'name': 'Jane'},
          'items': ['one', 'two'],
        }
      ];

      expect(csvToJsonList(jsonListToCsv(source)), source);
    });
  });
}
