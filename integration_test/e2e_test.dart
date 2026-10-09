import 'package:integration_test/integration_test.dart';
import 'groups/accessibility.dart';
import 'groups/accounts.dart';
import 'groups/ai_services.dart';
import 'groups/appointments.dart';
import 'groups/attachments.dart';
import 'groups/backups.dart';
import 'groups/calendar.dart';
import 'groups/dashboard.dart';
import 'groups/deleted_items.dart';
import 'groups/dicom.dart';
import 'groups/errors_and_recovery.dart';
import 'groups/expenses.dart';
import 'groups/insights.dart';
import 'groups/labworks.dart';
import 'groups/lifecycle_platform.dart';
import 'groups/localization_rtl.dart';
import 'groups/login.dart';
import 'groups/multi_clinic.dart';
import 'groups/notes.dart';
import 'groups/notifications.dart';
import 'groups/patient_panel.dart';
import 'groups/patient_portal.dart';
import 'groups/patients.dart';
import 'groups/perf_budgets.dart';
import 'groups/settings_general.dart';
import 'groups/settings_services.dart';
import 'groups/sync_offline.dart';
import 'groups/tooth_chart.dart';
import 'groups/upgrade.dart';
import 'support/e2e.dart';

/// The end-to-end suite — the file `flutter test` / `flutter drive` target.
///
/// ```bash
/// # a native window (or any connected device)
/// flutter test integration_test/e2e_test.dart -d windows
///
/// # a browser (needs chromedriver — see integration_test/readme.md)
/// flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/e2e_test.dart -d web-server
/// ```
///
/// `tools/run_e2e.ps1` runs either of those for you (it also passes the backend
/// credentials as dart-defines).
///
/// Run one group, or one test, with the standard filter:
///
/// ```bash
/// flutter test integration_test/e2e_test.dart -d windows --plain-name login
/// flutter test integration_test/e2e_test.dart -d windows --plain-name "04:"
/// ```
///
/// A web run takes a group name as a define instead (see `_onlyGroup`):
///
/// ```bash
/// flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/e2e_test.dart -d web-server \
///     --dart-define=E2E_GROUP=login
/// ```
///
/// Every test boots the app for itself with `E2E.boot` — a `testWidgets` starts
/// with an empty widget tree, there is no "boot once and share" in the standard
/// framework — and the backend/local-state reset happens once per run, on the
/// first boot.
/// A group selected by name, so a **web** run can be narrowed too.
///
/// `--plain-name` belongs to `flutter test` (native); `flutter drive` rejects it
/// and would otherwise always run every group. `tools/run_e2e.ps1 -Group login
/// -Target web` passes this define instead.
const _onlyGroup = String.fromEnvironment('E2E_GROUP');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Also installed per test by `E2E.boot`: the binding swaps its own
  // `FlutterError.onError` in around every test, and the fluent error this
  // filters for can land in the gap between two of them (see the method).
  E2E.installKnownFlutterIssueFilters();

  final groups = <String, void Function()>{
    'login': registerLoginTests,
    'patients': registerPatientsTests,
    'calendar': registerCalendarTests,
    'appointments': registerAppointmentsTests,
    'patient_panel': registerPatientPanelTests,
    'tooth_chart': registerToothChartTests,
    'patient_portal': registerPatientPortalTests,
    'accessibility': registerAccessibilityTests,
    'upgrade': registerUpgradeTests,
    'labworks': registerLabworksTests,
    'expenses': registerExpensesTests,
    'dashboard': registerDashboardTests,
    'notes': registerNotesTests,
    'attachments': registerAttachmentsTests,
    'insights': registerInsightsTests,
    'deleted_items': registerDeletedItemsTests,
    'accounts': registerAccountsTests,
    'settings_general': registerSettingsGeneralTests,
    'settings_services': registerSettingsServicesTests,
    'ai_services': registerAiServicesTests,
    'sync_offline': registerSyncOfflineTests,
    'backups': registerBackupsTests,
    'notifications': registerNotificationsTests,
    'multi_clinic': registerMultiClinicTests,
    'lifecycle_platform': registerLifecyclePlatformTests,
    'localization_rtl': registerLocalizationTests,
    'errors_and_recovery': registerErrorsAndRecoveryTests,
    // The X-ray link: native Windows only, so its tests skip elsewhere (§2.12).
    'dicom': registerDicomTests,
    // Scale and performance budgets (§4.4). Last in the order kept here: it seeds
    // a thousand patients into the clinic the suite shares and hands them back at
    // the end of the group, so nothing after it should depend on a small list.
    'perf_budgets': registerPerfBudgetTests,
    // Next groups register here, one entry each:
  };

  if (_onlyGroup.isEmpty) {
    // The register order is the run order: a group's tests depend on the
    // stores and records the groups before it left behind.
    for (final register in groups.values) {
      register();
    }
  } else {
    final register = groups[_onlyGroup];
    if (register == null) {
      throw ArgumentError.value(_onlyGroup, 'E2E_GROUP',
          'unknown group; known groups: ${groups.keys.join(', ')}');
    }
    register();
  }
}
