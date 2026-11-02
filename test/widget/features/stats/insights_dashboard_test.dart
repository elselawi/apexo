@Tags(['serial'])
library;

import 'dart:ui' show PointerDeviceKind;

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:apexo/features/stats/widgets/charts/bar.dart';
import 'package:apexo/features/stats/widgets/charts/line.dart';
import 'package:apexo/features/stats/widgets/charts/stacked.dart';
import 'package:apexo/features/stats/widgets/insight_chart_card.dart';
import 'package:apexo/features/stats/widgets/insights_dashboard.dart';
import 'package:apexo/features/stats/widgets/insight_surface.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  setUp(() {
    final oldPatients = patients.docs.values.toList();
    final oldAppointments = appointments.docs.values.toList();
    final oldExpenses = expenses.docs.values.toList();
    final oldPermissions = login.savedPermissions;
    final oldStart = chartsCtrl.start();
    final oldEnd = chartsCtrl.end();
    final oldInterval = chartsCtrl.interval();
    final oldOperator = chartsCtrl.filterByOperatorID();
    patients.observableMap.clear();
    appointments.observableMap.clear();
    expenses.observableMap.clear();
    login.savedPermissions = Perm.full;
    chartsCtrl.start(DateTime(2024, 1, 1));
    chartsCtrl.end(DateTime(2024, 1, 2, 23, 59, 59, 999));
    chartsCtrl.interval(StatsInterval.days);
    chartsCtrl.filterByOperatorID('');
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(oldPatients);
      appointments.observableMap.clear();
      appointments.setAll(oldAppointments);
      expenses.observableMap.clear();
      expenses.setAll(oldExpenses);
      login.savedPermissions = oldPermissions;
      chartsCtrl.start(oldStart);
      chartsCtrl.end(oldEnd);
      chartsCtrl.interval(oldInterval);
      chartsCtrl.filterByOperatorID(oldOperator);
    });
  });

  testWidgets('empty line and bar charts render localized empty states',
      (tester) async {
    await pumpApexoApp(
        tester,
        const Row(children: [
          Expanded(
              child:
                  StyledLineChart(labels: [], datasets: [], datasetLabels: [])),
          Expanded(child: StyledBarChart(labels: [], yAxis: [])),
        ]));
    expect(find.byType(ChartEmptyState), findsNWidgets(2));
    expect(find.text(txt('insightsNoData')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-point negative cash flow stays within the chart bounds',
      (tester) async {
    await pumpApexoApp(
        tester,
        const StyledLineChart(
          labels: ['Jan 1'],
          datasets: [
            [-150]
          ],
          datasetLabels: ['Net'],
        ));
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.minY, lessThan(-150));
    expect(chart.data.maxY, greaterThanOrEqualTo(0));
    expect(chart.data.maxX, greaterThan(chart.data.minX));
    expect(tester.takeException(), isNull);
  });

  testWidgets('gradient lines retain signed data and zero-baseline fills',
      (tester) async {
    await pumpApexoApp(
        tester,
        const StyledLineChart(
          labels: ['A', 'B', 'C'],
          datasets: [
            [20, -10, 30]
          ],
          datasetLabels: ['Net'],
        ));
    final line = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single;
    expect(line.spots.map((spot) => spot.y), [20, -10, 30]);
    expect(line.gradient!.colors, hasLength(3));
    expect(line.shadow.blurRadius, greaterThan(0));
    expect(line.belowBarData.applyCutOffY, isTrue);
    expect(line.belowBarData.cutOffY, 0);
    expect(line.aboveBarData.applyCutOffY, isTrue);
    expect(line.aboveBarData.cutOffY, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bars fade toward the bottom and retain compact corners',
      (tester) async {
    await pumpApexoApp(
        tester, const StyledBarChart(labels: ['A', 'B'], yAxis: [4, 10]));
    final groups =
        tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
    expect(groups.map((group) => group.barRods.single.toY), [4, 10]);
    final rod = groups.first.barRods.single;
    final gradient = rod.gradient! as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors, hasLength(2));
    expect(gradient.colors.first.a, greaterThan(gradient.colors.last.a));
    expect(rod.backDrawRodData.show, isTrue);
    expect(rod.borderSide, BorderSide.none);
    expect(rod.borderRadius!.topLeft.x, lessThanOrEqualTo(4));
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('chart grid is visible on both axes in $theme', (tester) async {
      await pumpApexoApp(
          tester,
          const StyledLineChart(
            labels: ['A', 'B', 'C'],
            datasets: [
              [2, 4, 3]
            ],
            datasetLabels: ['Visits'],
          ),
          theme: theme);
      final data =
          tester.widget<LineChart>(find.byType(LineChart)).data.gridData;
      expect(data.drawHorizontalLine, isTrue);
      expect(data.drawVerticalLine, isTrue);
      final horizontal = data.getDrawingHorizontalLine(1);
      final vertical = data.getDrawingVerticalLine(1);
      expect(horizontal.color!.a, greaterThanOrEqualTo(0.23));
      expect(vertical.color, horizontal.color);
      expect(horizontal.strokeWidth, 1);
      expect(data.verticalInterval, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stacked status bars preserve segment values in tooltips',
      (tester) async {
    await pumpApexoApp(
        tester,
        const StyledStackedChart(
          labels: ['A'],
          datasets: [
            [8, 2]
          ],
          datasetLabels: ['Done', 'Missed'],
        ));
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    final group = data.barGroups.single;
    expect(group.barRods.map((rod) => rod.fromY), [0, 8]);
    expect(group.barRods.map((rod) => rod.toY), [8, 10]);
    final tooltip = data.barTouchData.touchTooltipData
        .getTooltipItem(group, 0, group.barRods[1], 1);
    expect(tooltip!.text, 'A\nMissed: 2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('lit surfaces respond to hover and honor reduced motion',
      (tester) async {
    await pumpApexoApp(
        tester,
        const Center(
            child: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SizedBox(
              width: 300,
              height: 200,
              child: InsightSurface(
                color: Color(0xFF6875F5),
                child: Text('Surface'),
              )),
        )));
    final surface = find.byType(InsightSurface);
    final animated =
        find.descendant(of: surface, matching: find.byType(AnimatedContainer));
    final before = tester.widget<AnimatedContainer>(animated);
    expect(before.duration, Duration.zero);
    expect((before.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(4));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(surface));
    await tester.pumpAndSettle();
    final after = tester.widget<AnimatedContainer>(animated);
    expect(after.decoration, isNot(before.decoration));
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient donut renders gradient segments without changing counts',
      (tester) async {
    patients.setAll([
      testPatient(id: 'design-female', gender: 0),
      testPatient(id: 'design-male', gender: 1),
    ]);
    appointments.setAll([
      testAppointment(patientID: 'design-female', date: DateTime(2024, 1, 1)),
      testAppointment(patientID: 'design-male', date: DateTime(2024, 1, 2)),
    ]);
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const InsightsDashboard());
    await tester.tap(find.text(txt('insightsPatients')).first);
    await tester.pumpAndSettle();
    final chart = tester.widget<PieChart>(find.byType(PieChart));
    expect(chart.data.sections.map((section) => section.value), [1, 1]);
    expect(chart.data.sections.every((section) => section.gradient != null),
        isTrue);
    expect(chart.data.centerSpaceRadius, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('chart cards use a neutral borderless Fluent surface in $theme',
        (tester) async {
      await pumpApexoApp(
          tester,
          const SizedBox(
            width: 600,
            height: 440,
            child: InsightChartCard(
              title: 'Activity',
              subtitle: 'Selected range',
              labels: ['A', 'B'],
              names: ['Visits'],
              series: [
                [2, 4]
              ],
              chart: StyledLineChart(labels: [
                'A',
                'B'
              ], datasets: [
                [2, 4]
              ], datasetLabels: [
                'Visits'
              ]),
            ),
          ),
          theme: theme);
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.backgroundColor, isNull);
      expect(card.borderColor, Colors.transparent);
      expect(card.borderRadius, BorderRadius.circular(4));
      expect(find.byType(InsightSurface), findsNothing);
      final decorations = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(Card),
            matching: find.byType(Container),
          ))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>();
      expect(
          decorations.every((decoration) =>
              decoration.gradient == null &&
              (decoration.boxShadow == null || decoration.boxShadow!.isEmpty)),
          isTrue);
      final line = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData
          .single;
      expect(line.gradient, isNotNull);
      expect(line.shadow.blurRadius, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chart data table and CSV copy preserve exact values',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApexoApp(
        tester,
        const SizedBox(
            width: 600,
            height: 410,
            child: InsightChartCard(
                title: 'Revenue',
                subtitle: 'Selected period',
                labels: ['Jan 1'],
                names: ['Payments'],
                series: [
                  [123.45]
                ],
                money: true,
                chart: Text('Chart placeholder'))));
    await tester.tap(find.byIcon(FluentIcons.table));
    await tester.pumpAndSettle();
    expect(find.text('123.45'), findsOneWidget);
    expect(find.text('Chart placeholder'), findsNothing);
    await tester.tap(find.byIcon(FluentIcons.copy));
    await tester.pump();
    expect(copied, contains('123.45'));
    expect(copied, contains('Jan 1'));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview controls work and store changes refresh metrics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const InsightsDashboard());
    expect(find.byKey(const ValueKey('cash-flow')), findsOneWidget);
    expect(find.byKey(const ValueKey('outstanding')), findsOneWidget);
    await tester.tap(find.text(txt('insightsBars')).first);
    await tester.pumpAndSettle();
    final activityBar = find.descendant(
        of: find.byKey(const ValueKey('activity')),
        matching: find.byType(StyledBarChart));
    expect(activityBar, findsOneWidget);
    final visit = testAppointment(
        id: 'insights-live', date: DateTime(2024, 1, 1), paid: 120);
    appointments.set(visit);
    await tester.pumpAndSettle();
    final chart = tester.widget<StyledBarChart>(activityBar);
    expect(chart.yAxis, [1, 0]);
    final cashFlow = find.byKey(const ValueKey('cash-flow'));
    await tester.ensureVisible(cashFlow);
    await tester.tap(
        find.descendant(of: cashFlow, matching: find.byType(ToggleSwitch)));
    await tester.pumpAndSettle();
    final card = tester.widget<InsightChartCard>(cashFlow);
    expect(card.series.single, [120, 120]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow dark RTL layout supports all sections without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(
        tester,
        const Directionality(
            textDirection: TextDirection.rtl, child: InsightsDashboard()),
        theme: ThemeMode.dark);
    await tester.ensureVisible(find.text(txt('insightsPatterns')).first);
    await tester.tap(find.text(txt('insightsPatterns')).first);
    await tester.pumpAndSettle();
    expect(find.byType(ComboBox<int>), findsOneWidget);
    await tester.ensureVisible(find.text(txt('insightsPatients')).first);
    await tester.tap(find.text(txt('insightsPatients')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gender')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pattern controls retain every distribution and label the table dimension',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const InsightsDashboard());
    await tester.tap(find.text(txt('insightsPatterns')).first);
    await tester.pumpAndSettle();
    final expectedLengths = [24, 7, 31, 12];
    for (var index = 0; index < expectedLengths.length; index++) {
      tester
          .widget<ComboBox<int>>(find.byType(ComboBox<int>))
          .onChanged!(index);
      await tester.pumpAndSettle();
      final card = tester
          .widget<InsightChartCard>(find.byKey(const ValueKey('patterns')));
      expect(card.labels.length, expectedLengths[index]);
      expect(card.series.single.length, expectedLengths[index]);
      expect(card.dimensionLabel, isNot(txt('insightsPeriod')));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new practical charts expose accurate series and fractional hours in tables',
      (tester) async {
    patients.set(testPatient(id: 'practical-patient'));
    appointments.setAll([
      testAppointment(
          patientID: 'practical-patient',
          date: DateTime(2024, 1, 1),
          duration: 45,
          isDone: true,
          price: 100,
          paid: 40),
      testAppointment(
          patientID: 'practical-patient',
          date: DateTime(2024, 1, 2),
          duration: 30,
          price: 200,
          paid: 10),
    ]);
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const InsightsDashboard());
    final completed = tester.widget<InsightChartCard>(
        find.byKey(const ValueKey('completed-value')));
    expect(completed.series, [
      [100, 0],
      [40, 0]
    ]);
    final debt =
        tester.widget<InsightChartCard>(find.byKey(const ValueKey('debt-age')));
    expect(debt.series.single, [0, 0, 0, 60]);
    expect(debt.dimensionLabel, txt('insightsAge'));
    await tester.tap(find.text(txt('insightsPatterns')).first);
    await tester.pumpAndSettle();
    final hoursFinder = find.byKey(const ValueKey('chair-hours'));
    final hours = tester.widget<InsightChartCard>(hoursFinder);
    expect(hours.series, [
      [0.75, 0.5],
      [0.75, 0]
    ]);
    await tester.ensureVisible(hoursFinder);
    await tester.tap(find.descendant(
        of: hoursFinder, matching: find.byIcon(FluentIcons.table)));
    await tester.pumpAndSettle();
    expect(find.text('0.75'), findsNWidgets(2));
    await tester.ensureVisible(find.text(txt('insightsPatients')).first);
    await tester.tap(find.text(txt('insightsPatients')).first);
    await tester.pumpAndSettle();
    final visits = tester
        .widget<InsightChartCard>(find.byKey(const ValueKey('patient-visits')));
    expect(visits.series, [
      [1, 0],
      [0, 1]
    ]);
    expect(visits.chart, isA<StyledStackedChart>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('revenue permission hides financial charts and copy controls',
      (tester) async {
    login.savedPermissions = Perm.full..[Perm.revenue] = 0;
    await pumpApexoApp(tester, const InsightsDashboard());
    expect(find.byKey(const ValueKey('payments')), findsNothing);
    expect(find.byKey(const ValueKey('cash-flow')), findsNothing);
    expect(find.byKey(const ValueKey('outstanding')), findsNothing);
    expect(find.byKey(const ValueKey('completed-value')), findsNothing);
    expect(find.byKey(const ValueKey('debt-age')), findsNothing);
    expect(find.text(txt('insightsNet')), findsNothing);
    expect(find.byType(InsightChartCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
