import 'package:test/test.dart';
import 'package:apexo/utils/uuid.dart';

void main() {
  group('uuid', () {
    test('generates a string of length 15', () {
      final id = uuid();
      expect(id.length, equals(15));
    });

    test('generates a string containing only valid characters', () {
      final id = uuid();
      const validCharacters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      for (var char in id.split('')) {
        expect(validCharacters.contains(char), isTrue);
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
  });
}
