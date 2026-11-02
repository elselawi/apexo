import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StyledBarChart extends StatelessWidget {
  const StyledBarChart({
    super.key,
    required this.labels,
    required this.yAxis,
    this.color = const Color(0xFF6875F5),
  });
  final List<String> labels;
  final List<double> yAxis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty || yAxis.isEmpty || yAxis.every((value) => value == 0)) {
      return const ChartEmptyState();
    }
    final max = (yAxis.reduce((a, b) => a > b ? a : b) * 1.2).toDouble();
    return LayoutBuilder(builder: (context, constraints) => BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: max + 0.05 * max,
        barTouchData: barTouchData(labels),
        titlesData: titles(labels, context),
        gridData: grid(max, context, labelCount: labels.length),
        borderData: border(),
        barGroups: List.generate(
          labels.length,
          (index) => BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: yAxis[index].toDouble(),
                gradient: insightBarGradient(color),
                borderSide: BorderSide.none,
                width: ((constraints.maxWidth - 48) / labels.length * 0.48).clamp(1.5, 38),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4), bottom: Radius.circular(3)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  fromY: 0,
                  toY: max,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.08),
                      color.withValues(alpha: 0.025)
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
