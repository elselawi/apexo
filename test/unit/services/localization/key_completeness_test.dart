@Tags(['serial'])
library;

import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/ar.dart';
import 'package:apexo/services/localization/el.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/services/localization/es.dart';
import 'package:apexo/services/localization/fa.dart';
import 'package:apexo/services/localization/fr.dart';
import 'package:apexo/services/localization/it.dart';
import 'package:apexo/services/localization/ku.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/localization/tr.dart';
import 'package:apexo/services/localization/ur.dart';
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
    'ku': Ku(),
    'fr': Fr(),
    'tr': Tr(),
    'it': It(),
    'ur': Ur(),
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
      expect(en.$direction, TextDirection.ltr);
    });

    test('en code is "en"', () {
      expect(en.$code, 'en');
    });

    test('ar direction is rtl', () {
      expect(locales['ar']!.$direction, TextDirection.rtl);
    });

    test('fa direction is rtl', () {
      expect(locales['fa']!.$direction, TextDirection.rtl);
    });

    test('es direction is ltr', () {
      expect(locales['es']!.$direction, TextDirection.ltr);
    });

    test('el direction is ltr', () {
      expect(locales['el']!.$direction, TextDirection.ltr);
    });

    test('ku direction is rtl', () {
      expect(locales['ku']!.$direction, TextDirection.rtl);
    });

    test('fr direction is ltr', () {
      expect(locales['fr']!.$direction, TextDirection.ltr);
    });

    test('tr direction is ltr', () {
      expect(locales['tr']!.$direction, TextDirection.ltr);
    });

    test('it direction is ltr', () {
      expect(locales['it']!.$direction, TextDirection.ltr);
    });

    test('ur direction is rtl', () {
      expect(locales['ur']!.$direction, TextDirection.rtl);
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

    test('locale list contains all 10 locales', () {
      expect(locale.list.length, 10);
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

  group('Date formatting across locales', () {
    test('DF formats dates and times for every locale without throwing', () {
      final prev = localSettings.selectedLocale;
      final prevCalendar = localSettings.calendarSystem;
      addTearDown(() {
        localSettings.selectedLocale = prev;
        localSettings.calendarSystem = prevCalendar;
      });

      final sampleDate = DateTime(2026, 10, 16, 14, 30);
      localSettings.calendarSystem = 'gregorian';

      for (var i = 0; i < locale.list.length; i++) {
        localSettings.selectedLocale = i;
        final code = locale.s.$code;
        expect(DF.commonDate(sampleDate), isNotEmpty,
            reason: 'DF.commonDate failed for $code');
        expect(DF.full(sampleDate), isNotEmpty,
            reason: 'DF.full failed for $code');
        expect(DF.fullCompact(sampleDate), isNotEmpty,
            reason: 'DF.fullCompact failed for $code');
        expect(DF.allNumbers(sampleDate), isNotEmpty,
            reason: 'DF.allNumbers failed for $code');
        expect(DF.time(sampleDate), isNotEmpty,
            reason: 'DF.time failed for $code');
        expect(DF.jalaliMonthYear(sampleDate), isNotEmpty,
            reason: 'DF.jalaliMonthYear failed for $code');
        expect(DF.jalaliDayOfWeekAbbr(sampleDate), isNotEmpty,
            reason: 'DF.jalaliDayOfWeekAbbr failed for $code');
      }
    });
  });
}
