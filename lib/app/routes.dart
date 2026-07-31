import 'dart:async';
import 'dart:convert';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/dicom/dicom_screen.dart';
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
import 'package:apexo/services/perm.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/localization/locale.dart';
import 'package:apexo/features/appointments/calendar_screen.dart';
import 'package:apexo/features/settings/settings_screen.dart';
import '../core/observable.dart';
import "../features/appointments/appointments_store.dart";
import "../features/archive/archive_screen.dart";
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
  final String singularName;
  final String unicodeSymbol;
  String? title;
  final inProgress = ObservableState(false);
  final selectedTab = ObservableState<int>(0);
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);
  late String savedJson;
  late String identifier;
  final Completer<T> result = Completer<T>();
  final int creationDate = DateTime.now().millisecondsSinceEpoch;
  final bool inherentlyScrollable;
  final bool showTitles;
  final bool showBottomControls;
  final bool canNotBeNew;
  final Widget? additionalControls;
  final Widget? archiveButtonReplacement;

  /// If provided, used by the periodic timer instead of comparing
  /// [item.toJson] against [savedJson]. Useful when the panel manages
  /// multiple items (e.g. expenses orders panel).
  final bool Function()? checkUnsavedChanges;

  /// If provided, called when the Save button is pressed instead of the
  /// default [store.set(item)]. Useful when the panel manages multiple items.
  final void Function()? onSave;

  Panel({
    required this.item,
    required this.store,
    required this.tabs,
    required this.icon,
    required this.singularName,
    required this.unicodeSymbol,
    this.inherentlyScrollable = false,
    this.showTitles = false,
    this.title,
    this.showBottomControls = true,
    int? selectedTabIndex,
    this.canNotBeNew = false,
    this.additionalControls,
    this.archiveButtonReplacement,
    this.checkUnsavedChanges,
    this.onSave,
  }) {
    identifier = store.get(item.id) == null
        ? (canNotBeNew ? item.id : "new+${store.local?.name ?? singularName}")
        : item.id;
    savedJson = jsonEncode(item.toJson());
    selectedTab(selectedTabIndex);
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

  final minimizePanels = ObservableState(false);

  void openPanel(Panel panel) {
    final foundPanel = panels()
        .indexWhere((element) => element.identifier == panel.identifier);
    if (foundPanel > -1) {
      panels()[foundPanel].selectedTab(panel.selectedTab());
      bringPanelToFront(foundPanel);
    } else {
      panels(panels()..add(panel));
      routes.minimizePanels(false);
    }
  }

  void bringPanelToFront(int index) {
    panels(panels()..add(panels().removeAt(index)));
    routes.minimizePanels(false);
  }

  void closePanel(String targetToClose) {
    panels(panels()
      ..removeWhere(
          (p) => p.item.id == targetToClose || targetToClose == p.identifier));
  }

  final showBottomNav = ObservableState(false);

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
        if (login.perm(Perm.patients).some || login.isAdmin)
          Route(
            title: txt("patients"),
            identifier: "patients",
            navbarTitle: txt("patients"),
            icon: FluentIcons.medication_admin,
            screen: PatientsScreen.new,
            accessible: login.perm(Perm.patients).some || login.isAdmin,
            onSelect: () async {
              await accounts.reloadFromRemote();
              await patients.synchronize();
              appointments.synchronize();
            },
          ),
        if (login.perm(Perm.appointments).some || login.isAdmin)
          Route(
            title: txt("appointments"),
            identifier: "calendar",
            navbarTitle: txt("calendar"),
            icon: WindowsIcons.calendar,
            screen: CalendarScreen.new,
            accessible: login.perm(Perm.appointments).some || login.isAdmin,
            onSelect: () async {
              if (login.perm(Perm.appointments).not(2)) {
                appointments.filterByOperatorID(login.currentAccountID);
              }
              await accounts.reloadFromRemote();
              await patients.synchronize();
              appointments.synchronize();
            },
          ),
        if (login.perm(Perm.appointments).some || login.isAdmin)
          Route(
            title: txt("labworks"),
            identifier: "labworks",
            navbarTitle: txt("labworks"),
            icon: FluentIcons.manufacturing,
            screen: LabworksScreen.new,
            accessible: login.perm(Perm.appointments).some || login.isAdmin,
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
        if (login.perm(Perm.expenses).some || login.isAdmin)
          Route(
            title: txt("expenses"),
            identifier: "expenses",
            navbarTitle: txt("expenses"),
            icon: FluentIcons.receipt_processing,
            screen: ExpensesScreen.new,
            accessible: login.perm(Perm.expenses).some || login.isAdmin,
            onSelect: () async {
              await accounts.reloadFromRemote();
              await patients.synchronize();
              expenses.synchronize();
            },
          ),
        if (login.perm(Perm.stats).some || login.isAdmin)
          Route(
            title: txt("insights"),
            identifier: "insights",
            navbarTitle: txt("insights"),
            icon: FluentIcons.chart,
            screen: StatsScreen.new,
            accessible: login.perm(Perm.stats).some || login.isAdmin,
            onSelect: () async {
              chartsCtrl.resetSelected();
              if (login.perm(Perm.appointments).not(2) ||
                  login.perm(Perm.stats).not(2)) {
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
            navbarTitle: txt("accounts"),
            icon: FluentIcons.people,
            screen: AccountsScreen.new,
            accessible: login.isAdmin,
            onSelect: () {},
          ),
        Route(
          title: txt("deletedItems"),
          identifier: "deletedItems",
          navbarTitle: txt("deletedItems"),
          icon: WindowsIcons.delete,
          screen: ArchivedScreen.new,
          accessible: true,
          onSelect: () {
            patients.synchronize();
            appointments.synchronize();
            expenses.synchronize();
            notes.synchronize();
          },
        ),
        // Windows-only DICOM import route. Gated on the current
        // platform + photos permission (or admin). onSelect triggers a scan
        // so the pending list is fresh when the dentist opens the screen.
        if (DicomController.isSupported &&
            (login.perm(Perm.photos).some || login.isAdmin))
          Route(
            title: txt("xrayLink"),
            identifier: "dicom",
            navbarTitle: txt("xrayLink"),
            icon: FluentIcons.generic_scan,
            screen: DicomScreen.new,
            accessible: true,
            onSelect: () {
              dicomCtrl.refresh();
            },
          ),
        Route(
          title: txt("settings"),
          identifier: "settings",
          navbarTitle: txt("settings"),
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
