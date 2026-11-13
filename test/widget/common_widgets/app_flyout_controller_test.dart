import 'package:apexo/utils/app_flyout_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  /// Opens a flyout from a [FlyoutTarget] and leaves it on screen.
  Future<AppFlyoutController> openFlyout(WidgetTester tester) async {
    final controller = AppFlyoutController();
    addTearDown(controller.dispose);
    await pumpApexoApp(
      tester,
      Center(
        child: FlyoutTarget(
          controller: controller,
          child: FilledButton(
            onPressed: () => controller.showFlyout<void>(
              builder: (context) => const FlyoutContent(
                child: Text('flyout'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FlyoutContent), findsOneWidget);
    return controller;
  }

  testWidgets('a metrics notification that changes nothing keeps the flyout',
      (tester) async {
    addTearDown(tester.view.reset);
    await openFlyout(tester);

    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsOneWidget);
  });

  testWidgets('a keyboard being dismissed under the flyout keeps it',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);

    await openFlyout(tester);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsOneWidget);
  });

  testWidgets('a keyboard rising under the flyout closes it', (tester) async {
    addTearDown(tester.view.reset);
    await openFlyout(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsNothing);
  });

  testWidgets('resizing the view closes the flyout', (tester) async {
    addTearDown(tester.view.reset);
    await openFlyout(tester);

    tester.view.physicalSize = tester.view.physicalSize * 2;
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsNothing);
  });
}
