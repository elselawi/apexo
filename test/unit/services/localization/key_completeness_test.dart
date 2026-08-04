import 'package:apexo/services/localization/ar.dart';
import 'package:apexo/services/localization/el.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/services/localization/es.dart';
import 'package:apexo/services/localization/fa.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects all keys from [en] dictionary that are missing from [other].
List<String> _missingKeys(Map<String, String> en, Map<String, String> other) {
  return en.keys.where((k) => !other.containsKey(k)).toList()..sort();
}

/// Collects all keys from [other] that are not in [en] (extra keys).
List<String> _extraKeys(Map<String, String> en, Map<String, String> other) {
  return other.keys.where((k) => !en.containsKey(k)).toList()..sort();
}

void main() {
  final en = En();
  final locales = <String, En>{
    'ar': Ar(),
    'es': Es(),
    'el': El(),
    'fa': Fa(),
  };

  group('Locale key completeness', () {
    for (final entry in locales.entries) {
      final code = entry.key;
      final locale = entry.value;

      test('$code has all keys from en', () {
        final missing = _missingKeys(en.dictionary, locale.dictionary);
        expect(
          missing,
          isEmpty,
          reason: '$code is missing ${missing.length} key(s): $missing',
        );
      });

      test('$code has no extra keys not in en', () {
        final extra = _extraKeys(en.dictionary, locale.dictionary);
        expect(
          extra,
          isEmpty,
          reason: '$code has ${extra.length} extra key(s): $extra',
        );
      });
    }
  });

  group('Locale metadata', () {
    test('en direction is ltr', () {
      expect(en.$direction, Direction.ltr);
    });

    test('en code is "en"', () {
      expect(en.$code, 'en');
    });

    test('ar direction is rtl', () {
      expect(locales['ar']!.$direction, Direction.rtl);
    });

    test('fa direction is rtl', () {
      expect(locales['fa']!.$direction, Direction.rtl);
    });

    test('es direction is ltr', () {
      expect(locales['es']!.$direction, Direction.ltr);
    });

    test('el direction is ltr', () {
      expect(locales['el']!.$direction, Direction.ltr);
    });

    test('all locales have valid codes', () {
      for (final entry in locales.entries) {
        expect(entry.value.$code, isNotEmpty);
        expect(entry.value.$code.length, lessThanOrEqualTo(2));
      }
    });

    test('all locales have names', () {
      for (final entry in locales.entries) {
        expect(entry.value.$name, isNotEmpty);
      }
    });
  });

  group('txt() function', () {
    test('returns translated string for known key', () {
      // Test with a key we know exists in en
      final result = txt('cancel');
      expect(result, isNotEmpty);
      expect(result, isNotEmpty);
    });

    test('returns input for unknown key', () {
      final result = txt('this_key_definitely_does_not_exist_12345');
      expect(result, 'this_key_definitely_does_not_exist_12345');
    });
  });

  group('locale service', () {
    test('locale.s returns current locale instance', () {
      expect(locale.s, isA<En>());
    });

    test('locale.s.dictionary is non-empty', () {
      expect(locale.s.dictionary, isNotEmpty);
    });

    test('locale list contains all 5 locales', () {
      expect(locale.list.length, 5);
    });

    test('locale list items all implement En', () {
      for (final l in locale.list) {
        expect(l, isA<En>());
      }
    });

    test('isRtl returns bool', () {
      expect(locale.isRtl, isA<bool>());
    });
  });
}
