import 'dart:math' as math;

import 'package:apexo/services/localization/locale.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';

FlTitlesData titles(List<String> labels, BuildContext context) {
  return FlTitlesData(
    show: true,
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        reservedSize: 30,
        showTitles: labels.length > 15 ? false : true,
        getTitlesWidget: (value, meta) {
          return SideTitleWidget(
            meta: meta,
            child: Transform.translate(
              offset: const Offset(0, -10),
              child: Transform.rotate(
                angle: math.pi / -4,
                child: Txt(
                  labels[value.toInt()],
                  style:  TextStyle(fontSize: 12, color: FluentTheme.of(context).inactiveColor),
                ),
              ),
            ),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      drawBelowEverything: true,
      sideTitles: SideTitles(
        minIncluded: false,
        showTitles: true,
        reservedSize: 50,
        maxIncluded: false,
        getTitlesWidget: (value, meta) {
          return SideTitleWidget(
            meta: meta,
            child: Text(
              value.toInt().toString(),
              style: TextStyle(fontSize: 12, color: FluentTheme.of(context).inactiveColor),
            ),
          );
        },
      ),
    ),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

FlGridData grid(double max, BuildContext context) {
  return FlGridData(
    show: true,
    drawVerticalLine: true,
    horizontalInterval: math.max(max / 20, 1),
    verticalInterval: 1,
    getDrawingHorizontalLine: (value) {
      return FlLine(
        color: FluentTheme.of(context).inactiveBackgroundColor.withAlpha(150),
        strokeWidth: 1,
      );
    },
    getDrawingVerticalLine: (value) {
      return FlLine(
        color: FluentTheme.of(context).inactiveBackgroundColor.withAlpha(150),
        strokeWidth: 1,
      );
    },
  );
}

FlBorderData border() {
  return FlBorderData(show: false);
}

BarTouchData barTouchData(List<String> labels) {
  return BarTouchData(
    allowTouchBarBackDraw: true,
    touchTooltipData: BarTouchTooltipData(
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      getTooltipItem: (group, groupIndex, rod, rodIndex) {
        return BarTooltipItem(
          '${labels[groupIndex]}\n',
          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          children: <TextSpan>[
            TextSpan(
              text: rod.toY.round().toString(),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w100),
            ),
          ],
        );
      },
    ),
  );
}

double barWidth(List<String> labels) {
  return math.max((200 / labels.length), 3);
}
