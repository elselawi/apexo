import 'dart:math' as math;
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StyledLineChart extends StatelessWidget {
  const StyledLineChart({
    super.key,
    required this.labels,
    required this.datasets,
    required this.datasetLabels,
    this.colors = insightColors,
  });
  final List<String> labels;
  final List<List<double>> datasets;
  final List<String> datasetLabels;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final allValues = datasets.expand((dataset) => dataset).toList();
    if (labels.isEmpty || allValues.isEmpty || allValues.every((v) => v == 0)) {
      return const ChartEmptyState();
    }
    final low = math.min(0.0, allValues.reduce(math.min));
    final high = math.max(0.0, allValues.reduce(math.max));
    final padding = (high - low) * 0.15;
    final min = low < 0 ? low - padding : 0.0;
    final max = high + padding;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: labels.length < 2 ? 1 : (labels.length - 1).toDouble(),
        minY: min,
        maxY: max,
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (bar, indexes) => indexes.map((index) {
            final color = bar.gradient?.colors[1] ?? colors.first;
            return TouchedSpotIndicatorData(
              FlLine(
                  color: color.withValues(alpha: 0.35),
                  strokeWidth: 1,
                  dashArray: [4, 4]),
              FlDotData(
                  getDotPainter: (spot, percent, line, index) =>
                      FlDotCirclePainter(
                        radius: 6,
                        color: color,
                        strokeWidth: 3,
                        strokeColor: FluentTheme.of(context)
                            .resources
                            .solidBackgroundFillColorBase,
                      )),
            );
          }).toList(),
          touchTooltipData: LineTouchTooltipData(
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            getTooltipColor: (_) =>
                FluentTheme.of(context).resources.solidBackgroundFillColorBase,
            tooltipBorder: BorderSide(
                color: FluentTheme.of(context)
                    .resources
                    .dividerStrokeColorDefault),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final datasetIndex = spot.barIndex;
                return LineTooltipItem(
                  '${datasetLabels[datasetIndex]}: ${spot.y.toStringAsFixed(2)}\n${labels[spot.x.toInt()]}',
                  TextStyle(
                      color: colors[datasetIndex % colors.length],
                      fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        titlesData: titles(labels, context),
        gridData: grid(max - min, context, labelCount: labels.length),
        borderData: border(),
        lineBarsData: List.generate(
          datasets.length,
          (datasetIndex) {
            final color = colors[datasetIndex % colors.length];
            return LineChartBarData(
              spots: List.generate(
                labels.length,
                (index) =>
                    FlSpot(index.toDouble(), datasets[datasetIndex][index]),
              ),
              isCurved: true,
              preventCurveOverShooting: true,
              gradient: insightStroke(color),
              barWidth: 3.5,
              isStrokeCapRound: true,
              shadow: Shadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) =>
                    labels.length <= 8 || spot.x == labels.length - 1,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: labels.length <= 8 ? 3.5 : 4,
                  color: FluentTheme.of(context)
                      .resources
                      .solidBackgroundFillColorBase,
                  strokeWidth: 2.5,
                  strokeColor: color,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                applyCutOffY: low < 0,
                cutOffY: 0,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 1],
                  colors: [
                    color.withValues(alpha: 0.32),
                    color.withValues(alpha: 0.13),
                    color.withValues(alpha: 0.015),
                  ],
                ),
              ),
              aboveBarData: BarAreaData(
                show: low < 0,
                applyCutOffY: true,
                cutOffY: 0,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    color.withValues(alpha: 0.24),
                    color.withValues(alpha: 0.01)
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
