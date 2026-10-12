import 'package:apexo/common_widgets/context_menu_region.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<void> pumpRegion(
    WidgetTester tester, {
    required VoidCallback onPressed,
  }) {
    return pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 300,
          height: 200,
          child: ContextMenuRegion(
            items: (context, controller) => [
              MenuFlyoutItem(
                text: Txt(txt("open")),
                onPressed: onPressed,
              ),
            ],
            child: const ColoredBox(
              color: Color(0xFFFFFFFF),
              child: Center(child: Text('row')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('long press opens the menu and the item runs once',
      (tester) async {
    var pressed = 0;
    await pumpRegion(tester, onPressed: () => pressed++);

    expect(find.byType(MenuFlyout), findsNothing);

    await tester.longPress(find.text('row'));
    await tester.pumpAndSettle();

    // Txt localizes into a nested Text, so both match the same label.
    final item = find.descendant(
      of: find.byType(MenuFlyout),
      matching: find.text(txt("open")),
    );
    expect(item, findsWidgets);

    await tester.tap(item.first);
    await tester.pumpAndSettle();

    expect(pressed, 1);
    expect(find.byType(MenuFlyout), findsNothing);
  });

  testWidgets('right click opens the same menu', (tester) async {
    await pumpRegion(tester, onPressed: () {});

    await tester.tap(find.text('row'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.byType(MenuFlyout), findsOneWidget);
  });

  testWidgets('a tap alone does not open the menu', (tester) async {
    await pumpRegion(tester, onPressed: () {});

    await tester.tap(find.text('row'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuFlyout), findsNothing);
  });
}
