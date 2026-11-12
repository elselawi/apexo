@Tags(['serial'])
library;

import 'package:apexo/app/nav_badges.dart';
import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';

/// Badges are shell chrome: the counts and the shortening rules are what a
/// reader notices, so they are what these tests pin down.
void main() {
  late List<Appointment> previousAppointments;
  late List<Expense> previousExpenses;
  late List<Note> previousNotes;
  late List<RecordModel> previousAccounts;
  late List<int> previousPermissions;
  late String previousEmail;

  setUp(() {
    previousAppointments = appointments.docs.values.toList();
    previousExpenses = expenses.docs.values.toList();
    previousNotes = notes.docs.values.toList();
    previousAccounts = accounts.list();
    previousPermissions = login.savedPermissions;
    previousEmail = login.email;

    appointments.observableMap.clear();
    expenses.observableMap.clear();
    notes.observableMap.clear();
    accounts.list([]);
    login.email = '';
    login.token = '';
    login.pb = null;
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    appointments.observableMap.clear();
    appointments.setAll(previousAppointments);
    expenses.observableMap.clear();
    expenses.setAll(previousExpenses);
    notes.observableMap.clear();
    notes.setAll(previousNotes);
    accounts.list(previousAccounts);
    login.email = previousEmail;
    login.savedPermissions = previousPermissions;
  });

  Future<void> pumpBadge(WidgetTester tester, AppRoute route) async {
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 120,
          height: 40,
          child: navBadgeFor(route) ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  String badgeLabel(WidgetTester tester) =>
      tester.widget<NavBadge>(find.byType(NavBadge)).label;

  testWidgets('only routes with something to count get a badge',
      (tester) async {
    for (final route in const [
      AppRoute.dashboard,
      AppRoute.patients,
      AppRoute.insights,
      AppRoute.accounts,
      AppRoute.deletedItems,
      AppRoute.settings,
    ]) {
      expect(navBadgeFor(route), isNull, reason: '${route.id} should be bare');
    }
    for (final route in const [
      AppRoute.labworks,
      AppRoute.calendar,
      AppRoute.notes,
      AppRoute.expenses,
      AppRoute.booking,
    ]) {
      expect(navBadgeFor(route), isNotNull, reason: '${route.id} counts');
    }
    expect(find.byType(NavBadge), findsNothing);
  });

  testWidgets('an empty count shows no pill at all', (tester) async {
    await pumpBadge(tester, AppRoute.labworks);

    expect(find.byKey(WK.navBadge(AppRoute.labworks.id)), findsOneWidget);
    expect(find.byType(NavBadge), findsNothing,
        reason: 'nothing pending must not draw a zero');
  });

  testWidgets('the labworks badge counts labwork still at the lab',
      (tester) async {
    appointments.set(testAppointment(
        id: 'waiting-1', hasLabwork: true, labName: 'Acme Lab'));
    appointments.set(testAppointment(
        id: 'waiting-2', hasLabwork: true, labName: 'Acme Lab'));
    appointments.set(testAppointment(
        id: 'received',
        hasLabwork: true,
        labName: 'Acme Lab',
        labworkReceived: true));
    appointments.set(testAppointment(id: 'no-labwork'));

    await pumpBadge(tester, AppRoute.labworks);
    expect(badgeLabel(tester), '2');

    appointments.set(testAppointment(
        id: 'waiting-1',
        hasLabwork: true,
        labName: 'Acme Lab',
        labworkReceived: true));
    await tester.pumpAndSettle();
    expect(badgeLabel(tester), '1');

    appointments.set(testAppointment(
        id: 'waiting-2',
        hasLabwork: true,
        labName: 'Acme Lab',
        labworkReceived: true));
    await tester.pumpAndSettle();
    expect(find.byType(NavBadge), findsNothing,
        reason: 'a settled lab queue must clear the badge');
  });

  testWidgets('the calendar badge counts today only', (tester) async {
    final now = DateTime.now();
    appointments.set(testAppointment(id: 'today-1', date: now));
    appointments.set(testAppointment(
        id: 'today-2', date: DateTime(now.year, now.month, now.day, 23, 30)));
    appointments.set(testAppointment(
        id: 'yesterday', date: now.subtract(const Duration(days: 1))));
    appointments.set(testAppointment(
        id: 'tomorrow', date: now.add(const Duration(days: 1))));

    await pumpBadge(tester, AppRoute.calendar);

    expect(badgeLabel(tester), '2');
  });

  testWidgets('the notes badge counts this account\'s open notes',
      (tester) async {
    accounts.list([
      RecordModel({'id': 'acc-1', 'email': 'acc-1@clinic.test'}),
    ]);
    login.email = 'acc-1@clinic.test';

    notes.set(testNote(id: 'mine', assignedTo: 'acc-1'));
    notes.set(testNote(id: 'mine-too', assignedTo: 'acc-1'));
    notes.set(testNote(id: 'done', assignedTo: 'acc-1', done: true));
    notes.set(testNote(id: 'theirs', assignedTo: 'acc-2'));
    notes.set(testNote(id: 'column', isColumn: true, assignedTo: 'acc-1'));

    await pumpBadge(tester, AppRoute.notes);

    expect(badgeLabel(tester), '2');
  });

  testWidgets('the expenses badge shows the due amount, then shortens it',
      (tester) async {
    expenses.set(testExpense(id: 'order-1', cost: 500, paidAmount: 100));

    await pumpBadge(tester, AppRoute.expenses);
    expect(badgeLabel(tester), '400');

    expenses.set(testExpense(id: 'order-2', cost: 1500));
    await tester.pumpAndSettle();

    final label = badgeLabel(tester);
    expect(label, endsWith('+'), reason: '$label should mark the rounding');
    expect(label.length, lessThan(7),
        reason: '$label must stay inside the icon width');

    expenses.set(testExpense(
        id: 'order-2', cost: 1500, processed: true, paidAmount: 1500));
    await tester.pumpAndSettle();
    expect(badgeLabel(tester), '400',
        reason: 'a settled order stops counting as due');
  });

  testWidgets('the bottom bar draws the badge on its destination',
      (tester) async {
    appointments.set(
        testAppointment(id: 'waiting', hasLabwork: true, labName: 'Acme Lab'));

    await pumpApexoApp(
      tester,
      const Center(
        child: SizedBox(
          width: 90,
          height: 66,
          child: BottomNavBarButton(route: AppRoute.labworks),
        ),
      ),
    );

    expect(find.byType(NavBadge), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
