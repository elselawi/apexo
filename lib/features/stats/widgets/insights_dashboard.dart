import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/stats/insights_data.dart';
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:apexo/features/stats/widgets/charts/bar.dart';
import 'package:apexo/features/stats/widgets/charts/line.dart';
import 'package:apexo/features/stats/widgets/charts/stacked.dart';
import 'package:apexo/features/stats/widgets/insight_chart_card.dart';
import 'package:apexo/features/stats/widgets/insight_surface.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class InsightsDashboard extends StatefulWidget {
  const InsightsDashboard({super.key});

  @override
  State<InsightsDashboard> createState() => _InsightsDashboardState();
}

class _InsightsDashboardState extends State<InsightsDashboard> {
  int section = 0;
  int pattern = 0;
  bool bars = false;
  bool cumulative = false;

  String _money(double value) =>
      '${formatMoneyInText(value.toStringAsFixed(2))} ${currency()}';

  @override
  Widget build(BuildContext context) => MStreamBuilder(
        streams: [
          chartsCtrl.start.stream,
          chartsCtrl.end.stream,
          chartsCtrl.interval.stream,
          chartsCtrl.filterByOperatorID.stream,
          appointments.observableMap.stream,
          expenses.observableMap.stream,
          patients.observableMap.stream,
          localSettings.stream,
          globalSettings.observableMap.stream,
        ],
        builder: (context, _) {
          final data = InsightsData(
            periods: chartsCtrl.periods,
            appointments: chartsCtrl.filteredAppointments,
            receipts: login.perm(Perm.revenue).read
                ? chartsCtrl.filteredReceipts
                : [],
          );
          final revenue = login.perm(Perm.revenue).read;
          return LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 960 ? 2 : 1;
            final width =
                (constraints.maxWidth - 40 - (columns - 1) * 16) / columns;
            return ListView(
              key: const PageStorageKey('insights-dashboard'),
              padding: const EdgeInsets.all(20),
              children: [
                _summary(data, constraints.maxWidth - 40, revenue),
                const SizedBox(height: 24),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (index, key) in [
                        'insightsOverview',
                        'insightsPatterns',
                        'insightsPatients'
                      ].indexed)
                        ToggleButton(
                            checked: section == index,
                            onChanged: (_) => setState(() => section = index),
                            child: Txt(txt(key))),
                      if (revenue && chartsCtrl.filterByOperatorID().isNotEmpty)
                        Txt(txt('insightsClinicExpenses'),
                            style: FluentTheme.of(context).typography.caption),
                    ]),
                const SizedBox(height: 16),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  for (final card in _cards(data, revenue))
                    SizedBox(width: width, height: 440, child: card),
                ]),
              ],
            );
          });
        },
      );

  Widget _summary(InsightsData data, double width, bool revenue) {
    final number = NumberFormat.decimalPattern(locale.s.$code);
    final metrics = <(String, String, String, IconData, Color)>[
      (
        txt('appointments'),
        number.format(data.totalAppointments),
        '${number.format(InsightsData.sum(data.newPatients))} ${txt('insightsNewPatients')}',
        FluentIcons.date_time,
        insightColors[0]
      ),
      (
        txt('insightsCompletion'),
        '${data.completionRate.toStringAsFixed(1)}%',
        '${number.format(InsightsData.sum(data.done))} ${txt('done')} · ${number.format(InsightsData.sum(data.missed))} ${txt('missed')}',
        FluentIcons.check_mark,
        insightColors[1]
      ),
      (
        txt('insightsUniquePatients'),
        number.format(data.uniquePatients),
        '${data.uniquePatients == 0 ? '0' : (data.patientVisits / data.uniquePatients).toStringAsFixed(1)} ${txt('insightsVisits')}',
        FluentIcons.people,
        insightColors[3]
      ),
      if (revenue)
        (
          txt('insightsNet'),
          _money(InsightsData.sum(data.cashFlow)),
          '${txt('insightsOutstanding')}: ${_money(InsightsData.sum(data.outstanding))}',
          FluentIcons.currency,
          insightColors[2]
        ),
    ];
    final columns = width >= 1100
        ? metrics.length
        : width >= 520
            ? 2
            : 1;
    final cardWidth = (width - (columns - 1) * 12) / columns;
    final theme = FluentTheme.of(context);
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final (label, value, detail, icon, color) in metrics)
        SizedBox(
            width: cardWidth,
            child: InsightSurface(
                color: color,
                padding: const EdgeInsets.all(18),
                radius: 4,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: insightStroke(color),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                    color: color.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4))
                              ],
                            ),
                            child: Icon(icon, size: 15, color: Colors.white)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Txt(label,
                                style: theme.typography.caption
                                    ?.copyWith(fontWeight: FontWeight.w600))),
                      ]),
                      const SizedBox(height: 14),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.9,
                              shadows: [
                                Shadow(
                                    color: color.withValues(alpha: 0.16),
                                    blurRadius: 16,
                                    offset: const Offset(0, 3))
                              ])),
                      const SizedBox(height: 8),
                      Container(
                          width: 32,
                          height: 3,
                          decoration: BoxDecoration(
                              gradient: insightStroke(color),
                              borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 10),
                      Txt(detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.caption),
                    ]))),
    ]);
  }

  List<Widget> _cards(InsightsData data, bool revenue) {
    if (section == 1) {
      return [
        _patterns(data),
        _card('chair-hours', txt('insightsChairHours'), txt('insightsChairHoursHint'),
          data.labels, [data.scheduledHours, data.completedHours],
          [txt('insightsScheduledHours'), txt('insightsCompletedHours')],
          decimalDigits: 2),
      ];
    }
    if (section == 2) {
      return [
        _card(
            'new-patients',
            '${txt('newPatientsPer')} ${txt(chartsCtrl.intervalString)}',
            '${txt('acquiredPatientsIn')} ${data.periods.length} ${txt(chartsCtrl.intervalString)}',
            data.labels,
            [data.newPatients],
            [txt('patients')]),
        _card('patient-visits', txt('insightsPatientVisits'), txt('insightsPatientVisitsHint'),
          data.labels, [data.newPatients, data.returningVisits],
          [txt('insightsNewVisits'), txt('insightsReturningVisits')]),
        InsightChartCard(
          key: const ValueKey('gender'),
          title: txt('patientsGender'),
          subtitle: txt('insightsGenderHint'),
          dimensionLabel: txt('patientsGender'),
          colors: [insightColors[3], insightColors[0]],
          icon: FluentIcons.people,
          labels: [txt('female'), txt('male')],
          names: [txt('patients')],
          series: [
            [data.female.toDouble(), data.male.toDouble()]
          ],
          chart: _donut(data),
        ),
      ];
    }
    return [
      _card(
          'activity',
          txt('insightsActivity'),
          bars
              ? '${txt('appointmentsPer')} ${txt(chartsCtrl.intervalString)}'
              : txt('insightsActivityHint'),
          data.labels,
          bars ? [data.counts] : [data.counts, data.newPatients],
          bars
              ? [txt('appointments')]
              : [txt('appointments'), txt('insightsNewPatients')],
          chart: bars
              ? StyledBarChart(labels: data.labels, yAxis: data.counts)
              : null,
          controls: Wrap(spacing: 6, children: [
            ToggleButton(
                checked: !bars,
                onChanged: (_) => setState(() => bars = false),
                child: Txt(txt('insightsLine'))),
            ToggleButton(
                checked: bars,
                onChanged: (_) => setState(() => bars = true),
                child: Txt(txt('insightsBars'))),
          ])),
      if (revenue)
        _card(
            'payments',
            '${txt('paymentsAndExpensesPer')} ${txt(chartsCtrl.intervalString)}',
            txt('insightsClinicExpenses'),
            data.labels,
            [data.payments, data.expenses],
            [
              '${txt('payments')} ${currency()}',
              '${txt('expenses')} ${currency()}'
            ],
            money: true),
      _card(
          'status',
          '${txt('doneMissedPer')} ${txt(chartsCtrl.intervalString)}',
          txt('insightsStatusHint'),
          data.labels,
          [data.done, data.missed],
          [txt('done'), txt('missed')]),
      if (revenue) ...[
        _card(
            'cash-flow',
            txt('insightsCashFlow'),
            txt('insightsCashFlowHint'),
            data.labels,
            [
              cumulative
                  ? InsightsData.cumulative(data.cashFlow)
                  : data.cashFlow
            ],
            ['${txt('insightsNet')} ${currency()}'],
            money: true,
            controls: ToggleSwitch(
                checked: cumulative,
                onChanged: (value) => setState(() => cumulative = value),
                content: Txt(txt('insightsCumulative')))),
        _card(
            'outstanding',
            txt('insightsOutstanding'),
            txt('insightsOutstandingHint'),
            data.labels,
            [data.outstanding],
            ['${txt('insightsOutstanding')} ${currency()}'],
            money: true),
        _card('completed-value', txt('insightsCompletedValue'), txt('insightsCompletedValueHint'),
          data.labels, [data.completedCharges, data.completedPayments],
          ['${txt('insightsCharges')} ${currency()}', '${txt('insightsCollections')} ${currency()}'],
          money: true),
        _card('debt-age', txt('insightsDebtAge'), txt('insightsDebtAgeHint'),
          [txt('insightsAge30'), txt('insightsAge60'), txt('insightsAge90'), txt('insightsAgeOlder')],
          [data.debtByAge], ['${txt('insightsOutstanding')} ${currency()}'],
          dimensionLabel: txt('insightsAge'), money: true,
          chart: StyledBarChart(
            labels: [txt('insightsAge30'), txt('insightsAge60'), txt('insightsAge90'), txt('insightsAgeOlder')],
            yAxis: data.debtByAge, color: insightColors[2])),
      ],
    ];
  }

  Widget _card(String id, String title, String subtitle, List<String> labels,
      List<List<double>> series, List<String> names,
      {Widget? chart,
      Widget? controls,
      bool money = false,
      int? decimalDigits,
      String? dimensionLabel}) {
    final (color, secondary, icon) = switch (id) {
      'payments' => (insightColors[1], insightColors[2], FluentIcons.currency),
      'status' => (insightColors[1], insightColors[2], FluentIcons.check_mark),
      'cash-flow' => (insightColors[3], insightColors[0], FluentIcons.chart),
      'outstanding' => (
          insightColors[2],
          insightColors[3],
          FluentIcons.currency
        ),
      'new-patients' => (
          insightColors[3],
          insightColors[1],
          FluentIcons.people
        ),
      'patterns' => (insightColors[0], insightColors[3], FluentIcons.clock),
      'chair-hours' => (insightColors[0], insightColors[1], FluentIcons.clock),
      'patient-visits' => (insightColors[3], insightColors[1], FluentIcons.people),
      'completed-value' => (insightColors[0], insightColors[1], FluentIcons.currency),
      'debt-age' => (insightColors[2], insightColors[3], FluentIcons.currency),
      _ => (insightColors[0], insightColors[1], FluentIcons.date_time),
    };
    final colors = [color, secondary];
    return InsightChartCard(
      key: ValueKey(id),
      title: title,
      subtitle: subtitle,
      labels: labels,
      series: series,
      names: names,
      money: money,
      decimalDigits: decimalDigits,
      dimensionLabel: dimensionLabel,
      colors: colors,
      icon: icon,
      controls: controls,
      chart: chart ??
          (id == 'status' || id == 'patient-visits'
              ? StyledStackedChart(
                  labels: labels,
                  datasets: List.generate(
                      labels.length,
                      (index) =>
                          series.map((values) => values[index]).toList()),
                  datasetLabels: names,
                  colors: colors)
              : StyledLineChart(
                  labels: labels,
                  datasets: series,
                  datasetLabels: names,
                  colors: colors)),
    );
  }

  Widget _patterns(InsightsData data) {
    final keys = ['timeOfDay', 'dayOfWeek', 'dayOfMonth', 'monthOfYear'];
    final List<String> labels;
    final List<double> values;
    switch (pattern) {
      case 0:
        labels = List.generate(
            24, (hour) => DF.hourLabel(DateTime(2000, 1, 1, hour)));
        values = chartsCtrl.timeOfDayDistribution;
      case 1:
        labels = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday'
        ].map(txt).toList();
        values = chartsCtrl.dayOfWeekDistribution;
      case 2:
        labels = List.generate(31, (day) => '${day + 1}');
        values = chartsCtrl.dayOfMonthDistribution;
      default:
        labels = (DF.isPersianCalendar
                ? [
                    'farvardin',
                    'ordibehesht',
                    'khordad',
                    'tir',
                    'mordad',
                    'shahrivar',
                    'mehr',
                    'aban',
                    'azar',
                    'dey',
                    'bahman',
                    'esfand'
                  ]
                : DF.isHijriCalendar
                    ? [
                        'muharram',
                        'safar',
                        'rabiAlAwwal',
                        'rabiAlThani',
                        'jumadaAlUla',
                        'jumadaAlAkhirah',
                        'rajab',
                        'shaban',
                        'ramadan',
                        'shawwal',
                        'dhuAlQidah',
                        'dhuAlHijjah'
                      ]
                    : [
                        'January',
                        'February',
                        'March',
                        'April',
                        'May',
                        'June',
                        'July',
                        'August',
                        'September',
                        'October',
                        'November',
                        'December'
                      ])
            .map(txt)
            .toList();
        values = chartsCtrl.monthOfYearDistribution;
    }
    return _card(
        'patterns',
        txt('insightsDistribution'),
        txt('distributionOfAppointments'),
        labels,
        [values],
        [txt('appointments')],
        dimensionLabel: txt(keys[pattern]),
        chart: StyledBarChart(labels: labels, yAxis: values),
        controls: ComboBox<int>(
          value: pattern,
          items: [
            for (final (index, key) in keys.indexed)
              ComboBoxItem(value: index, child: Txt(txt(key)))
          ],
          onChanged: (value) {
            if (value != null) setState(() => pattern = value);
          },
        ));
  }

  Widget _donut(InsightsData data) {
    final values = [data.female.toDouble(), data.male.toDouble()];
    final total = data.female + data.male;
    if (total == 0) return const ChartEmptyState();
    final colors = [insightColors[3], insightColors[0]];
    final theme = FluentTheme.of(context);
    final base = theme.resources.solidBackgroundFillColorBase;
    return LayoutBuilder(builder: (context, constraints) {
      final radius = constraints.biggest.shortestSide / 2.5;
      return Stack(alignment: Alignment.center, children: [
        Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: base,
              boxShadow: [
                BoxShadow(
                    color: colors.first.withValues(alpha: 0.2),
                    blurRadius: 26,
                    spreadRadius: 2),
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 8,
                    offset: const Offset(0, 9)),
              ],
            )),
        PieChart(PieChartData(
          centerSpaceRadius: radius * 0.68,
          sectionsSpace: 4,
          sections: [
            for (var index = 0; index < values.length; index++)
              PieChartSectionData(
                value: values[index],
                gradient: insightStroke(colors[index]),
                radius: radius * 0.32,
                borderSide: BorderSide(
                    color:
                        insightHighlight(colors[index]).withValues(alpha: 0.6),
                    width: 1),
                title: '${(values[index] / total * 100).round()}%',
                titlePositionPercentageOffset: 0.5,
                titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              )
          ],
        )),
        Container(
            width: radius * 1.25,
            height: radius * 1.25,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                        colors.first.withValues(alpha: 0.08), base),
                    base
                  ]),
              border: Border.all(color: colors.first.withValues(alpha: 0.12)),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$total',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1)),
              Txt(txt('patients'), style: theme.typography.caption),
            ])),
        Positioned(
            bottom: 0,
            child: Wrap(spacing: 16, children: [
              for (var index = 0; index < values.length; index++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FluentIcons.circle_fill, size: 8, color: colors[index]),
                  const SizedBox(width: 6),
                  Txt('${txt(index == 0 ? 'female' : 'male')}: ${values[index].toInt()}'),
                ]),
            ])),
      ]);
    });
  }
}
