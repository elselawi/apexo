import 'package:apexo/features/accounts/accounts_screen.dart';
import 'package:apexo/features/appointments/calendar_screen.dart';
import 'package:apexo/features/archive/archive_screen.dart';
import 'package:apexo/features/booking/booking_requests_screen.dart';
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

/// Every screen reachable from the shell. Declaration order is navbar order.
enum AppRoute {
  dashboard('dashboard', 'dashboard', FluentIcons.home, navbarKey: 'home'),
  patients(
    'patients',
    'patients',
    FluentIcons.medication_admin,
    perm: Perm.patients,
  ),
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
  // Offered only once a clinic has claimed a public booking page (router check).
  booking('booking', 'bookingInbox', FluentIcons.globe),
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

  /// Exhaustive switch: a new route does not compile until it has a screen.
  Widget buildScreen() => switch (this) {
        AppRoute.dashboard => const DashboardScreen(),
        AppRoute.patients => const PatientsScreen(),
        AppRoute.booking => const BookingRequestsScreen(),
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
