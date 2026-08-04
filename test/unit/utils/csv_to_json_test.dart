import 'package:apexo/utils/csv_to_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('csvToJsonList', () {
    test('empty CSV returns empty list', () {
      expect(csvToJsonList(''), isEmpty);
    });

    test('header-only (1 row) returns empty list', () {
      expect(csvToJsonList('a,b,c'), isEmpty);
    });

    test('simple CSV with headers and one data row', () {
      final result = csvToJsonList('name,age\nJohn,30');
      expect(result, hasLength(1));
      expect(result[0]['name'], 'John');
      expect(result[0]['age'], '30');
    });

    test('multiple data rows', () {
      final result = csvToJsonList('name,age\nJohn,30\nJane,25\nBob,40');
      expect(result.length, 3);
      expect(result[0]['name'], 'John');
      expect(result[1]['name'], 'Jane');
      expect(result[2]['name'], 'Bob');
    });

    test('empty values become null', () {
      final result = csvToJsonList('name,age\nJohn,');
      expect(result[0]['name'], 'John');
      expect(result[0]['age'], isNull);
    });

    test('quoted fields with commas inside', () {
      final result = csvToJsonList('name,note\nJohn,"Hello, World"');
      expect(result[0]['note'], 'Hello, World');
    });

    test('escaped quotes inside quoted field', () {
      final result = csvToJsonList('name,note\nJohn,"She said ""hi"""');
      expect(result[0]['note'], 'She said "hi"');
    });

    test('multiline field inside quotes', () {
      final result = csvToJsonList('name,note\nJohn,"Line1\nLine2"');
      expect(result[0]['note'], 'Line1\nLine2');
    });

    test('Windows-style line endings (\\r\\n)', () {
      final result = csvToJsonList('name,age\r\nJohn,30\r\nJane,25');
      expect(result.length, 2);
      expect(result[0]['name'], 'John');
      expect(result[1]['name'], 'Jane');
    });

    test('trailing newline is handled', () {
      final result = csvToJsonList('name,age\nJohn,30\n');
      expect(result.length, 1);
      expect(result[0]['name'], 'John');
    });

    test('row with wrong column count is skipped', () {
      final result = csvToJsonList('name,age\nJohn,30\nExtraColumn');
      expect(result.length, 1);
      expect(result.first['name'], 'John');
    });

    test('malformed CSV returns empty list (try/catch)', () {
      // Test that the function handles edge cases without crashing
      // Passing a string-only construct; invalid CSV should return []
      final result = csvToJsonList('not,valid,csv\n');
      // This may or may not return data depending on structure
      expect(result, isEmpty);
    });

    test('dot-notation unflatten: nested object', () {
      final result = csvToJsonList('a/b,other\nval1,val2');
      expect(result, isNotEmpty);
      // a/b → nested object {a: {b: "val1"}}
      expect(result[0]['a'], isA<Map>());
    });

    test('a sole value column returns primitive rows', () {
      expect(csvToJsonList('value\nabc\n'), ['abc']);
      expect(csvToJsonList('value\n'), isEmpty);
      expect(csvToJsonList('value\n\n'), [isNull]);
    });

    test('unflattens nested and sparse lists', () {
      final result = csvToJsonList(
          'items/0/name,items/2/name,meta/version\nfirst,third,1');

      expect(result, [
        {
          'items': [
            {'name': 'first'},
            null,
            {'name': 'third'},
          ],
          'meta': {'version': '1'},
        }
      ]);
    });

    test('path conflicts are rejected as an all-or-nothing import', () {
      expect(csvToJsonList('a,a/b\nx,y'), isEmpty);
    });

    test('supports CR-only rows and quoted empty cells', () {
      expect(csvToJsonList('name,note\rJohn,""\r'), [
        {'name': 'John', 'note': null}
      ]);
    });

    test('keeps trailing empty header and data cells aligned', () {
      expect(csvToJsonList('name,note,\nJohn,text,'), [
        {'name': 'John', 'note': 'text', '': null}
      ]);
    });
  });
}
