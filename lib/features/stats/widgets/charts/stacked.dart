import 'dart:math' as math;

import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StyledStackedChart extends StatelessWidget {
  final List<String> labels;
  final List<List<double>> datasets;
  final List<String> datasetLabels;

  const StyledStackedChart({
    super.key,
    required this.labels,
    required this.datasets,
    required this.datasetLabels,
  });

  @override
  Widget build(BuildContext context) {
    final values = datasets.map((s) => s.reduce((v, e) => v + e)).toList();
    final max = (values.reduce(math.max) * 1.2).toDouble();
    const min = 0;
    if ((max == min) && max == 0) {
      return const Center(child: Txt('No data found'));
    }
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: max,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${labels[groupIndex]} : ${datasetLabels[rodIndex]} \n',
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                children: <TextSpan>[
                  TextSpan(
                    text: rod.toY.round().toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w100),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: titles(labels, context),
        gridData: grid(max, context),
        borderData: FlBorderData(show: false),
        barGroups: _buildBarGroups(max),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups(double max) {
    return List.generate(datasets.length, (setIndex) {
      final set = datasets[setIndex];
      return BarChartGroupData(
          x: setIndex,
          groupVertically: true,
          barRods: List.generate(datasetLabels.length, (valueIndex) {
            return BarChartRodData(
              width: barWidth(labels),
              fromY: valueIndex == 0 ? 0 : set[valueIndex - 1],
              toY: valueIndex == 0
                  ? set[valueIndex]
                  : set[valueIndex] + set[valueIndex - 1],
              gradient: LinearGradient(colors: [
                Colors.white.withValues(alpha: 150),
                getDeterministicItem(Colors.accentColors,
                        datasetLabels[valueIndex] + setIndex.toString())
                    .withValues(alpha: 230),
              ], begin: Alignment.bottomCenter, end: Alignment.topCenter),
              borderRadius: BorderRadius.circular(7),
              backDrawRodData: BackgroundBarChartRodData(
                fromY: 0,
                toY: max - max * 0.05,
                show: true,
                color: Colors.grey.withValues(alpha: 0.05),
              ),
            );
          }));
    });
  }
}
