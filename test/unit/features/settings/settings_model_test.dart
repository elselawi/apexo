import 'package:apexo/features/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Setting.fromJson', () {
    test('parses setting with value', () {
      final s = Setting.fromJson({'id': 'currency_______', 'value': '\$'});
      expect(s.id, 'currency_______');
      expect(s.value, '\$');
    });

    test('parses setting with empty value', () {
      final s = Setting.fromJson({'id': 'key1', 'value': ''});
      expect(s.value, isEmpty);
    });

    test('missing value defaults to empty string', () {
      final s = Setting.fromJson({'id': 'key1'});
      expect(s.value, isEmpty);
    });

    test('empty JSON gives defaults', () {
      final s = Setting.fromJson({});
      expect(s.id, isNotEmpty);
      expect(s.value, isEmpty);
    });

    test('null value preserves the empty-string default', () {
      final s = Setting.fromJson({'id': 'null-value', 'value': null});
      expect(s.value, isEmpty);
    });

    test('numeric value is rejected by the String model contract', () {
      expect(
        () => Setting.fromJson({'id': 'numeric', 'value': 42}),
        throwsA(anything),
      );
    });
  });

  group('Setting.toJson', () {
    test('round-trip preserves id and value', () {
      final s = testSetting(id: 'key1', value: 'test_value');
      final json = s.toJson();
      expect(json['id'], 'key1');
      expect(json['value'], 'test_value');
    });

    test('toJson includes id and value exactly', () {
      expect(Setting.fromJson({'id': 'exact', 'value': 'v'}).toJson(), {
        'id': 'exact',
        'value': 'v',
      });
    });
  });

  group('Setting.copy', () {
    test('copy preserves all fields', () {
      final orig = testSetting(id: 'cpy1', value: 'original');
      final clone = orig.copy(false);
      expect(clone.id, 'cpy1');
      expect(clone.value, 'original');
    });

    test('copy(blank: true) creates fresh instance', () {
      final orig = testSetting(id: 'cpy2', value: 'orig');
      final clone = orig.copy(true);
      expect(clone.id, isNot('cpy2'));
      expect(clone.value, isEmpty);
    });

    test('copy(false) is independent from the source', () {
      final original = testSetting(id: 'independent', value: 'before');
      final clone = original.copy(false);
      clone.value = 'after';

      expect(original.value, 'before');
      expect(clone.value, 'after');
    });
  });
}
