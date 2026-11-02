import 'dart:math' as math;

import 'package:apexo/services/localization/locale.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

const insightColors = <Color>[
  Color(0xFF6875F5),
  Color(0xFF12BFA5),
  Color(0xFFF18A65),
  Color(0xFFA17CF5),
];

Color insightHighlight(Color color) => Color.lerp(color, Colors.white, 0.48)!;
Color insightDepth(Color color) => Color.lerp(color, const Color(0xFF18234B), 0.4)!;

LinearGradient insightStroke(Color color) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [insightHighlight(color), color, insightDepth(color)],
      stops: const [0, 0.48, 1],
    );

LinearGradient insightBarGradient(Color color) => LinearGradient(
      colors: [color, color.withValues(alpha: 0.12)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

class ChartEmptyState extends StatelessWidget {
  const ChartEmptyState({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(FluentIcons.chart,
              size: 28, color: FluentTheme.of(context).inactiveColor),
          const SizedBox(height: 12),
          Txt(txt('insightsNoData')),
          const SizedBox(height: 4),
          Txt(txt('insightsNoDataHint'),
              textAlign: TextAlign.center,
              style: FluentTheme.of(context).typography.caption),
        ]),
      );
}

FlTitlesData titles(List<String> labels, BuildContext context) {
  return FlTitlesData(
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        reservedSize: 38,
        showTitles: true,
        interval: math.max(1, (labels.length / 4).ceil()).toDouble(),
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (index < 0 ||
              index >= labels.length ||
              value != index.toDouble()) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: SizedBox(
                width: 78,
                child: Text(labels[index],
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: FluentTheme.of(context).inactiveColor))),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        minIncluded: false,
        maxIncluded: false,
        showTitles: true,
        reservedSize: 48,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
              NumberFormat.compact(locale: locale.s.$code).format(value),
              style: TextStyle(
                  fontSize: 10, color: FluentTheme.of(context).inactiveColor)),
        ),
      ),
    ),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

FlGridData grid(double range, BuildContext context, {int labelCount = 0}) {
  final theme = FluentTheme.of(context);
  final color = theme.inactiveColor.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.32 : 0.24);
  FlLine gridLine(double value) => FlLine(
        color: color,
        strokeWidth: 1,
        dashArray: [4, 4],
      );
  return FlGridData(
    drawVerticalLine: true,
    horizontalInterval: math.max(range / 4, 1),
    verticalInterval: math.max(1, (labelCount / 4).ceil()).toDouble(),
    getDrawingHorizontalLine: gridLine,
    getDrawingVerticalLine: gridLine,
  );
}

FlBorderData border() => FlBorderData(show: false);

BarTouchData barTouchData(List<String> labels) => BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
          '${labels[group.x]}\n${rod.toY.round()}',
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );

double barWidth(List<String> labels) =>
    (240 / math.max(1, labels.length)).clamp(2, 24).toDouble();
