import 'dart:async';
import 'dart:convert';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/dashboard/dashboard_screen.dart';
import 'package:apexo/features/expenses/expenses_screen.dart';
import 'package:apexo/features/labwork/labworks_screen.dart';
import 'package:apexo/features/notes/notes_screen.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_screen.dart';
import 'package:apexo/features/stats/screen_stats.dart';
import 'package:apexo/features/accounts/accounts_screen.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/localization/locale.dart';
import 'package:apexo/features/appointments/calendar_screen.dart';
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
    identifier =
        store.get(item.id) == null ? "new+${store.local?.name}" : item.id;
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
  void Function() onSelect;

  Route({
    required this.title,
    required this.identifier,
    required this.icon,
    required this.screen,
    required this.onSelect,
    this.navbarTitle = "",
    this.accessible = true,
    this.onFooter = false,
  });
}

class _Routes {
  final ObservableState<List<Panel>> panels = ObservableState([]);

  /// Optional interceptor registered by a screen to handle the back action
  /// internally. Return [true] to let [goBack] proceed normally, or [false]
  /// if the interceptor fully handled the back action.
  bool Function()? onBackInterceptor;
  final minimizePanels = ObservableState(false);

  void openPanel(Panel panel) {
    final foundPanel = panels()
        .indexWhere((element) => element.identifier == panel.identifier);
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

  void closePanel(String itemId) {
    panels(panels()..removeWhere((p) => p.item.id == itemId));
  }

  final showBottomNav = ObservableState(false);
  final bottomNavFlyoutController = FlyoutController();

  List<Route> get allRoutes => [
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
        if (login.permissions[PInt.patients] > 0 || login.isAdmin)
          Route(
            title: txt("patients"),
            identifier: "patients",
            navbarTitle: txt("patients"),
            icon: FluentIcons.medication_admin,
            screen: PatientsScreen.new,
            accessible: login.permissions[PInt.patients] > 0 || login.isAdmin,
            onSelect: () async {
              await accounts.reloadFromRemote();
              await patients.synchronize();
              appointments.synchronize();
            },
          ),
        if (login.permissions[PInt.appointments] > 0 || login.isAdmin)
          Route(
            title: txt("appointments"),
            identifier: "calendar",
            navbarTitle: txt("calendar"),
            icon: WindowsIcons.calendar,
            screen: CalendarScreen.new,
            accessible:
                login.permissions[PInt.appointments] > 0 || login.isAdmin,
            onSelect: () async {
              if (login.permissions[PInt.appointments] != 2) {
                appointments.filterByOperatorID(login.currentAccountID);
              }
              await accounts.reloadFromRemote();
              await patients.synchronize();
              appointments.synchronize();
            },
          ),
        if (login.permissions[PInt.appointments] > 0 || login.isAdmin)
          Route(
            title: txt("labworks"),
            identifier: "labworks",
            navbarTitle: txt("labworks"),
            icon: FluentIcons.manufacturing,
            screen: LabworksScreen.new,
            accessible:
                login.permissions[PInt.appointments] > 0 || login.isAdmin,
            onSelect: () async {
              await accounts.reloadFromRemote();
              await patients.synchronize();
              await appointments.synchronize();
            },
          ),
        Route(
          title: txt("notes"),
          identifier: "notes",
          navbarTitle: txt("notes"),
          icon: WindowsIcons.quick_note,
          screen: NotesScreen.new,
          onSelect: () async {
            await accounts.reloadFromRemote();
            await patients.synchronize();
            await appointments.synchronize();
            await notes.synchronize();
          },
        ),
        if (login.permissions[PInt.expenses] > 0 || login.isAdmin)
          Route(
            title: txt("expenses"),
            identifier: "expenses",
            navbarTitle: txt("expenses"),
            icon: FluentIcons.receipt_processing,
            screen: ExpensesScreen.new,
            accessible: login.permissions[PInt.expenses] > 0 || login.isAdmin,
            onSelect: () async {
              await accounts.reloadFromRemote();
              await patients.synchronize();
              expenses.synchronize();
            },
          ),
        if (login.permissions[PInt.stats] > 0 || login.isAdmin)
          Route(
            title: txt("statistics"),
            identifier: "statistics",
            icon: FluentIcons.chart,
            screen: StatsScreen.new,
            accessible: login.permissions[PInt.stats] > 0 || login.isAdmin,
            onSelect: () async {
              chartsCtrl.resetSelected();
              if (login.permissions[PInt.appointments] != 2 ||
                  login.permissions[PInt.stats] != 2) {
                chartsCtrl.filterByOperatorID(login.currentAccountID);
              }
              await accounts.reloadFromRemote();
              await patients.synchronize();
              appointments.synchronize();
            },
          ),
        if (login.isAdmin)
          Route(
            title: txt("accounts"),
            identifier: "accounts",
            icon: FluentIcons.people,
            screen: AccountsScreen.new,
            accessible: login.isAdmin,
            navbarTitle: "",
            onSelect: () {},
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
            backups.reloadFromRemote();
            accounts.reloadFromRemote();
          },
        ),
      ];

  final currentRouteIndex = ObservableState(0);
  List<int> history = [];

  Route get currentRoute {
    if (currentRouteIndex() < 0 || currentRouteIndex() >= allRoutes.length) {
      return allRoutes.first;
    }
    return allRoutes[currentRouteIndex()];
  }

  void goBack() {
    if (onBackInterceptor != null) {
      final shouldProceed = onBackInterceptor!();
      if (!shouldProceed) return;
    }
    if (history.isNotEmpty) {
      currentRouteIndex(history.removeLast());
      currentRoute.onSelect();
    }
  }

  void navigate(String identifier) {
    if (currentRoute.identifier == identifier) return;
    final identifiedIndex =
        allRoutes.indexWhere((x) => x.identifier == identifier);
    if (identifiedIndex == -1) return;
    history.add(currentRouteIndex());
    currentRouteIndex(identifiedIndex);
    allRoutes[identifiedIndex].onSelect();
  }

  Route? getByIdentifier(String identifier) {
    var target = allRoutes.where((element) => element.identifier == identifier);
    if (target.isEmpty) return null;
    return target.first;
  }

  void reset() {
    currentRouteIndex(0);
    history = [];
  }
}

final routes = _Routes();
