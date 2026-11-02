import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/stats/widgets/insights_dashboard.dart';
import 'package:apexo/features/stats/widgets/range_selector.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/clip.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
      const Expanded(child: InsightsDashboard()),
    ]);
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
                if (!fitsInCodePoints(name, 17)) {
                  name = "${clipCodePoints(name, 14)}...";
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
