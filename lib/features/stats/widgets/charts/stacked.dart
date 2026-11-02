import 'dart:math' as math;

import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StyledStackedChart extends StatelessWidget {
  const StyledStackedChart({
    super.key,
    required this.labels,
    required this.datasets,
    required this.datasetLabels,
    this.colors = insightColors,
  });

  final List<String> labels;
  // One row per period, one value per series.
  final List<List<double>> datasets;
  final List<String> datasetLabels;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final totals = datasets.map((row) => row.fold(0.0, (a, b) => a + b));
    final max = totals.fold(0.0, math.max) * 1.2;
    if (labels.isEmpty || max == 0) return const ChartEmptyState();
    return LayoutBuilder(
        builder: (context, constraints) => BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: max,
                titlesData: titles(labels, context),
                gridData: grid(max, context, labelCount: labels.length),
                borderData: border(),
                barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                    '${labels[group.x]}\n${datasetLabels[rodIndex]}: ${(rod.toY - rod.fromY).round()}',
                    const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                )),
                barGroups: List.generate(datasets.length, (index) {
                  var baseline = 0.0;
                  return BarChartGroupData(
                    x: index,
                    groupVertically: true,
                    barRods: List.generate(datasetLabels.length, (series) {
                      final from = baseline;
                      baseline += datasets[index][series];
                      final color = colors[series % colors.length];
                      return BarChartRodData(
                        fromY: from,
                        toY: baseline,
                        width:
                            ((constraints.maxWidth - 48) / labels.length * 0.48)
                                .clamp(1.5, 38),
                        gradient: insightBarGradient(color),
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(3),
                      );
                    }),
                  );
                }),
              ),
            ));
  }
}
