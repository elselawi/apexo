import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/features/stats/widgets/charts/bar.dart';
import 'package:apexo/features/stats/widgets/charts/line.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/permissions.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String get currentName {
    if (login.currentMember == null) return "";
    if (login.currentMember!.title.length > 20) return "${login.currentMember!.title.substring(0, 17)}...";
    return login.currentMember?.title ?? "";
  }

  String get mode {
    return login.isAdmin
        ? txt("modeAdmin")
        : network.isOnline()
            ? txt("modeUser")
            : txt("modeOffline");
  }

  String get dashboardMessage {
    final onceStable = network.isOnline() ? "" : " ${txt("onceConnectionIsStable")}.";

    final restriction = (login.isAdmin && network.isOnline()) ? txt("unRestrictedAccess") : txt("restrictedAccess");

    return "${txt("youAreCurrentlyIn")} $mode ${txt("mode")}. ${txt("youHave")} $restriction.$onceStable";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        key: WK.dashboardScreen,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(FluentIcons.medical),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Txt(
                          "${txt("hello")} $currentName",
                          style: const TextStyle(fontSize: 20),
                        ),
                        Txt(
                          DateFormat("MMMM d yyyy, hh:mm:a", locale.s.$code).format(DateTime.now()),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!launch.isDemo)
                  Tooltip(
                    message: dashboardMessage,
                    child: PaymentPill(
                      finalTextColor: login.isAdmin ? Colors.blue : Colors.warningPrimaryColor,
                      title: txt("mode"),
                      amount: mode,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          if (permissions.list[5] || login.isAdmin) ...[
            buildTopSquares(),
            buildDashboardCharts()
          ] else if (permissions.list[2] && dashboardCtrl.todayAppointments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 5, 15, 0),
              child: Txt(txt("patientsToday")),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: dashboardCtrl.todayAppointments.map((e) => ItemTitle(item: e)).toList(),
              ),
            )
          ]
        ],
      ),
    );
  }

  Expanded buildDashboardCharts() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        child: StreamBuilder(
            stream: dashboardCtrl.currentOpenTab.stream,
            builder: (context, snapshot) {
              return TabView(
                currentIndex: dashboardCtrl.currentOpenTab(),
                closeButtonVisibility: CloseButtonVisibilityMode.never,
                header: const SizedBox(width: 5),
                footer: IconButton(
                  icon: Row(
                    children: [const Icon(FluentIcons.chart), const SizedBox(width: 5), Txt(txt("fullStats"))],
                  ),
                  onPressed: () => routes.navigate(routes.getByIdentifier("statistics")!),
                ),
                onChanged: (i) => dashboardCtrl.currentOpenTab(i),
                tabs: [
                  Tab(
                    text: Txt(txt("appointments")),
                    icon: const Icon(FluentIcons.calendar),
                    closeIcon: null,
                    outlineColor: WidgetStatePropertyAll(Colors.grey.withValues(alpha: 0.1)),
                    body: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.4),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(children: [
                          Expanded(
                              child: StyledBarChart(
                            labels: chartsCtrl.periods.map((p) => p.label).toList(),
                            yAxis: chartsCtrl.groupedAppointments.map((g) => g.length.toDouble()).toList(),
                          ))
                        ]),
                      ),
                    ),
                  ),
                  Tab(
                    text: Txt(txt("payments")),
                    icon: const Icon(FluentIcons.money),
                    closeIcon: null,
                    outlineColor: WidgetStatePropertyAll(Colors.grey.withValues(alpha: 0.1)),
                    body: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.4),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
                        child: Column(children: [
                          Expanded(
                              child: StyledLineChart(
                            labels: chartsCtrl.periods.map((p) => p.label).toList(),
                            datasets: [chartsCtrl.groupedPayments.toList()],
                            datasetLabels: ["Payments in ${globalSettings.get("currency_______").value}"],
                          ))
                        ]),
                      ),
                    ),
                  ),
                ],
              );
            }),
      ),
    );
  }

  SingleChildScrollView buildTopSquares() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            dashboardSquare(
              Colors.purple,
              FluentIcons.goto_today,
              dashboardCtrl.todayAppointments.length.toString(),
              txt("appointmentsToday"),
            ),
            dashboardSquare(
              Colors.blue,
              FluentIcons.people,
              dashboardCtrl.newPatientsToday.toString(),
              txt("newPatientsToday"),
            ),
            dashboardSquare(
              Colors.teal,
              FluentIcons.money,
              dashboardCtrl.paymentsToday.toStringAsFixed(2),
              txt("paymentsMadeToday"),
            ),
          ],
        ),
      ),
    );
  }

  Padding dashboardSquare(AccentColor color, IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Acrylic(
        elevation: 50,
        luminosityAlpha: 1,
        blurAmount: 80,
        tintAlpha: 0.9,
        tint: color,
        shadowColor: color,
        child: SizedBox(
          width: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: color,
                    ),
                    ...const [
                      SizedBox(width: 10),
                      Divider(size: 40, direction: Axis.vertical),
                      SizedBox(width: 10),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Txt(
                          title,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color.dark),
                        ),
                        Txt(
                          subtitle,
                          style: TextStyle(
                              fontSize: 13, color: color.light, fontStyle: FontStyle.italic, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 10),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
