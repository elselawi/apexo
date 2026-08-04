import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/uuid.dart';

void main() {
  group('uuid', () {
    test('generates a string of length 15', () {
      final id = uuid();
      expect(id.length, equals(15));
    });

    test('generates a string containing only valid characters', () {
      final id = uuid();
      for (var char in id.split('')) {
        expect(alphabet.contains(char), isTrue);
      }
    });

    test('generates different UUIDs on consecutive calls', () {
      final id1 = uuid();
      final id2 = uuid();
      expect(id1, isNot(equals(id2)));
    });

    test('generates a non-empty string', () {
      final id = uuid();
      expect(id.isNotEmpty, isTrue);
    });

    test('creates a unique moderate batch under normal randomness', () {
      final ids = List.generate(250, (_) => uuid()).toSet();

      expect(ids.length, 250);
    });

    test('does not generate an all-zero or all-identical batch', () {
      final ids = List.generate(32, (_) => uuid());

      expect(ids.every((id) => id == ids.first), isFalse);
      expect(ids.every((id) => id.split('').every((c) => c == '0')), isFalse);
    });
  });
}
