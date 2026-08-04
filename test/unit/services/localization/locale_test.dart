import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Internationalization', () {
    test('locale singleton exists', () {
      expect(locale, isNotNull);
    });

    test('s getter returns a dictionary based on selectedLocale', () {
      final previousLocale = localSettings.selectedLocale;

      localSettings.selectedLocale = 0; // English
      expect(locale.s.$code, 'en');

      localSettings.selectedLocale = 1; // Arabic
      expect(locale.s.$code, 'ar');

      localSettings.selectedLocale = 2; // Spanish
      expect(locale.s.$code, 'es');

      // Restore
      localSettings.selectedLocale = previousLocale;
    });

    test('isRtl is true for Arabic, false for English', () {
      final prev = localSettings.selectedLocale;
      localSettings.selectedLocale = 0;
      expect(locale.isRtl, false);
      localSettings.selectedLocale = 1;
      expect(locale.isRtl, true);
      localSettings.selectedLocale = prev;
    });

    test('txt returns translated term', () {
      final prev = localSettings.selectedLocale;
      localSettings.selectedLocale = 0;
      expect(txt('save'), 'Save');
      localSettings.selectedLocale = 1;
      expect(txt('save'), 'حفظ');
      localSettings.selectedLocale = prev;
    });

    test('txt returns input when term not found', () {
      expect(txt("this doesn't exist"), "this doesn't exist");
    });

    test('list has 5 locales', () {
      expect(locale.list.length, 5);
    });

    test('all terms begin with lowercase key', () {
      for (final entry in locale.list.first.dictionary.entries) {
        expect(entry.key[0], entry.key[0].toLowerCase());
      }
    });

    test('all terms are non-empty', () {
      for (final lang in locale.list) {
        for (final value in lang.dictionary.values) {
          expect(value, isNotEmpty);
        }
      }
    });

    test('all terms in English exist in all other locales', () {
      final base = locale.list.first; // English
      for (final lang in locale.list) {
        for (final term in base.dictionary.keys) {
          expect(lang.dictionary[term], isNotNull,
              reason: 'Term "$term" missing in ${lang.$name}');
          expect(lang.dictionary[term]!.isNotEmpty, true,
              reason: 'Term "$term" is empty in ${lang.$name}');
        }
      }
    });
  });
}
