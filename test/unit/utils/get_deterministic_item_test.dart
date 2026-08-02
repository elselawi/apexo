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

    test('returns different items for different inputs', () {
      final items = ['apple', 'banana', 'cherry'];
      const input1 = 'test1';
      const input2 = 'test2';

      final result1 = getDeterministicItem(items, input1);
      final result2 = getDeterministicItem(items, input2);

      expect(result1, isNot(equals(result2)));
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
  });
}
