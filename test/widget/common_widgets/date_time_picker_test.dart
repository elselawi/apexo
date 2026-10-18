@Tags(['serial'])
library;

import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('DateTimePicker time mode', () {
    late String savedTimeFormat;
    late int savedSelectedLocale;

    setUpAll(() async {
      await initializeDateFormatting();
    });

    setUp(() {
      savedTimeFormat = localSettings.timeFormat;
      savedSelectedLocale = localSettings.selectedLocale;
    });

    tearDown(() {
      localSettings.timeFormat = savedTimeFormat;
      localSettings.selectedLocale = savedSelectedLocale;
    });

    Future<void> openPicker(WidgetTester tester) async {
      await pumpApexoApp(
        tester,
        DateTimePicker(
          initValue: DateTime(2026, 1, 1, 14, 30),
          onChange: (_) {},
          pickTime: true,
        ),
      );
      await tester.tap(find.byType(DateTimePicker));
      await tester.pumpAndSettle();
    }

    testWidgets('12-hour setting opens a picker with AM and PM',
        (tester) async {
      localSettings.timeFormat = DF.time12hPattern;

      await openPicker(tester);

      expect(find.text('AM'), findsOneWidget);
      expect(find.text('PM'), findsOneWidget);
    });

    testWidgets('24-hour setting opens a picker without AM and PM',
        (tester) async {
      localSettings.timeFormat = DF.time24hPattern;

      await openPicker(tester);

      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
    });

    testWidgets('12-hour setting forces AM/PM for a 24-hour locale',
        (tester) async {
      localSettings.selectedLocale = 2; // es
      localSettings.timeFormat = DF.time12hPattern;

      await openPicker(tester);

      expect(find.text('AM'), findsOneWidget);
      expect(find.text('PM'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Aceptar'), findsOneWidget);
    });
  });
}
