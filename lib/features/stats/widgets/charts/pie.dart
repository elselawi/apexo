import 'package:apexo/services/localization/locale.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StyledPie extends StatefulWidget {
  final Map<String, double> data;
  const StyledPie({required this.data, super.key});

  @override
  State<StatefulWidget> createState() => _StyledPieState();
}

class _StyledPieState extends State<StyledPie> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return const Center(child: Txt('No data'));
    if (widget.data.values.length < 2)
      return const Center(child: Txt('No data'));
    if (widget.data.values.reduce((x, y) => x + y) == 0)
      return const Center(child: Txt('No data'));

    return PieChart(
      PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (FlTouchEvent event, pieTouchResponse) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    pieTouchResponse == null ||
                    pieTouchResponse.touchedSection == null) {
                  touchedIndex = -1;
                  return;
                }
                touchedIndex =
                    pieTouchResponse.touchedSection!.touchedSectionIndex;
              });
            },
          ),
          startDegreeOffset: 180,
          borderData: FlBorderData(
            show: false,
          ),
          sectionsSpace: 1,
          centerSpaceRadius: 0,
          sections: List.generate(
            widget.data.length,
            (i) {
              final total = widget.data.values.reduce((a, b) => a + b);
              final color = Colors.accentColors.reversed
                  .toList()[i % Colors.accentColors.length];
              return PieChartSectionData(
                value: widget.data.values.elementAt(i),
                radius: touchedIndex == i ? 150 : 130,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.lightest.withAlpha(70),
                    color,
                  ],
                ),
                title: widget.data.keys.elementAt(i),
                badgeWidget: Txt(
                    "${((widget.data.values.elementAt(i) / total) * 100).toStringAsFixed(2)}%",
                    style: TextStyle(
                        color: Colors.white,
                        backgroundColor: color.withValues(alpha: 0.2))),
                badgePositionPercentageOffset: 0.8,
                titlePositionPercentageOffset: 0.4,
                titleStyle: TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  backgroundColor: color.withValues(alpha: 0.4),
                ),
              );
            },
          )),
    );
  }
}
