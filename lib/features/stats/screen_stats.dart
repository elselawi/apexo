import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/stats/widgets/charts/bar.dart';
import 'package:apexo/features/stats/widgets/charts/line.dart';
import 'package:apexo/features/stats/widgets/charts/pie.dart';
import 'package:apexo/features/stats/widgets/charts/radar.dart';
import 'package:apexo/features/stats/widgets/charts/stacked.dart';
import 'package:apexo/features/stats/widgets/range_selector.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  final List<IconData> _icons = const [
    WindowsIcons.calendar_day,
    WindowsIcons.calendar_week,
    WindowsIcons.calendar,
    WindowsIcons.calendar,
    WindowsIcons.calendar,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(context),
      ChartsRangeSelector(
          color: FluentTheme.of(context).inactiveColor.withValues(alpha: 0.5),
          textStyle: _textStyle.copyWith(
              color:
                  FluentTheme.of(context).inactiveColor.withValues(alpha: 0.5)),
          icons: _icons),
      Container(
        decoration: topBarDecoration(context, Colors.grey),
        child: Padding(
          padding: const EdgeInsets.only(top: 0, bottom: 10, left: 8, right: 8),
          child: StreamBuilder(
              stream: chartsCtrl.interval.stream,
              builder: (context, asyncSnapshot) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 2,
                  children: [
                    ToggleButton(
                        checked: chartsCtrl.interval() == StatsInterval.days,
                        onChanged: (_) => chartsCtrl.setIntervalToDays(),
                        child: Txt(
                          txt("days"),
                          style: const TextStyle(fontSize: 13),
                        )),
                    ToggleButton(
                        checked: chartsCtrl.interval() == StatsInterval.weeks,
                        onChanged: (_) => chartsCtrl.setIntervalToWeeks(),
                        child: Txt(
                          txt("weeks"),
                          style: const TextStyle(fontSize: 13),
                        )),
                    ToggleButton(
                        checked: chartsCtrl.interval() == StatsInterval.months,
                        onChanged: (_) => chartsCtrl.setIntervalToMonths(),
                        child: Txt(
                          txt("months"),
                          style: const TextStyle(fontSize: 13),
                        )),
                    ToggleButton(
                        checked:
                            chartsCtrl.interval() == StatsInterval.quarters,
                        onChanged: (_) => chartsCtrl.setIntervalToQuarters(),
                        child: Txt(
                          txt("quarters"),
                          style: const TextStyle(fontSize: 13),
                        )),
                    ToggleButton(
                        checked: chartsCtrl.interval() == StatsInterval.years,
                        onChanged: (_) => chartsCtrl.setIntervalToYears(),
                        child: Txt(
                          txt("years"),
                          style: const TextStyle(fontSize: 13),
                        )),
                  ],
                );
              }),
        ),
      ),
      Expanded(
        child: MStreamBuilder(
            streams: [
              chartsCtrl.start.stream,
              chartsCtrl.end.stream,
              chartsCtrl.interval.stream,
              chartsCtrl.filterByOperatorID.stream,
              appointments.observableMap.stream,
              expenses.observableMap.stream,
            ],
            builder: (context, snapshot) {
              return LayoutBuilder(builder: (context, constraints) {
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 750,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 0,
                    mainAxisSpacing: 0,
                  ),
                  itemCount: 9,
                  padding: const EdgeInsets.all(0),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildSingleChart(
                        "${txt("appointmentsPer")} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        "${txt("total")}: ${chartsCtrl.filteredAppointments.length} ${txt("appointments")} ${txt("in_Duration_")} ${chartsCtrl.periods.length} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        StyledBarChart(
                          labels:
                              chartsCtrl.periods.map((p) => p.label).toList(),
                          yAxis: chartsCtrl.groupedAppointments
                              .map((g) => g.length.toDouble())
                              .toList(),
                        ),
                        constraints.maxWidth,
                        context,
                        FluentIcons.date_time,
                      );
                    }
                    if (index == 1 && login.perm(Perm.revenue).read) {
                      return _buildSingleChart(
                        "${txt("paymentsAndExpensesPer")} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        "${txt("total")}: ${txt("payments")} ${formatMoneyInText(chartsCtrl.groupedPayments.reduce((v, e) => v += e).toStringAsFixed(2))} ${currency()}\n${txt("expenses")} ${formatMoneyInText(chartsCtrl.groupedExpenses.reduce((v, e) => v += e).toStringAsFixed(2))} ${currency()} ${txt("in_Duration_")} ${chartsCtrl.periods.length} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        StyledLineChart(
                          labels:
                              chartsCtrl.periods.map((p) => p.label).toList(),
                          datasets: [
                            chartsCtrl.groupedPayments.toList(),
                            chartsCtrl.groupedExpenses.toList()
                          ],
                          datasetLabels: [
                            "${txt("payments")} ${currency()}",
                            "${txt("expenses")} ${currency()}"
                          ],
                        ),
                        constraints.maxWidth,
                        context,
                        FluentIcons.currency,
                      );
                    }
                    if (index == 2) {
                      return _buildSingleChart(
                        "${txt("newPatientsPer")} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        "${txt("acquiredPatientsIn")} ${chartsCtrl.periods.length} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        StyledLineChart(
                          labels:
                              chartsCtrl.periods.map((p) => p.label).toList(),
                          datasets: [chartsCtrl.newPatients.toList()],
                          datasetLabels: [txt("patients")],
                        ),
                        constraints.maxWidth,
                        context,
                        FluentIcons.people,
                      );
                    }
                    if (index == 3) {
                      return _buildSingleChart(
                        "${txt("doneMissedPer")} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        "${txt("doneAndMissedAppointmentsIn")} ${chartsCtrl.periods.length} ${txt(chartsCtrl.intervalString.toLowerCase())}",
                        StyledStackedChart(
                          labels:
                              chartsCtrl.periods.map((p) => p.label).toList(),
                          datasets: chartsCtrl.doneAndMissedAppointments,
                          datasetLabels: [txt("done"), txt("all")],
                        ),
                        constraints.maxWidth,
                        context,
                        FluentIcons.check_list,
                      );
                    }
                    if (index == 4) {
                      return _buildSingleChart(
                        txt("timeOfDay"),
                        txt("distributionOfAppointments"),
                        StyledRadarChart(
                          data: [chartsCtrl.timeOfDayDistribution],
                          labels: List.generate(
                              24,
                              (index) => DateFormat("hh a", locale.s.$code)
                                  .format(DateTime(0, 0, 0, index))),
                        ),
                        constraints.maxWidth,
                        context,
                        FluentIcons.clock,
                      );
                    }
                    if (index == 5) {
                      return _buildSingleChart(
                        txt("dayOfWeek"),
                        txt("distributionOfAppointments"),
                        StyledRadarChart(
                          data: [chartsCtrl.dayOfWeekDistribution],
                          labels: [
                            "Monday",
                            "Tuesday",
                            "Wednesday",
                            "Thursday",
                            "Friday",
                            "Saturday",
                            "Sunday"
                          ].map((e) => txt(e)).toList(),
                        ),
                        constraints.maxWidth,
                        context,
                        WindowsIcons.calendar_day,
                      );
                    }
                    if (index == 6) {
                      return _buildSingleChart(
                        txt("dayOfMonth"),
                        txt("distributionOfAppointments"),
                        StyledRadarChart(
                            data: [chartsCtrl.dayOfMonthDistribution],
                            labels: List.generate(
                                31, (index) => (index + 1).toString())),
                        constraints.maxWidth,
                        context,
                        WindowsIcons.calendar_day,
                      );
                    }
                    if (index == 7) {
                      return _buildSingleChart(
                        txt("monthOfYear"),
                        txt("distributionOfAppointments"),
                        StyledRadarChart(
                          data: [chartsCtrl.monthOfYearDistribution],
                          labels: DF.isPersianCalendar
                              ? [
                                  txt("farvardin"),
                                  txt("ordibehesht"),
                                  txt("khordad"),
                                  txt("tir"),
                                  txt("mordad"),
                                  txt("shahrivar"),
                                  txt("mehr"),
                                  txt("aban"),
                                  txt("azar"),
                                  txt("dey"),
                                  txt("bahman"),
                                  txt("esfand"),
                                ]
                              : const [
                                  "January",
                                  "February",
                                  "March",
                                  "April",
                                  "May",
                                  "June",
                                  "July",
                                  "August",
                                  "September",
                                  "October",
                                  "November",
                                  "December"
                                ].map((e) => txt(e)).toList(),
                        ),
                        constraints.maxWidth,
                        context,
                        WindowsIcons.calendar,
                      );
                    }
                    if (index == 8) {
                      return _buildSingleChart(
                        txt("patientsGender"),
                        txt("maleAndFemalePatients"),
                        StyledPie(data: {
                          txt("female"): chartsCtrl.femaleMale[0].toDouble(),
                          txt("male"): chartsCtrl.femaleMale[1].toDouble(),
                        }),
                        constraints.maxWidth,
                        context,
                        FluentIcons.people_external_share,
                      );
                    }

                    return const SizedBox();
                  },
                );
              });
            }),
      ),
    ]);
  }

  Widget _buildSingleChart(String title, String subtitle, Widget chart,
      double parentWidth, BuildContext context,
      [IconData icon = FluentIcons.chart]) {
    return Container(
      width: (parentWidth > 500 ? parentWidth / 2 : parentWidth) - 20,
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
        border: BorderDirectional(
          bottom: BorderSide(
              color:
                  FluentTheme.of(context).resources.dividerStrokeColorDefault),
          end: BorderSide(
              color:
                  FluentTheme.of(context).resources.dividerStrokeColorDefault),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 10, 7),
            child: Row(
              spacing: 5,
              children: [
                Icon(icon),
                const Divider(size: 20, direction: Axis.vertical),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(
                      title,
                      style: FluentTheme.of(context).typography.bodyLarge,
                    ),
                    Txt(
                      subtitle,
                      style: FluentTheme.of(context).typography.caption,
                    )
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: chart,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ScreenCommandBar(
        mainButton: _buildPickRangeButton(context),
        farItems: [_buildOperatorFilter()]);
  }

  Widget _buildOperatorFilter() {
    return StreamBuilder(
        stream: chartsCtrl.filterByOperatorID.stream,
        builder: (context, snapshot) {
          return ComboBox<String>(
            style: const TextStyle(overflow: TextOverflow.ellipsis),
            items: [
              ComboBoxItem<String>(
                value: "",
                child: Txt(txt("allDoctors")),
              ),
              ...accounts.operators.map((account) {
                var name = "🥼 ${accounts.name(account)}";
                if (name.length > 17) {
                  name = "${name.substring(0, 14)}...";
                }
                return ComboBoxItem(value: account.id, child: Txt(name));
              }),
            ],
            onChanged: (login.perm(Perm.appointments).not(2) ||
                    login.perm(Perm.stats).not(2))
                ? null
                : chartsCtrl.filterByOperator,
            value: chartsCtrl.filterByOperatorID(),
          );
        });
  }

  IconButton _buildPickRangeButton(BuildContext context) {
    return IconButton(
      icon: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(
            FluentIcons.public_calendar,
            size: 17,
          ),
          const SizedBox(width: 5),
          Txt(txt("pickRange"))
        ],
      ),
      onPressed: () => chartsCtrl.rangePicker(context),
    );
  }

  TextStyle get _textStyle => TextStyle(
        color: _color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      );

  Color get _color => Colors.grey.withValues(alpha: 0.5);
}
