@Tags(['serial'])
library;

import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/design/mica_backdrop.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

void main() {
  DentalChartSession sessionFor() => DentalChartSession(
        id: 'patient:overlay-test',
        titleKey: kDentalChartTitleKey,
        subtitle: () => 'Overlay Patient',
        type: StateType.state,
        teeth: {},
        extraNotes: {},
        history: () => const [],
        oldNotes: () => const {},
        historyTitle: 'toothAppointmentNotes',
      );

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  const cardKey = ValueKey('overlay-test-card');

  /// The card's own height, not the room it is given: scrollable so a card
  /// taller than its ceiling is squeezed, not overflowing.
  Widget card({required double content}) => Container(
        key: cardKey,
        color: const Color(0xFFDCE6F2),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TextBox(),
              SizedBox(height: content),
            ],
          ),
        ),
      );

  /// A narrow chart with [card] floating at its foot, in a surface [height]
  /// tall — the room a phone leaves a sheet above its keyboard.
  Future<void> pumpChart(
    WidgetTester tester, {
    required double height,
    required double cardContent,
    double width = 360,
    bool still = false,
  }) async {
    final body = Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: DentalChartBody(
          session: sessionFor(),
          overlay: card(content: cardContent),
        ),
      ),
    );
    await pumpApexoApp(
      tester,
      still
          ? Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: body,
              ),
            )
          : body,
    );
  }

  double cardHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(cardKey)).height;

  testWidgets('a resting card is a bubble that keeps its own height',
      (tester) async {
    setViewport(tester, const Size(360, 740));
    await pumpChart(tester, height: 400, cardContent: 600);

    expect(cardHeight(tester), 240,
        reason: '60% of the surface is the bubble\'s rest ceiling');
    expect(find.byKey(WK.dentalChartOverlayBarrier), findsNothing,
        reason: 'the teeth take taps while nothing is being edited');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a field unfolds the card, and leaving it folds back',
      (tester) async {
    setViewport(tester, const Size(360, 740));
    await pumpChart(tester, height: 400, cardContent: 600);

    await tester.tap(find.byType(TextBox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));

    final midway = cardHeight(tester);
    expect(midway, greaterThan(240), reason: 'the card is growing');
    expect(midway, lessThan(348), reason: 'not there in one jump');

    await tester.pumpAndSettle();
    expect(cardHeight(tester), 348,
        reason: 'the surface, short of the band of teeth left to tap');
    expect(find.byKey(WK.dentalChartOverlayBarrier), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(cardHeight(tester), 240, reason: 'back to the bubble');
    expect(find.byKey(WK.dentalChartOverlayBarrier), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the chart ends the edit and does nothing else',
      (tester) async {
    setViewport(tester, const Size(360, 740));
    await pumpChart(tester, height: 400, cardContent: 600);
    await tester.tap(find.byType(TextBox));
    await tester.pumpAndSettle();

    // The strip of chart the unfolded card leaves: the chart's own dentition
    // switch sits in it, so a tap there would be visible.
    final chartSwitch = tester.getCenter(find.text(txt('showPrimary')).first);
    expect(chartSwitch.dy, lessThan(52),
        reason: 'the switch sits in the strip');

    await tester.tapAt(chartSwitch);
    await tester.pumpAndSettle();

    expect(cardHeight(tester), 240, reason: 'the tap ended the edit');
    expect(find.byKey(WK.tooth('55', selected: false)), findsNothing,
        reason: 'the tap was spent on the keyboard, not on the chart');
    expect(find.byType(ToothStateWheel), findsNothing);

    // The tap after it reaches the chart: the switch works again.
    await tester.tapAt(tester.getCenter(find.text(txt('showPrimary')).first));
    await tester.pumpAndSettle();
    expect(find.byKey(WK.tooth('55', selected: false)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with nothing being edited a tooth opens its wheel',
      (tester) async {
    setViewport(tester, const Size(700, 740));
    await pumpChart(tester, width: 700, height: 740, cardContent: 80);

    final tooth = find.byKey(WK.tooth('11', selected: false));
    expect(
      tester.getCenter(tooth).dy,
      lessThan(tester.getTopLeft(find.byKey(cardKey)).dy),
      reason: 'the tooth is above the resting card',
    );

    await tester.tapAt(tester.getCenter(tooth));
    await tester.pumpAndSettle();

    expect(find.byType(ToothStateWheel), findsOneWidget);
    expect(
        tester.widget<ToothStateWheel>(find.byType(ToothStateWheel)).iso, '11');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chart that asked for no animation unfolds at once',
      (tester) async {
    setViewport(tester, const Size(360, 740));
    await pumpChart(tester, height: 400, cardContent: 600, still: true);

    await tester.tap(find.byType(TextBox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(cardHeight(tester), 348);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card unfolds onto a rounded, frosted pane', (tester) async {
    setViewport(tester, const Size(360, 740));
    await pumpChart(tester, height: 400, cardContent: 600);

    final pane = tester.widget<AcrylicSurface>(find.byType(AcrylicSurface));
    expect(pane.blur, greaterThan(0),
        reason: 'the chart behind the card is blurred, not only dimmed');
    expect(pane.radius, greaterThan(0),
        reason: 'the pane is rounded like the card it carries');

    Finder paneFade() => find
        .ancestor(
          of: find.byType(AcrylicSurface),
          matching: find.byType(FadeTransition),
        )
        .first;
    expect(tester.widget<FadeTransition>(paneFade()).opacity.value, 0,
        reason: 'no pane while the card is a bubble');

    await tester.tap(find.byType(TextBox));
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(paneFade()).opacity.value, 1,
        reason: 'the pane arrives with the unfolded card');
    expect(tester.takeException(), isNull);
  });
}
