import 'dart:async';
import 'dart:convert';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/dashboard/dashboard_screen.dart';
import 'package:apexo/features/expenses/expenses_screen.dart';
import 'package:apexo/features/labwork/labworks_screen.dart';
import 'package:apexo/features/patients/patients_screen.dart';
import 'package:apexo/features/stats/screen_stats.dart';
import 'package:apexo/services/admins.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/permissions.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/doctors/doctors_store.dart';
import 'package:apexo/services/users.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/localization/locale.dart';
import 'package:apexo/features/appointments/calendar_screen.dart';
import 'package:apexo/features/doctors/doctors_screen.dart';
import 'package:apexo/features/settings/settings_screen.dart';
import '../core/observable.dart';
import "../features/appointments/appointments_store.dart";
import "../features/settings/settings_stores.dart";

class PanelTab {
  final String title;
  final IconData icon;
  final Widget body;
  final double padding;
  final bool onlyIfSaved;
  final Widget? footer;
  PanelTab({
    required this.title,
    required this.icon,
    required this.body,
    this.footer,
    this.onlyIfSaved = false,
    this.padding = 10,
  });
}

class Panel<T extends Model> {
  final T item;
  final Store store;
  final List<PanelTab> tabs;
  final IconData icon;
  String? title;
  final inProgress = ObservableState(false);
  final selectedTab = ObservableState<int>(0);
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);
  late String savedJson;
  late String identifier;
  final Completer<T> result = Completer<T>();
  final int creationDate = DateTime.now().millisecondsSinceEpoch;
  Panel({
    required this.item,
    required this.store,
    required this.tabs,
    required this.icon,
    this.title,
  }) {
    identifier = store.get(item.id) == null ? "new+${store.local?.name}" : item.id;
    savedJson = jsonEncode(item.toJson());
  }

  String get storeSingularName {
    return store.local!.name.substring(0, store.local!.name.length - 1);
  }
}

class Route {
  IconData icon;
  String title;
  String identifier;
  Widget Function() screen;
  String navbarTitle;

  /// show in the navigation pane and thus being activated
  bool accessible;

  /// show in the footer of the navigation pane
  bool onFooter;

  /// callback to be called when the route is selected
  void Function()? onSelect;

  Route({
    required this.title,
    required this.identifier,
    required this.icon,
    required this.screen,
    this.navbarTitle = "",
    this.accessible = true,
    this.onFooter = false,
    this.onSelect,
  });
}

class _Routes {
  final ObservableState<List<Panel>> panels = ObservableState([]);
  final minimizePanels = ObservableState(false);

  void openPanel(Panel panel) {
    final foundPanel = panels().indexWhere((element) => element.identifier == panel.identifier);
    if (foundPanel > -1) {
      // bring to front
      bringPanelToFront(foundPanel);
    } else {
      // add to end
      panels(panels()..add(panel));
      routes.minimizePanels(false);
    }
  }

  void bringPanelToFront(int index) {
    panels(panels()..add(panels().removeAt(index)));
    routes.minimizePanels(false);
  }

  List<Route> genAllRoutes() => [
        Route(
          title: txt("dashboard"),
          identifier: "dashboard",
          icon: FluentIcons.home,
          screen: DashboardScreen.new,
          accessible: true,
          navbarTitle: txt("home"),
          onSelect: () {
            chartsCtrl.resetSelected();
            patients.synchronize();
            appointments.synchronize();
          },
        ),
        Route(
          title: txt("doctors"),
          identifier: "doctors",
          icon: FluentIcons.medical,
          screen: DoctorsScreen.new,
          accessible: permissions.list[0] || login.isAdmin,
          onSelect: () async {
            await doctors.synchronize();
            await patients.synchronize();
            appointments.synchronize();
          },
        ),
        Route(
          title: txt("patients"),
          identifier: "patients",
          navbarTitle: txt("patients"),
          icon: FluentIcons.medication_admin,
          screen: PatientsScreen.new,
          accessible: permissions.list[1] || login.isAdmin,
          onSelect: () async {
            await doctors.synchronize();
            await patients.synchronize();
            appointments.synchronize();
          },
        ),
        Route(
          title: txt("appointments"),
          identifier: "calendar",
          navbarTitle: txt("calendar"),
          icon: FluentIcons.calendar,
          screen: CalendarScreen.new,
          accessible: permissions.list[2] || login.isAdmin,
          onSelect: () async {
            await doctors.synchronize();
            await patients.synchronize();
            appointments.synchronize();
          },
        ),
        Route(
          title: txt("labworks"),
          identifier: "labworks",
          navbarTitle: txt("labworks"),
          icon: FluentIcons.manufacturing,
          screen: LabworksScreen.new,
          accessible: permissions.list[3] || login.isAdmin,
          onSelect: () async {
            await doctors.synchronize();
            await patients.synchronize();
            await appointments.synchronize();
          },
        ),
        Route(
          title: txt("expenses"),
          identifier: "expenses",
          navbarTitle: txt("expenses"),
          icon: FluentIcons.receipt_processing,
          screen: ExpensesScreen.new,
          accessible: permissions.list[4] || login.isAdmin,
          onSelect: () async {
            await doctors.synchronize();
            await patients.synchronize();
            expenses.synchronize();
          },
        ),
        Route(
          title: txt("statistics"),
          identifier: "statistics",
          icon: FluentIcons.chart,
          screen: StatsScreen.new,
          accessible: permissions.list[5] || login.isAdmin,
          onSelect: () async {
            chartsCtrl.resetSelected();
            await doctors.synchronize();
            await patients.synchronize();
            appointments.synchronize();
          },
        ),
        Route(
          title: txt("settings"),
          identifier: "settings",
          icon: FluentIcons.settings,
          screen: SettingsScreen.new,
          accessible: true,
          onFooter: false,
          onSelect: () {
            globalSettings.synchronize();
            admins.reloadFromRemote();
            backups.reloadFromRemote();
            permissions.reloadFromRemote();
            users.reloadFromRemote();
          },
        ),
      ];

  late List<Route> allRoutes = genAllRoutes();
  final showBottomNav = ObservableState(false);
  final bottomNavFlyoutController = FlyoutController();
  final currentRouteIndex = ObservableState(0);
  List<int> history = [];

  int selectedTabInSheet = 0;

  Route get currentRoute {
    if (currentRouteIndex() < 0 || currentRouteIndex() >= allRoutes.length) {
      return allRoutes.first;
    }
    return allRoutes[currentRouteIndex()];
  }

  closePanel(String itemId) {
    panels(panels()..removeWhere((p) => p.item.id == itemId));
  }

  goBack() {
    if (history.isNotEmpty) {
      currentRouteIndex(history.removeLast());
      if (currentRoute.onSelect != null) {
        currentRoute.onSelect!();
      }
    }
  }

  navigate(Route route) {
    if (currentRouteIndex() == allRoutes.indexOf(route)) return;
    history.add(currentRouteIndex());
    currentRouteIndex(allRoutes.indexOf(route));
    if (currentRoute.onSelect != null) {
      currentRoute.onSelect!();
    }
  }

  Route? getByIdentifier(String identifier) {
    var target = allRoutes.where((element) => element.identifier == identifier);
    if (target.isEmpty) return null;
    return target.first;
  }
}

final routes = _Routes();
