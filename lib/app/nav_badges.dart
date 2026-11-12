import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/labwork/labworks_controller.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// What a route is waiting on, or null when it has nothing worth a badge
/// (dashboard, patients, deleted items, settings…).
///
/// Each badge watches only its own store, so the shell builds once and only the
/// badge's few pixels redraw when the count changes.
Widget? navBadgeFor(AppRoute route) => switch (route) {
      AppRoute.labworks => _NavBadge(
          key: WK.navBadge(route.id),
          streams: [appointments.observableMap.stream],
          label: () => _count(labworks.dueCount),
        ),
      AppRoute.calendar => _NavBadge(
          key: WK.navBadge(route.id),
          streams: [appointments.observableMap.stream],
          label: () => _count(appointments.todayAppointments.length),
        ),
      AppRoute.notes => _NavBadge(
          key: WK.navBadge(route.id),
          streams: [notes.observableMap.stream],
          label: () => _count(notes.incomingCount),
        ),
      AppRoute.expenses => _NavBadge(
          key: WK.navBadge(route.id),
          streams: [expenses.observableMap.stream],
          label: () => _amount(expenses.outstandingDue),
        ),
      AppRoute.booking => _NavBadge(
          key: WK.navBadge(route.id),
          streams: [booking.requests.pending.stream],
          label: () => _count(booking.requests.pending()),
        ),
      _ => null,
    };

/// Nothing to say at zero; past ninety-nine the badge stops growing.
String? _count(int value) {
  if (value <= 0) return null;
  return value > 99 ? "99+" : "$value";
}

/// Exact money below a thousand, then a rounded "12.4K+" so the badge keeps the
/// width of the icons it sits on.
String? _amount(double value) {
  final whole = value.round();
  if (whole <= 0) return null;
  if (whole < 1000) {
    return NumberFormat.decimalPattern(locale.s.$code).format(whole);
  }
  return "${NumberFormat.compact(locale: locale.s.$code).format(whole)}+";
}

/// Repaints the badge when [streams] fire and disappears while [label] is null.
class _NavBadge extends StatelessWidget {
  const _NavBadge({
    super.key,
    required this.streams,
    required this.label,
  });

  final List<Stream<dynamic>> streams;
  final String? Function() label;

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder<dynamic>(
      streams: streams,
      builder: (context, _) {
        final text = label();
        if (text == null) return const SizedBox.shrink();
        return NavBadge(text);
      },
    );
  }
}

/// A compact pill: the same shape in the pane, the bottom bar and its flyout.
class NavBadge extends StatelessWidget {
  const NavBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.accentColor.normal,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: theme.resources.textOnAccentFillColorPrimary,
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
