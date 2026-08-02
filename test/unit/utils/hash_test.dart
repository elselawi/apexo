import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/hash.dart';

void main() {
  group('simpleHash', () {
    test('returns a fixed-length hash', () {
      String input = 'test';
      String hash = simpleHash(input);
      expect(hash.length, 17); // "h" + 16 characters
    });

    test('returns different hashes for different inputs', () {
      String input1 = 'test1';
      String input2 = 'test2';
      String hash1 = simpleHash(input1);
      String hash2 = simpleHash(input2);
      expect(hash1, isNot(equals(hash2)));
    });

    test('returns the same hash for the same input', () {
      String input = 'test';
      String hash1 = simpleHash(input);
      String hash2 = simpleHash(input);
      expect(hash1, equals(hash2));
    });

    test('handles empty input', () {
      String input = '';
      String hash = simpleHash(input);
      expect(hash.length, 17); // "h" + 16 characters
    });

    test('handles long input', () {
      String input = 'a' * 1000;
      String hash = simpleHash(input);
      expect(hash.length, 17); // "h" + 16 characters
    });
  });
}
