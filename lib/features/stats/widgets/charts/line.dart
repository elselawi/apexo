import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'dart:convert';

class StyledLineChart extends StatelessWidget {
  final List<String> labels;
  final List<List<double>> datasets;
  final List<String> datasetLabels;

  const StyledLineChart({
    super.key,
    required this.labels,
    required this.datasets,
    required this.datasetLabels,
  });

  @override
  Widget build(BuildContext context) {
    final allValues = datasets.expand((dataset) => dataset).toList();
    final max = (allValues.reduce((a, b) => a > b ? a : b) * 1.2).toDouble();
    const min = 0.0;

    if (max == min && max == 0) {
      return const Center(child: Txt('No data found'));
    }

    return LineChart(
      LineChartData(
        minY: min,
        maxY: max + 0.05 * max,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) =>
                Colors.white.withValues(alpha: 0.5),
            tooltipBorder:
                BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final datasetIndex = spot.barIndex;
                return LineTooltipItem(
                  '${datasetLabels[datasetIndex]}: ${spot.y.toStringAsFixed(2)}\n${labels[spot.x.toInt()]}',
                  TextStyle(
                      color: getDeterministicItem(
                          colorsWithoutYellow,
                          datasetIndex.toString() +
                              datasetLabels[datasetIndex]),
                      fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        titlesData: titles(labels, context),
        gridData: grid(max, context),
        borderData: border(),
        lineBarsData: List.generate(
          datasets.length,
          (datasetIndex) {
            final color = getDeterministicItem(colorsWithoutYellow,
                datasetIndex.toString() + datasetLabels[datasetIndex]);
            final colorA = color.lightest;
            final colorB = color.darkest;
            return LineChartBarData(
              spots: List.generate(
                labels.length,
                (index) =>
                    FlSpot(index.toDouble(), datasets[datasetIndex][index]),
              ),
              isCurved: true,
              color: colorA,
              gradient: LinearGradient(colors: [colorA, colorB]),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              shadow: kElevationToShadow[8]![0],
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colorA, Colors.white.withAlpha(20)]),
              ),
            );
          },
        ),
      ),
    );
  }

  T getDeterministicItem<T>(List<T> items, String input) {
    input = input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    int hash = utf8.encode(input).fold(0, (prev, element) => prev + element);
    int index = hash % items.length;
    return items[index];
  }
}
