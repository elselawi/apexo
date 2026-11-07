import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

/// Pauses the scope ring's endless ripple unless [scopeRipple] is set, so
/// `pumpAndSettle` can settle; enabling it requires pumping bounded frames.
Future<void> pumpApexoApp(
  WidgetTester tester,
  Widget child, {
  ThemeMode theme = ThemeMode.light,
  bool scopeRipple = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  debugPauseScopeRipple = !scopeRipple;
  await tester.pumpWidget(
    FluentApp(
      home: material.Directionality(
        textDirection: direction,
        child: FluentTheme(
          data: theme == ThemeMode.dark
              ? FluentThemeData.dark()
              : FluentThemeData.light(),
          child: child,
        ),
      ),
    ),
  );
  if (scopeRipple) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    await tester.pumpAndSettle();
  }
}
