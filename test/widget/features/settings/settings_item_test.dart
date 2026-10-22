@Tags(['serial'])
library;

import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/features/settings/applies_to_indicator.dart';
import 'package:apexo/features/settings/settings_screen.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

Finder _card(String identifier) => find.byKey(WK.settingsItem(identifier));

Future<void> _expandCard(
  WidgetTester tester,
  String identifier,
  String headerLabel,
) async {
  await tester.tap(
    find
        .descendant(
          of: _card(identifier),
          matching: find.text(headerLabel),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _selectOption(
  WidgetTester tester,
  String identifier,
  String label,
) async {
  await tester.tap(find.byKey(Key('${identifier}_combo')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Finder _button(String identifier, String label) => find.descendant(
      of: _card(identifier),
      matching: find.widgetWithText(FilledButton, label),
    );

SettingsItem _textItem({
  required String identifier,
  required String initValue,
  required void Function(String newVal) apply,
}) {
  return SettingsItem(
    identifier: identifier,
    title: txt(identifier),
    description: 'description',
    icon: FluentIcons.edit,
    inputType: InputType.text,
    scope: Scope.app,
    initValue: initValue,
    apply: apply,
  );
}

SettingsItem _calendarSystemItem() {
  return SettingsItem(
    identifier: 'calendarSystem',
    title: txt('calendarSystem'),
    description: txt('calendarSystem_desc'),
    icon: WindowsIcons.calendar,
    inputType: InputType.dropDown,
    scope: Scope.device,
    options: [
      ComboBoxItem(value: 'gregorian', child: Txt(txt('gregorian'))),
      ComboBoxItem(value: 'persian', child: Txt(txt('persian'))),
      ComboBoxItem(value: 'hijri', child: Txt(txt('hijri'))),
    ],
    initValue: localSettings.calendarSystem,
    apply: (newVal) => localSettings.calendarSystem = newVal,
  );
}

SettingsItem _dentalNotationItem() {
  return SettingsItem(
    identifier: 'dentalNotation',
    title: txt('dentalNotation'),
    description: txt('dentalNotation_desc'),
    icon: FluentIcons.teeth,
    inputType: InputType.dropDown,
    scope: Scope.device,
    options: [
      ComboBoxItem(value: 'p', child: Txt(txt('palmer'))),
      ComboBoxItem(value: 'u', child: Txt(txt('universal'))),
      ComboBoxItem(value: 'i', child: Txt(txt('iso'))),
    ],
    initValue: localSettings.dentalNotation,
    apply: (newVal) => localSettings.dentalNotation = newVal,
  );
}

void main() {
  group('SettingsItem', () {
    late Map<String, dynamic> savedLocalSettings;

    setUp(() {
      savedLocalSettings = Map<String, dynamic>.from(localSettings.toJson());
    });

    tearDown(() {
      localSettings.fromJson(savedLocalSettings);
    });

    testWidgets('text cards show Save after typing and cancel restores save',
        (tester) async {
      final applied = <String>[];

      await pumpApexoApp(
        tester,
        SizedBox(
          width: 480,
          child: _textItem(
            identifier: 'currency',
            initValue: 'EUR',
            apply: applied.add,
          ),
        ),
      );

      await _expandCard(tester, 'currency', txt('currency'));

      final field = find.byKey(const Key('currency_text_field'));
      await tester.enterText(field, 'CHF');
      await tester.pumpAndSettle();

      expect(_button('currency', txt('save')), findsOneWidget);

      await tester.tap(_button('currency', txt('save')));
      await tester.pumpAndSettle();

      expect(applied, ['CHF']);
      expect(_button('currency', txt('save')), findsNothing);

      await tester.enterText(field, 'USD');
      await tester.pumpAndSettle();

      expect(_button('currency', txt('cancel')), findsOneWidget);
      await tester.tap(_button('currency', txt('cancel')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<CupertinoTextField>(field).controller!.text,
        'CHF',
      );
      expect(_button('currency', txt('save')), findsNothing);
    });

    test('legacy transcription language indices migrate to language codes', () {
      for (final entry in ['en', 'ar', 'es', 'el', 'fa'].asMap().entries) {
        localSettings.fromJson({'transcriptionLocale': '${entry.key}'});
        expect(localSettings.transcriptionLocaleNonFinal, entry.value);
      }
      localSettings.fromJson({'transcriptionLocale': 'fa'});
      expect(localSettings.transcriptionLocaleNonFinal, 'fa');
    });

    testWidgets('incoming settings refresh clean fields but preserve typing',
        (tester) async {
      String initial = 'EUR';
      late StateSetter rebuild;
      await pumpApexoApp(
        tester,
        StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return SizedBox(
            width: 480,
            child: _textItem(
              identifier: 'currency',
              initValue: initial,
              apply: (_) {},
            ),
          );
        }),
      );
      await _expandCard(tester, 'currency', txt('currency'));
      final field = find.byKey(const Key('currency_text_field'));
      rebuild(() => initial = 'CHF');
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoTextField>(field).controller!.text, 'CHF');
      await tester.enterText(field, 'USD');
      rebuild(() => initial = 'GBP');
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoTextField>(field).controller!.text, 'USD');
      expect(_button('currency', txt('save')), findsOneWidget);
      await tester.tap(_button('currency', txt('cancel')));
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoTextField>(field).controller!.text, 'GBP');
      expect(_button('currency', txt('save')), findsNothing);
    });

    testWidgets('calendar system applies only on save', (tester) async {
      localSettings.calendarSystem = 'gregorian';

      await pumpApexoApp(
        tester,
        SizedBox(width: 480, child: _calendarSystemItem()),
      );

      await _expandCard(tester, 'calendarSystem', txt('calendarSystem'));
      await _selectOption(tester, 'calendarSystem', txt('persian'));

      expect(localSettings.calendarSystem, 'gregorian');
      expect(DF.isPersianCalendar, isFalse);

      await tester.tap(_button('calendarSystem', txt('save')));
      await tester.pumpAndSettle();

      expect(localSettings.calendarSystem, 'persian');
      expect(DF.isPersianCalendar, isTrue);
      expect(DF.isHijriCalendar, isFalse);

      await _selectOption(tester, 'calendarSystem', txt('hijri'));
      await tester.tap(_button('calendarSystem', txt('save')));
      await tester.pumpAndSettle();

      expect(localSettings.calendarSystem, 'hijri');
      expect(DF.isHijriCalendar, isTrue);
      expect(DF.isPersianCalendar, isFalse);
    });

    testWidgets('dental notation save changes rendered notation',
        (tester) async {
      localSettings.dentalNotation = 'p';

      await pumpApexoApp(
        tester,
        SizedBox(width: 480, child: _dentalNotationItem()),
      );

      await _expandCard(tester, 'dentalNotation', txt('dentalNotation'));
      await _selectOption(tester, 'dentalNotation', txt('universal'));

      expect(localSettings.dentalNotation, 'p');

      await tester.tap(_button('dentalNotation', txt('save')));
      await tester.pumpAndSettle();

      expect(localSettings.dentalNotation, 'u');

      await pumpApexoApp(
        tester,
        const DentalNotation(
          iso: '11',
          withTooltip: false,
        ),
      );

      expect(find.text('8'), findsOneWidget);
    });
  });
}
