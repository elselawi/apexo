import 'package:apexo/services/backdrop.dart';
import 'package:apexo/ui/design/ambient_backdrop.dart';
import 'package:apexo/ui/design/mica_backdrop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Windows composes Mica behind the window itself. Everywhere else
/// [AmbientBackdrop] stands in for it, and these pin what makes the stand-in
/// worth having: it moves, it can be told not to, and it stays out of the
/// window DWM is already painting.
void main() {
  tearDown(() => Backdrop.native = false);

  AmbientMaterial materialOf(WidgetTester tester) => tester
      .widget<CustomPaint>(
        find.descendant(
          of: find.byType(AmbientBackdrop),
          matching: find.byType(CustomPaint),
        ),
      )
      .painter! as AmbientMaterial;

  Future<void> pumpShell(WidgetTester tester, {bool still = false}) =>
      tester.pumpWidget(
        FluentApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child:
                const MicaBackdrop(child: SizedBox.expand(key: Key('shell'))),
          ),
        ),
      );

  testWidgets('the stand-in material drifts', (tester) async {
    await pumpShell(tester);
    final before = materialOf(tester).phase;

    await tester.pump(const Duration(seconds: 4));

    expect(
      materialOf(tester).phase,
      isNot(before),
      reason: 'the material is still: it reads as a flat page again',
    );
  });

  testWidgets('Reduce Motion leaves the stand-in still', (tester) async {
    await pumpShell(tester, still: true);
    final before = materialOf(tester).phase;

    await tester.pump(const Duration(seconds: 4));

    expect(materialOf(tester).phase, before);
  });

  testWidgets('a native Windows backdrop paints nothing over itself',
      (tester) async {
    Backdrop.native = true;
    await pumpShell(tester);

    expect(
      find.byType(AmbientBackdrop),
      findsNothing,
      reason: 'the stand-in would cover the wallpaper DWM is composing',
    );
    expect(find.byKey(const Key('shell')), findsOneWidget);
  });
}
