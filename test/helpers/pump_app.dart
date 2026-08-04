import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

/// Pumps a minimal FluentApp shell around [child] for widget testing.
///
/// Wraps the widget in FluentApp + Directionality + FluentTheme so
/// Fluent UI controls can render correctly.
Future<void> pumpApexoApp(
  WidgetTester tester,
  Widget child, {
  ThemeMode theme = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    FluentApp(
      home: material.Directionality(
        textDirection: TextDirection.ltr,
        child: FluentTheme(
          data: theme == ThemeMode.dark
              ? FluentThemeData.dark()
              : FluentThemeData.light(),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
