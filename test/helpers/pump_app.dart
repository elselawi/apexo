import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

/// Pumps a minimal FluentApp shell around [child] for widget testing.
///
/// Wraps the widget in FluentApp + Directionality + FluentTheme so
/// Fluent UI controls can render correctly.
///
/// The ring that radiates from the record a chart has open repeats for as long
/// as the record stays open, so it is paused here unless [scopeRipple] asks for
/// it; a test that wants it has to pump bounded frames instead of settling.
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
