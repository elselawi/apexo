import 'dart:async';

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Whether [route] may be opened in this session.
///
/// The one place the catalog's requirements are checked against the session:
/// [AppRoute] declares them, this decides them.
bool _accessible(AppRoute route) {
  if (route.windowsOnly && !DicomController.isSupported) return false;
  if (route.adminOnly) return login.isAdmin;
  final int? requiredPerm = route.perm;
  if (requiredPerm != null) {
    return login.perm(requiredPerm).some || login.isAdmin;
  }
  return true;
}

/// The screens the shell can show, and the little state the navbar itself
/// needs.
///
/// Panels are not among those screens: they float above the routes, and the
/// stack they live on belongs to [PanelsManager] — which is why nothing here
/// mentions them.
class AppRouter {
  /// The route on screen.
  ///
  /// The route itself is stored, not an index into a permission-filtered list,
  /// so nothing can drift when the session's permissions change.
  final currentRoute = ObservableState<AppRoute>(AppRoute.dashboard);

  final showBottomNav = ObservableState(false);

  final List<AppRoute> _history = [];

  /// The routes this session may open, in catalog order.
  List<AppRoute> get visibleRoutes => [
        for (final route in AppRoute.values)
          if (_accessible(route)) route
      ];

  /// Where [currentRoute] sits in [visibleRoutes] — the navigation pane's
  /// selection.
  ///
  /// Falls back to the first route when the current one is no longer offered
  /// (a permission change while it is open), which is the screen the shell drew
  /// for that state before.
  int get currentIndex {
    final int index = visibleRoutes.indexOf(currentRoute());
    return index == -1 ? 0 : index;
  }

  bool get canGoBack => _history.isNotEmpty;

  void navigate(AppRoute target) {
    if (target == currentRoute() || !_accessible(target)) return;
    _history.add(currentRoute());
    currentRoute(target);
    unawaited(_syncStores(target));
  }

  void goBack() {
    if (_history.isEmpty) return;
    final AppRoute target = _history.removeLast();
    currentRoute(target);
    unawaited(_syncStores(target));
  }

  void reset() {
    currentRoute(AppRoute.dashboard);
    _history.clear();
  }

  /// Puts [target] on screen with somewhere to go back to, **without** running
  /// [_syncStores].
  ///
  /// [navigate] deliberately refreshes the stores on the way, which a unit test
  /// neither wants nor can wait for — this is the seam that lets one observe
  /// [reset] clearing real state. Production always goes through [navigate].
  @visibleForTesting
  void navigateWithoutSync(AppRoute target) {
    _history.add(currentRoute());
    currentRoute(target);
  }
}

final routes = AppRouter();

/// What a route change refreshes.
///
/// One switch beside the router, rather than a closure buried in each route's
/// own data. It mirrors the old `onSelect` closures exactly — `await` where they
/// awaited, `unawaited(...)` where they fired and forgot.
Future<void> _syncStores(AppRoute route) async {
  switch (route) {
    case AppRoute.dashboard:
      chartsCtrl.resetSelected();
      unawaited(patients.synchronize());
      unawaited(appointments.synchronize());

    case AppRoute.patients:
      await accounts.reloadFromRemote();
      await patients.synchronize();
      unawaited(appointments.synchronize());

    case AppRoute.calendar:
      if (login.perm(Perm.appointments).not(2)) {
        appointments.filterByOperatorID(login.currentAccountID);
      }
      await accounts.reloadFromRemote();
      await patients.synchronize();
      unawaited(appointments.synchronize());

    case AppRoute.labworks:
      await accounts.reloadFromRemote();
      await patients.synchronize();
      await appointments.synchronize();

    case AppRoute.notes:
      await accounts.reloadFromRemote();
      await patients.synchronize();
      await appointments.synchronize();
      await notes.synchronize();

    case AppRoute.expenses:
      await accounts.reloadFromRemote();
      await patients.synchronize();
      unawaited(expenses.synchronize());

    case AppRoute.insights:
      chartsCtrl.resetSelected();
      if (login.perm(Perm.appointments).not(2) ||
          login.perm(Perm.stats).not(2)) {
        chartsCtrl.filterByOperatorID(login.currentAccountID);
      }
      await accounts.reloadFromRemote();
      await patients.synchronize();
      unawaited(appointments.synchronize());

    case AppRoute.deletedItems:
      unawaited(patients.synchronize());
      unawaited(appointments.synchronize());
      unawaited(expenses.synchronize());
      unawaited(notes.synchronize());

    case AppRoute.dicom:
      unawaited(dicomCtrl.refresh());

    case AppRoute.settings:
      unawaited(globalSettings.synchronize());
      unawaited(backups.reloadFromRemote());
      unawaited(accounts.reloadFromRemote());

    case AppRoute.accounts:
      break;
  }
}
