import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StyledRadarChart extends StatefulWidget {
  final List<List<double>> data;
  final List<String> labels;
  const StyledRadarChart({required this.data, required this.labels, super.key});

  @override
  State<StyledRadarChart> createState() => _StyledRadarChartState();
}

class _StyledRadarChartState extends State<StyledRadarChart> {
  String currentLabel = '';
  double currentValue = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return const Center(child: Txt('No data'));
    for (var set in widget.data) {
      if (set.length < 3) return const Center(child: Txt('No data'));
    }

    return Column(
      spacing: 10,
      children: [
        Expanded(
          child: RadarChart(RadarChartData(
            borderData: border(),
            gridBorderData: BorderSide(
                color: FluentTheme.of(context).inactiveBackgroundColor),
            tickBorderData: BorderSide(
                color: FluentTheme.of(context).inactiveBackgroundColor),
            radarBorderData: BorderSide(
                color: FluentTheme.of(context).inactiveBackgroundColor),
            getTitle: (index, angle) =>
                RadarChartTitle(text: widget.labels[index]),
            titlePositionPercentageOffset: 0.2,
            radarTouchData: RadarTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  if (response == null || response.touchedSpot == null) {
                    return setState(() {
                      currentLabel = "";
                      currentValue = 0;
                    });
                  }

                  final value = response.touchedSpot!.touchedRadarEntry.value;
                  final label = widget
                      .labels[response.touchedSpot!.touchedRadarEntryIndex];
                  setState(() {
                    currentLabel = label;
                    currentValue = value;
                  });
                }),
            tickCount: 1,
            ticksTextStyle: const TextStyle(color: Colors.transparent),
            titleTextStyle: TextStyle(
                color: FluentTheme.of(context).inactiveColor, fontSize: 11),
            radarShape: RadarShape.polygon,
            dataSets: List.generate(widget.data.length, (setIndex) {
              Color color = getDeterministicItem(colorsWithoutYellow,
                  widget.labels.join() + setIndex.toString());
              return RadarDataSet(
                borderColor: color,
                borderWidth: 1,
                fillColor: color.withValues(alpha: 0.1),
                dataEntries:
                    List.generate(widget.data[setIndex].length, (valueIndex) {
                  return RadarEntry(value: widget.data[setIndex][valueIndex]);
                }),
              );
            }),
          )),
        ),
        Txt(currentLabel.isEmpty
            ? ""
            : "$currentLabel : ${currentValue.toStringAsFixed(0)}"),
      ],
    );
  }
}
