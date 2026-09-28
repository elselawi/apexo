import 'package:apexo/features/accounts/accounts_screen.dart';
import 'package:apexo/features/appointments/calendar_screen.dart';
import 'package:apexo/features/archive/archive_screen.dart';
import 'package:apexo/features/dashboard/dashboard_screen.dart';
import 'package:apexo/features/dicom/dicom_screen.dart';
import 'package:apexo/features/expenses/expenses_screen.dart';
import 'package:apexo/features/labwork/labworks_screen.dart';
import 'package:apexo/features/notes/notes_screen.dart';
import 'package:apexo/features/patients/patients_screen.dart';
import 'package:apexo/features/settings/settings_screen.dart';
import 'package:apexo/features/stats/screen_stats.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Every screen reachable from the shell, in navbar order.
///
/// The *catalog*: what each route is, and what it requires. Whether a
/// requirement is met is the router's business, so the requirements are
/// declared here as plain data — `perm`, `adminOnly`, `windowsOnly` — which is
/// also what an enum constant being `const` demands.
///
/// Navigation takes one of these values rather than a route id string, so a
/// route that does not exist is a compile error instead of a silent no-op.
enum AppRoute {
  dashboard('dashboard', 'dashboard', FluentIcons.home, navbarKey: 'home'),
  patients(
    'patients',
    'patients',
    FluentIcons.medication_admin,
    perm: Perm.patients,
  ),
  // The calendar screen's label is "appointments" and its phone-bar label is
  // "calendar" — the one route whose label is not its id.
  calendar(
    'calendar',
    'appointments',
    WindowsIcons.calendar,
    navbarKey: 'calendar',
    perm: Perm.appointments,
  ),
  labworks(
    'labworks',
    'labworks',
    FluentIcons.manufacturing,
    perm: Perm.appointments,
  ),
  notes('notes', 'notes', WindowsIcons.quick_note),
  expenses(
    'expenses',
    'expenses',
    FluentIcons.receipt_processing,
    perm: Perm.expenses,
  ),
  insights('insights', 'insights', FluentIcons.chart, perm: Perm.stats),
  accounts('accounts', 'accounts', FluentIcons.people, adminOnly: true),
  deletedItems('deletedItems', 'deletedItems', WindowsIcons.delete),
  // Windows-only DICOM import. Gated on the platform plus the photos
  // permission (or admin).
  dicom(
    'dicom',
    'xrayLink',
    FluentIcons.generic_scan,
    perm: Perm.photos,
    windowsOnly: true,
  ),
  settings('settings', 'settings', FluentIcons.settings);

  const AppRoute(
    this.id,
    this.titleKey,
    this.icon, {
    this.navbarKey,
    this.perm,
    this.adminOnly = false,
    this.windowsOnly = false,
  });

  final String id;

  /// The pane and flyout label — not always [id]: see [calendar].
  final String titleKey;

  /// The phone bar's label, when it should differ from [titleKey]
  /// (the dashboard reads "home" there).
  final String? navbarKey;

  final IconData icon;

  /// The permission slot this route needs. `Perm.*` are plain `int` constants.
  final int? perm;

  /// Reachable by admins only, whatever [perm] says.
  final bool adminOnly;

  /// Reachable on Windows only (`!kIsWeb && Platform.isWindows`).
  final bool windowsOnly;

  String get title => txt(titleKey);

  String get navbarTitle => txt(navbarKey ?? titleKey);

  /// The screen this route shows.
  ///
  /// A `switch` rather than a stored builder, so that a new route is a compile
  /// error here as well as in `_syncStores`.
  Widget buildScreen() => switch (this) {
        AppRoute.dashboard => const DashboardScreen(),
        AppRoute.patients => const PatientsScreen(),
        AppRoute.calendar => const CalendarScreen(),
        AppRoute.labworks => const LabworksScreen(),
        AppRoute.notes => const NotesScreen(),
        AppRoute.expenses => const ExpensesScreen(),
        AppRoute.insights => const StatsScreen(),
        AppRoute.accounts => const AccountsScreen(),
        AppRoute.deletedItems => const ArchivedScreen(),
        AppRoute.dicom => const DicomScreen(),
        AppRoute.settings => const SettingsScreen(),
      };
}
