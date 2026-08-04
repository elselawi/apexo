import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/constants.dart';
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

    test('uses the documented prefix and alphabet', () {
      final hash = simpleHash('alphabet check');

      expect(hash, startsWith('h'));
      expect(hash.split('').every(alphabet.contains), isTrue);
    });

    test('supports Unicode deterministically', () {
      expect(simpleHash('مرحبا 🌍'), simpleHash('مرحبا 🌍'));
    });

    test('honours custom lengths of two or more', () {
      expect(simpleHash('test', length: 2).length, 2);
      expect(simpleHash('test', length: 64).length, 64);
    });

    test('documents the minimum output length for zero and negative lengths',
        () {
      expect(simpleHash('test', length: 0), 'ha');
      expect(simpleHash('test', length: -1), 'ha');
    });
  });

  group('secureHash', () {
    test('is deterministic, exact-length, and uses its documented alphabet',
        () {
      final hash = secureHash('secure 🌍', length: 128);

      expect(hash, secureHash('secure 🌍', length: 128));
      expect(hash.length, 128);
      expect(hash.split('').every(RegExp(r'^[a-zA-Z0-9]$').hasMatch), isTrue);
    });

    test('supports empty input and distinguishes representative inputs', () {
      expect(secureHash('').length, 100);
      expect(secureHash('first', length: 32),
          isNot(secureHash('second', length: 32)));
    });

    test('returns an empty hash when zero length is requested', () {
      expect(secureHash('test', length: 0), isEmpty);
    });

    test('different requested lengths produce independent prefixes', () {
      final shortHash = secureHash('same input', length: 16);
      final longHash = secureHash('same input', length: 64);

      expect(longHash.substring(0, shortHash.length), shortHash);
      expect(longHash.length, 64);
    });
  });
}
