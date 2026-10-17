@Tags(['serial'])
library;

import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/intl_data.dart';
import 'package:apexo/utils/money_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Money only survives a round trip if the text a field shows reads back as the
/// amount that was typed, in the separators of every locale the app ships:
/// Greek and Spanish group thousands with a dot, Persian writes the digits in
/// its own script, and English and Arabic group with a comma.
void main() {
  ensureCustomIntlLocalesInitialized();
  MoneyInputFormatter formatterFor(String localeCode) =>
      MoneyInputFormatter(NumberFormat.decimalPattern(localeCode));

  /// The field text after typing [text] into a field that was empty.
  String typeInto(MoneyInputFormatter formatter, String text) {
    return formatter
        .formatEditUpdate(
            const TextEditingValue(), TextEditingValue(text: text))
        .text;
  }

  for (final localeCode in [
    'en',
    'ar',
    'el',
    'es',
    'fa',
    'ku',
    'fr',
    'tr',
    'it',
    'ur',
  ]) {
    group('money field in "$localeCode"', () {
      final formatter = formatterFor(localeCode);

      test('every keystroke leaves the amount typed so far', () {
        for (final amount in ['1000', '2650', '26500', '1000000']) {
          var field = '';
          for (var i = 0; i < amount.length; i++) {
            field = typeInto(formatter, field + amount[i]);
            expect(formatter.parse(field),
                double.parse(amount.substring(0, i + 1)),
                reason: 'after ${i + 1} of the digits of $amount the field '
                    'shows "$field"');
          }
        }
      });

      test('an amount filled in from storage reads back as it was saved', () {
        for (final amount in [0.0, 2.65, 12.5, 999.0, 2650.0, 2650.5]) {
          final filled = formatter.formatDouble(amount);
          expect(formatter.parse(filled), amount,
              reason: 'field shows "$filled"');
        }
      });

      test('a grouped amount can still be extended', () {
        final grouped = formatter.formatDouble(2650);
        expect(formatter.parse(typeInto(formatter, '${grouped}1')), 26501,
            reason: 'field shows "$grouped" plus one digit');
      });

      test('a fraction typed with the locale separator reads back', () {
        final separator = formatter.decimalSeparator;
        expect(formatter.parse(typeInto(formatter, '12${separator}50')), 12.5);
        expect(
            formatter.parse(typeInto(formatter, '999${separator}99')), 999.99);
        expect(formatter.parse(typeInto(formatter, '${separator}5')), 0.5);
        expect(
          typeInto(formatter, '${separator}5'),
          '${formatter.formatDouble(0)}$separator${formatter.formatDouble(5)}',
        );
      });

      test('currency symbols, spaces and letters are ignored', () {
        expect(formatter.parse(typeInto(formatter, r'€ 1 234')), 1234);
        expect(formatter.parse('abc'), 0);
        expect(formatter.parse(''), 0);
      });

      test('the field shows an amount the way storage fills it in', () {
        expect(typeInto(formatter, '2650'), formatter.formatDouble(2650));
      });
    });
  }

  testWidgets('typing 2650 into a Greek price field keeps 2650',
      (tester) async {
    final formatter = formatterFor('el');
    double? price;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextField(
          inputFormatters: [formatter],
          onChanged: (text) => price = formatter.parse(text),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), '2650');
    await tester.pump();

    // The field groups the amount as "2.650" — a dot that means thousands, not
    // the 2.65 the same text used to be read as.
    expect(price, 2650);
  });

  test('moneyInputFormatter follows locale switches mid-session', () {
    final originalLocale = localSettings.selectedLocale;
    addTearDown(() => localSettings.selectedLocale = originalLocale);

    // 0 = en, 3 = el, 4 = fa
    localSettings.selectedLocale = 0;
    expect(moneyInputFormatter.decimalSeparator, '.');
    expect(moneyInputFormatter.formatDouble(2650), '2,650');

    localSettings.selectedLocale = 3;
    expect(moneyInputFormatter.decimalSeparator, ',');
    expect(moneyInputFormatter.formatDouble(2650), '2.650');
    expect(moneyInputFormatter.parse('2.650'), 2650);

    localSettings.selectedLocale = 4;
    expect(moneyInputFormatter.decimalSeparator, '٫');
    expect(moneyInputFormatter.formatDouble(2650), '۲٬۶۵۰');
    expect(moneyInputFormatter.parse('۲٬۶۵۰'), 2650);
  });

  testWidgets(
      'MoneyDisplay splits integer and decimal parts using locale separator',
      (tester) async {
    final originalLocale = localSettings.selectedLocale;
    addTearDown(() => localSettings.selectedLocale = originalLocale);

    // Greek (3): 2650.5 -> "2.650,50 USD"
    localSettings.selectedLocale = 3;
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: MoneyDisplay('2650.5 USD'),
    ));

    final texts =
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(texts, ['2.650', ',', '50 USD']);
  });
}
