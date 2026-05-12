import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'dart:convert';

class StyledBarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> yAxis;

  const StyledBarChart({
    super.key,
    required this.labels,
    required this.yAxis,
  });

  @override
  Widget build(BuildContext context) {
    final max = (yAxis.reduce((a, b) => a > b ? a : b) * 1.2).toDouble();
    const min = 0;
    if ((max == min) && max == 0) {
      return const Center(child: Txt('No data found'));
    }
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: max + 0.05 * max,
        barTouchData: barTouchData(labels),
        titlesData: titles(labels, context),
        gridData: grid(max, context),
        borderData: border(),
        barGroups: List.generate(
          labels.length,
          (index) => BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: yAxis[index].toDouble(),
                gradient: LinearGradient(
                  colors: [
                    getDeterministicItem(Colors.accentColors, "${index}1")
                        .withAlpha(90),
                    getDeterministicItem(Colors.accentColors, index.toString()),
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: barWidth(labels),
                borderRadius: BorderRadius.circular(10),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  fromY: 0,
                  toY: (yAxis.reduce((a, b) => a > b ? a : b) * 1.2).toDouble(),
                  color: FluentTheme.of(context)
                      .inactiveBackgroundColor
                      .toAccentColor()
                      .lighter,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  T getDeterministicItem<T>(List<T> items, String input) {
    // Convert the input string to a hash code
    int hash = utf8.encode(input).fold(0, (prev, element) => prev + element);

    // Use the hash code to determine the index
    int index = hash % items.length;

    return items[index];
  }
}
