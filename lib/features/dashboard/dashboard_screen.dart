import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/current_account.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String get mode {
    return login.isAdmin
        ? txt("modeAdmin")
        : network.isOnline()
            ? txt("modeUser")
            : txt("modeOffline");
  }

  String get dashboardMessage {
    final onceStable =
        network.isOnline() ? "" : " ${txt("onceConnectionIsStable")}.";

    final restriction = (login.isAdmin && network.isOnline())
        ? txt("unRestrictedAccess")
        : txt("restrictedAccess");

    return "${txt("youAreCurrentlyIn")} $mode. ${txt("youHave")} $restriction.$onceStable";
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight - 218;
      return MStreamBuilder(
          streams: [
            appointments.observableMap.stream,
            expenses.observableMap.stream,
            showArchived.stream
          ],
          builder: (context, asyncSnapshot) {
            return Column(
              key: WK.dashboardScreen,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _builCommandBar(context),
                _buildTopSquares(),
                Container(
                  decoration: topBarDecoration(context, Colors.grey),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Txt(
                          DF.full(DateTime.now()),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth,
                  height: height,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    if (login.permissions[PInt.patients] > 0 &&
                        login.permissions[PInt.appointments] > 0)
                      _buildDashboardList(
                        context: context,
                        icon: WindowsIcons.contact,
                        onPressed: () => routes.navigate("calendar"),
                        height: height,
                        title: txt("patientsToday"),
                        items: dashboardCtrl.todayAppointments
                            .map((e) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onPressed: () => openAppointment(e, 0),
                                  title: ItemTitle(item: e, maxWidth: 123),
                                  trailing: Text(DF.time(e.date)),
                                  subtitle: Text(
                                      "${e.subtitleLine1.isNotEmpty ? "${e.subtitleLine1}\n" : ""}${e.subtitleLine2}"),
                                ))
                            .toList(),
                      ),
                    if (login.permissions[PInt.patients] > 0 &&
                        login.permissions[PInt.appointments] > 0)
                      _buildDashboardList(
                        context: context,
                        height: height,
                        icon: WindowsIcons.calendar,
                        onPressed: () => routes.navigate("calendar"),
                        title: txt("newPatientsToday"),
                        items: dashboardCtrl.newPatientsToday.map((e) {
                          final a = e.allAppointments.first;
                          return ListTile(
                            onPressed: () => openPatient(e, 2),
                            title: ItemTitle(item: e),
                            subtitle: Text(
                                "${a.subtitleLine1.isNotEmpty ? "${a.subtitleLine1}\n" : ""}${a.subtitleLine2}"),
                          );
                        }).toList(),
                      ),
                    if (login.permissions[PInt.patients] > 0 &&
                        login.permissions[PInt.appointments] > 0)
                      _buildDashboardList(
                        context: context,
                        height: height,
                        icon: FluentIcons.manufacturing,
                        onPressed: () => routes.navigate("labworks"),
                        title: "${txt("labworks")} (${txt("due")})",
                        items: labworks.due
                            .map((e) => ListTile(
                                  onPressed: () => openPatient(e.patient, 2),
                                  title: ItemTitle(item: e),
                                  subtitle: Txt(
                                      "${DateTime.now().difference(e.date).inDays} ${txt("daysAgo")}"),
                                ))
                            .toList(),
                      ),
                    if (login.permissions[PInt.patients] > 0 &&
                        login.permissions[PInt.appointments] > 0)
                      _buildDashboardList(
                        context: context,
                        height: height,
                        icon: FluentIcons.manufacturing,
                        onPressed: () => routes.navigate("labworks"),
                        title: "${txt("labworks")} (${txt("undelivered")})",
                        items: labworks.notDeliveredPatients
                            .map((e) => ListTile(
                                  onPressed: () => openPatient(e, 2),
                                  title: ItemTitle(item: e),
                                  subtitle: Txt(
                                      "${DateTime.now().difference(e.doneAppointments.lastOrNull?.date ?? e.allAppointments.last.date).inDays} ${txt("daysAgo")}"),
                                ))
                            .toList(),
                      ),
                    if (login.permissions[PInt.expenses] > 0)
                      _buildDashboardList(
                        context: context,
                        height: height,
                        icon: WindowsIcons.payment_card,
                        onPressed: () => routes.navigate("expenses"),
                        title: "${txt("expenses")} (${txt("due")})",
                        items: expenses.suppliers
                            .where((x) => x.duePayments > 0)
                            .map((e) => ListTile(
                                  title: Text(
                                    e.supplierName,
                                    style: FluentTheme.of(context)
                                        .typography
                                        .bodyStrong,
                                  ),
                                  onPressed: () {
                                    openExpenses(
                                      expenses.ordersPerSupplier[e.id]!,
                                      e.supplierName,
                                      e.id,
                                    );
                                  },
                                  subtitle:
                                      Text("${e.duePayments} ${currency()}"),
                                  leading: const Icon(WindowsIcons.folder),
                                ))
                            .toList(),
                      ),
                  ]),
                ),
              ],
            );
          });
    });
  }

  Container _buildDashboardList({
    required BuildContext context,
    required double height,
    required String title,
    required List<Widget> items,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    const double colWidth = 265;

    return Container(
      width: colWidth,
      height: 100,
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
        border: BorderDirectional(
          end: BorderSide(
              color:
                  FluentTheme.of(context).inactiveColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: colWidth,
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Txt(
                  title,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                IconButton(
                  icon: Icon(icon),
                  onPressed: onPressed,
                )
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(5),
            height: height - 90,
            child: items.isEmpty
                ? Center(
                    child: Txt(
                    txt("noResultsFound"),
                    style: FluentTheme.of(context)
                        .typography
                        .bodyStrong!
                        .copyWith(backgroundColor: Colors.grey.withAlpha(40)),
                  ))
                : ListView(
                    scrollDirection: Axis.vertical,
                    children: items,
                  ),
          )
        ],
      ),
    );
  }

  Widget _builCommandBar(BuildContext context) {
    return ScreenCommandBar(
      mainButton: _topWelcomingText(context),
      otherButtons: [if (!launch.isDemo) const LogoutButton()],
    );
  }

  Tooltip _topWelcomingText(BuildContext context) {
    return Tooltip(
      message: dashboardMessage,
      child: Row(
        spacing: 10,
        children: [
          login.currentLoginIsOperator
              ? const Icon(FluentIcons.medical)
              : const Icon(FluentIcons.contact),
          Txt(
            "${"${txt("hello")},"} ${login.currentName}",
          ),
          Txt(
            mode,
            style: FluentTheme.of(context)
                .typography
                .caption!
                .copyWith(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  SingleChildScrollView _buildTopSquares() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Row(
          children: [
            if (login.permissions[PInt.appointments] > 0)
              dashboardSquare(
                Colors.purple,
                FluentIcons.goto_today,
                dashboardCtrl.todayAppointments.length.toString(),
                txt("appointmentsToday"),
              ),
            if (login.permissions[PInt.patients] > 0)
              dashboardSquare(
                Colors.blue,
                FluentIcons.people,
                dashboardCtrl.newPatientsToday.length.toString(),
                txt("newPatientsToday"),
              ),
            if (login.permissions[PInt.postOp] > 1)
              dashboardSquare(
                Colors.teal,
                WindowsIcons.payment_card,
                "${dashboardCtrl.paymentsToday.toStringAsFixed(2)} ${currency()}",
                txt("paymentsMadeToday"),
                true,
              ),
          ],
        ),
      ),
    );
  }

  Padding dashboardSquare(
      AccentColor color, IconData icon, String title, String subtitle,
      [bool isMoney = false]) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
            color: color.withAlpha(50),
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                offset: const Offset(0.0, 6.0),
                blurRadius: 15.0,
                spreadRadius: 5.0,
                color: color.withAlpha(50),
              )
            ]),
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
                      if (isMoney)
                        MoneyDisplay(
                          title,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: color.dark),
                        )
                      else
                        Text(
                          title,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: color.dark),
                        ),
                      Txt(
                        subtitle,
                        style: TextStyle(
                            fontSize: 13,
                            color: color.light,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 0.6),
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
    );
  }
}
