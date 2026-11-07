import 'dart:async';

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/booking/booking_session.dart';
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

bool _accessible(AppRoute route) {
  if (route.windowsOnly && !DicomController.isSupported) return false;
  if (route == AppRoute.booking) return booking.ready();
  if (route.adminOnly) return login.isAdmin;
  final int? requiredPerm = route.perm;
  if (requiredPerm != null) {
    return login.perm(requiredPerm).some || login.isAdmin;
  }
  return true;
}

/// Panels are not routes: they float above them and `PanelsManager` owns their
/// stack.
class AppRouter {
  /// Stored as a route, not an index into the filtered list, so permissions
  /// changing cannot make it drift.
  final currentRoute = ObservableState<AppRoute>(AppRoute.dashboard);

  final showBottomNav = ObservableState(false);

  final List<AppRoute> _history = [];

  /// The routes this session may open, in catalog order.
  List<AppRoute> get visibleRoutes => [
        for (final route in AppRoute.values)
          if (_accessible(route)) route
      ];

  /// Falls back to the first route if permissions changed while it was open.
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
    final AppRoute previous = _history.removeLast();
    // Match the shell's currentIndex fallback if access changed in history.
    final AppRoute target =
        _accessible(previous) ? previous : visibleRoutes.first;
    currentRoute(target);
    unawaited(_syncStores(target));
  }

  void reset() {
    currentRoute(AppRoute.dashboard);
    _history.clear();
  }

  /// Test seam: pushes [target] without [_syncStores], which a unit test cannot
  /// wait for.
  @visibleForTesting
  void navigateWithoutSync(AppRoute target) {
    _history.add(currentRoute());
    currentRoute(target);
  }
}

final routes = AppRouter();

Future<void> _syncStores(AppRoute route) async {
  switch (route) {
    case AppRoute.dashboard:
      chartsCtrl.resetSelected();
      unawaited(patients.synchronize());
      unawaited(appointments.synchronize());
      unawaited(booking.requests.refresh(status: "pending"));

    case AppRoute.patients:
      await accounts.reloadFromRemote();
      await patients.synchronize();
      unawaited(appointments.synchronize());

    case AppRoute.booking:
      unawaited(booking.requests.refresh());

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
