import 'dart:async';

import 'package:apexo/app/optional_features.dart';
import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/common_widgets/current_account.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/booking/booking_labels.dart';
import 'package:apexo/features/booking/booking_request_details.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/dashboard/dashboard_controller.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/labwork/labworks_controller.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
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
    return MStreamBuilder(
        streams: [
          appointments.observableMap.stream,
          patients.observableMap.stream,
          expenses.observableMap.stream,
          booking.ready.stream,
          booking.requests.pending.stream,
          booking.requests.connected.stream,
          booking.requests.items.stream,
          booking.requests.lastSuccessfulAt.stream,
        ],
        builder: (context, asyncSnapshot) {
          return Column(
            key: WK.dashboardScreen,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _builCommandBar(context),
              _buildTopSquares(context),
              Container(
                height: 36,
                decoration: topBarDecoration(context),
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
              Expanded(
                child: LayoutBuilder(builder: (context, listConstraints) {
                  final height = listConstraints.maxHeight;
                  return ListView(scrollDirection: Axis.horizontal, children: [
                    if (login.perm(Perm.patients).some &&
                        login.perm(Perm.appointments).some)
                      _buildDashboardList(
                        context: context,
                        id: 'patientsToday',
                        icon: WindowsIcons.contact,
                        onPressed: () => routes.navigate(AppRoute.calendar),
                        height: height,
                        title: txt("patientsToday"),
                        items: dashboardCtrl.todayAppointments
                            .map((e) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onPressed: () {
                                    unawaited(openAppointment(e));
                                  },
                                  title: ItemTitle(item: e, maxWidth: 123),
                                  trailing: Text(DF.time(e.date)),
                                  subtitle: Text(
                                      "${e.subtitleLine1.isNotEmpty ? "${e.subtitleLine1}\n" : ""}${e.subtitleLine2}"),
                                ))
                            .toList(),
                      ),
                    if (login.perm(Perm.patients).some &&
                        login.perm(Perm.appointments).some)
                      _buildDashboardList(
                        context: context,
                        id: 'newPatientsTodayList',
                        height: height,
                        icon: WindowsIcons.calendar,
                        onPressed: () => routes.navigate(AppRoute.calendar),
                        title: txt("newPatientsToday"),
                        items: dashboardCtrl.newPatientsToday.map((e) {
                          final a = e.allAppointments.firstOrNull;
                          if (a == null) return const SizedBox.shrink();
                          return ListTile(
                            onPressed: () {
                              // Open the patient itself, not its windows, which
                              // would crowd a new record.
                              unawaited(openPatientRecord(e));
                            },
                            title: ItemTitle(item: e),
                            subtitle: Text(
                                "${a.subtitleLine1.isNotEmpty ? "${a.subtitleLine1}\n" : ""}${a.subtitleLine2}"),
                          );
                        }).toList(),
                      ),
                    if (login.perm(Perm.patients).some &&
                        login.perm(Perm.appointments).some)
                      _buildDashboardList(
                        context: context,
                        id: 'labworksDue',
                        height: height,
                        icon: FluentIcons.manufacturing,
                        onPressed: () => routes.navigate(AppRoute.labworks),
                        title: "${txt("labworks")} (${txt("due")})",
                        items: labworks.due
                            .map((e) => ListTile(
                                  // One row is one order: open its labwork window
                                  // rather than the patient's record, which would
                                  // bury it. Beside an open panel the visit's panel
                                  // takes it.
                                  onPressed: () => unawaited(
                                      openAppointmentWindowOnItsOwn(
                                          e, AppointmentWindow.labwork)),
                                  title: ItemTitle(item: e),
                                  subtitle: Txt(
                                      "${DateTime.now().difference(e.date).inDays} ${txt("daysAgo")}"),
                                ))
                            .toList(),
                      ),
                    if (login.perm(Perm.patients).some &&
                        login.perm(Perm.appointments).some)
                      _buildDashboardList(
                        context: context,
                        id: 'labworksUndelivered',
                        height: height,
                        icon: FluentIcons.manufacturing,
                        onPressed: () => routes.navigate(AppRoute.labworks),
                        title: "${txt("labworks")} (${txt("undelivered")})",
                        items: labworks.notDeliveredPatients.map((e) {
                          // The order belongs to the patient's latest visit, whose
                          // labwork window opens; an all-archived patient has none.
                          final visit = e.allAppointments.lastOrNull;
                          if (visit == null) {
                            return const SizedBox.shrink();
                          }
                          return ListTile(
                            onPressed: () => unawaited(
                                openAppointmentWindowOnItsOwn(
                                    visit, AppointmentWindow.labwork)),
                            title: ItemTitle(item: e),
                            subtitle: Txt(
                                "${DateTime.now().difference(e.doneAppointments.lastOrNull?.date ?? visit.date).inDays} ${txt("daysAgo")}"),
                          );
                        }).toList(),
                      ),
                    if (booking.ready())
                      _buildDashboardList(
                        context: context,
                        id: 'bookingRequests',
                        icon: WindowsIcons.calendar,
                        onPressed: () => routes.navigate(AppRoute.booking),
                        height: height,
                        title:
                            "${txt("bookingInbox")} (${booking.requests.connected() ? "${booking.requests.pending()}" : "—"})",
                        items: booking.requests.cache
                            .forFilter("pending")
                            .where((request) => !request.isExpired)
                            .take(20)
                            .map((request) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onPressed: () => unawaited(
                                      openBookingRequestPanel(
                                          context, request)),
                                  title: Text(request.name,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      bookingPreferenceLabel(request),
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                      ),
                    if (login.perm(Perm.expenses).some &&
                        expensesFeatureEnabled)
                      _buildDashboardList(
                        context: context,
                        id: 'expensesDue',
                        height: height,
                        icon: WindowsIcons.payment_card,
                        onPressed: () => routes.navigate(AppRoute.expenses),
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
                                    // Open the unpaid-orders list, not the supplier.
                                    unawaited(openExpenses(
                                      expenses.ordersPerSupplier[e.id]!,
                                      e.supplierName,
                                      e.id,
                                      null,
                                      ExpenseWindow.due,
                                    ));
                                  },
                                  subtitle:
                                      Text("${e.duePayments} ${currency()}"),
                                  leading: const Icon(WindowsIcons.folder),
                                ))
                            .toList(),
                      ),
                  ]);
                }),
              ),
            ],
          );
        });
  }

  Container _buildDashboardList({
    required BuildContext context,
    required String id,
    required double height,
    required String title,
    required List<Widget> items,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    const double colWidth = 265;

    return Container(
      key: WK.dashboardSquare(id),
      width: colWidth,
      height: 100,
      decoration: BoxDecoration(
        border: BorderDirectional(
          end: BorderSide(color: FluentMaterials.of(context).divider),
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
                        .copyWith(
                            backgroundColor: FluentTheme.of(context)
                                .resources
                                .textFillColorDisabled),
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
            style: FluentTheme.of(context).typography.bodyStrong!,
          ),
        ],
      ),
    );
  }

  SingleChildScrollView _buildTopSquares(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Row(
          children: [
            if (login.perm(Perm.appointments).some)
              dashboardSquare(
                context,
                'appointmentsToday',
                FluentIcons.goto_today,
                dashboardCtrl.todayAppointments.length.toString(),
                txt("appointmentsToday"),
              ),
            if (login.perm(Perm.patients).some)
              dashboardSquare(
                context,
                'newPatientsToday',
                FluentIcons.people,
                dashboardCtrl.newPatientsToday.length.toString(),
                txt("newPatientsToday"),
              ),
            if (login.perm(Perm.revenue).read)
              dashboardSquare(
                context,
                'paymentsToday',
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
    BuildContext context,
    String id,
    IconData icon,
    String title,
    String subtitle, [
    bool isMoney = false,
  ]) {
    return Padding(
      key: WK.dashboardSquare(id),
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
            color: FluentMaterials.of(context).glassTint,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: FluentMaterials.of(context).glassTint.withAlpha(16))),
        width: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Icon(
                    icon,
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
                          key: WK.dashboardCount(id),
                          title,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        Text(
                          title,
                          key: WK.dashboardCount(id),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      Txt(
                        subtitle,
                        style: const TextStyle(
                            fontSize: 13,
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
