import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/get_deterministic_item.dart';

void main() {
  group('getDeterministicItem', () {
    test('returns the same item for the same input', () {
      final items = ['apple', 'banana', 'cherry'];
      const input = 'test';

      final result1 = getDeterministicItem(items, input);
      final result2 = getDeterministicItem(items, input);

      expect(result1, equals(result2));
    });

    test('documents collisions for equal byte-sum inputs', () {
      final items = ['apple', 'banana', 'cherry'];
      const input1 = 'ab';
      const input2 = 'ba';

      final result1 = getDeterministicItem(items, input1);
      final result2 = getDeterministicItem(items, input2);

      expect(result1, equals(result2));
    });

    test('returns an item within the list', () {
      final items = ['apple', 'banana', 'cherry'];
      const input = 'test';

      final result = getDeterministicItem(items, input);

      expect(items.contains(result), isTrue);
    });

    test('handles empty input string', () {
      final items = ['apple', 'banana', 'cherry'];
      const input = '';

      final result = getDeterministicItem(items, input);

      expect(items.contains(result), isTrue);
    });

    test('handles single item list', () {
      final items = ['apple'];
      const input = 'test';

      final result = getDeterministicItem(items, input);

      expect(result, equals('apple'));
    });

    test('preserves generic object identity and accepts duplicate values', () {
      final first = Object();
      final second = Object();
      final items = [first, second, first];

      expect(identical(getDeterministicItem(items, 'a'), second), isTrue);
      expect(getDeterministicItem(['same', 'same'], 'anything'), 'same');
    });

    test('supports Unicode and very long inputs deterministically', () {
      const items = ['a', 'b', 'c', 'd'];
      final input = '🌍مرحبا' * 1000;

      expect(getDeterministicItem(items, input),
          getDeterministicItem(items, input));
    });

    test('throws when no items are available', () {
      expect(() => getDeterministicItem<String>([], 'seed'), throwsA(anything));
    });
  });
}
