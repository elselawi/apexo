import 'package:apexo/services/localization/flutter_delegates.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';

// Flutter ships no `ku` data; `appLocalizationsDelegates` supplies it.
void main() {
  Future<_Captured> pumpKu(WidgetTester tester) async {
    final captured = _Captured();
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale("ku"),
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            captured.direction = Directionality.of(context);
            captured.material = Localizations.of<MaterialLocalizations>(
              context,
              MaterialLocalizations,
            );
            captured.cupertino = Localizations.of<CupertinoLocalizations>(
              context,
              CupertinoLocalizations,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets("Kurdish resolves to an RTL Directionality", (tester) async {
    final captured = await pumpKu(tester);
    expect(captured.direction, TextDirection.rtl);
  });

  testWidgets("Kurdish provides Material and Cupertino localizations",
      (tester) async {
    final captured = await pumpKu(tester);
    expect(captured.material, isNotNull);
    expect(captured.cupertino, isNotNull);
  });

  testWidgets("Kurdish lays horizontal rows out right-to-left", (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale("ku"),
        localizationsDelegates: appLocalizationsDelegates,
        home: Row(
          children: [Text("First"), Text("Second")],
        ),
      ),
    );

    final first = tester.getTopLeft(find.text("First")).dx;
    final second = tester.getTopLeft(find.text("Second")).dx;
    expect(first, greaterThan(second));
  });

  testWidgets("Kurdish overrides leave other locales to Flutter",
      (tester) async {
    expect(
      appLocalizationsDelegates.where((d) => d.isSupported(const Locale("en"))),
      isEmpty,
    );

    late TextDirection direction;
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale("en"),
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            direction = Directionality.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(direction, TextDirection.ltr);
  });
}

class _Captured {
  TextDirection? direction;
  MaterialLocalizations? material;
  CupertinoLocalizations? cupertino;
}
