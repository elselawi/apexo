import 'package:apexo/core/observable.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:test/test.dart';

void main() {
  group("Internationalization", () {
    test("is observable", () async {
      expect(locale.selectedLocale, isA<ObservableState>());
      int count = 0;
      locale.selectedLocale.observe((e) {
        count++;
      });
      expect(locale.selectedLocale(), 0);
      locale.setSelected(1);
      expect(locale.selectedLocale(), 1);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(count, 1);
      locale.setSelected(0);
      expect(locale.selectedLocale(), 0);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(count, 2);
    });
    test("txt being an abstraction over the main i18 class", () async {
      expect(locale.s.dictionary["save"], "Save");
      expect(txt("save"), "Save");
      locale.setSelected(1);
      expect(txt("save"), "حفظ");
      locale.setSelected(0);
      expect(txt("save"), "Save");
    });

    test("Given term is automatically lowercases first letter", () {
      expect(txt("save"), "Save");
      expect(txt("Save"), "Save");
    });

    test("If terms isn't found it would return the same input", () {
      locale.setSelected(1);
      expect(txt("this doesn't exist"), "this doesn't exist");
      locale.setSelected(0);
      expect(txt("this doesn't exist"), "this doesn't exist");
    });

    test("all terms begin with lowercase", () async {
      locale.list.first.dictionary.forEach((key, value) {
        expect(key[0], key[0].toLowerCase());
      });
    });
    test("all terms are translated", () async {
      for (var element in locale.list) {
        element.dictionary.forEach((key, value) {
          expect(value, isNotEmpty);
        });
      }
    });

    test("all terms in the first are translated and included in others", () {
      final base = locale.list.first;
      for (var lang in locale.list) {
        for (var term in base.dictionary.keys) {
          try {
            expect(lang.dictionary[term], isA<String>());
            expect(lang.dictionary[term], isNotEmpty);
          } catch (e) {
            throw ("Term not found: $term in ${lang.$name}");
          }
        }
      }
    });
  });
}
