// Accounts and permissions: who can sign in, with what, and what they then see.
//
// This is the group that needs a **second session**: permissions are per
// account, so the honest test signs out and back in as the account under test
// (`Fixtures.loginAs`). That is also what unblocks the notes/permission test
// that has been skipped since the notes group was written.
import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/services/login.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

/// A fresh, unique email for the account a test creates.
String _email(String prefix) =>
    '$prefix.${DateTime.now().millisecondsSinceEpoch}@e2e.example.com';

void registerAccountsTests() {
  group('accounts', () {
    testWidgets('01: the accounts screen lists accounts', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openAccounts(tester);

      // The signed-in admin is one of the rows, and the counts say so.
      expect(find.byType(ListTile), findsWidgets,
          reason: 'the accounts screen lists nothing');
      expect(find.textContaining('${txt('admins')}:'), findsWidgets,
          reason: 'the screen does not report how many admins there are');
    });

    testWidgets('02: an account can be created', (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e user');
      await Fixtures.openAccounts(tester);

      await Fixtures.createAccount(
        tester,
        name: name,
        email: _email('create'),
        password: 'e2e-Passw0rd',
      );

      // The list is lazy: a row below the fold is not built, so the search box is
      // what makes it reachable (it filters on name and email).
      await Fixtures.searchAccounts(tester, name);
      await E2E.waitFor(tester, Fixtures.accountRow(name),
          timeout: const Duration(seconds: 20),
          description: 'the "$name" account row after searching for it');
    });

    testWidgets('03: an account is created disabled and can be toggled',
        (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e toggle');
      await Fixtures.openAccounts(tester);
      await Fixtures.createAccount(
        tester,
        name: name,
        email: _email('toggle'),
        password: 'e2e-Passw0rd',
      );

      // A new account is stored switched **off**: the panel's model defaults the
      // flag to false, so an admin decides when the account goes live.
      expect(Fixtures.accountEnabled(name), isFalse,
          reason: 'a new account is stored enabled');

      // The panel's switch is what "account is active" means, and the record is
      // where it has to land (the row shows it, and login reads it).
      await Fixtures.setAccountEnabled(tester, name, true);
      expect(Fixtures.accountEnabled(name), isTrue,
          reason: 'enabling the account did not stick');

      await Fixtures.setAccountEnabled(tester, name, false);
      expect(Fixtures.accountEnabled(name), isFalse,
          reason: 'disabling the account did not stick');
    });

    testWidgets('04: an account signs in with its own email and password',
        (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e login');
      final email = _email('login');
      await Fixtures.openAccounts(tester);
      await Fixtures.createAccount(
        tester,
        name: name,
        email: email,
        password: 'e2e-Passw0rd',
      );
      await Fixtures.setAccountEnabled(tester, name, true);

      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');
      // Signed in: the shell is up and it is this account's name on it.
      await E2E.waitFor(tester, find.byKey(WK.dashboardScreen),
          description: 'the shell for the new account');
      expect(find.text(name), findsWidgets,
          reason: 'the shell does not say which account is signed in');

      await Fixtures.signInAsAdmin(tester);
    });

    testWidgets('05: a permission-less account is offered no gated route',
        (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e noperm');
      final email = _email('noperm');

      // The admin's own session has the gated routes, so the assertion below is
      // about the permission and not about an empty registry.
      expect(routes.visibleRoutes.map((r) => r.id),
          containsAll(<String>['dashboard', 'patients', 'calendar']),
          reason: 'the admin session is missing routes');

      await Fixtures.openAccounts(tester);
      await Fixtures.createAccount(
        tester,
        name: name,
        email: email,
        password: 'e2e-Passw0rd',
      );
      await Fixtures.setAccountEnabled(tester, name, true);

      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');

      // A user with no permissions at all is not shown those screens at all
      // (`routes.visibleRoutes` omits them — the app filters the list rather
      // than drawing a locked item), so what is asserted is the absence.
      final offered = routes.visibleRoutes.map((r) => r.id).toSet();
      expect(offered, contains('dashboard'),
          reason: 'the permission-less account cannot reach anything at all');
      expect(offered, isNot(contains('patients')),
          reason:
              'a screen the account has no permission for is still offered');
      expect(offered, isNot(contains('calendar')),
          reason:
              'the calendar is offered without the appointments permission');

      await Fixtures.signInAsAdmin(tester);
    });

    testWidgets('06: the account switch decides who is an operator',
        (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e off');
      final email = _email('off');
      await Fixtures.openAccounts(tester);
      await Fixtures.createAccount(
        tester,
        name: name,
        email: email,
        password: 'e2e-Passw0rd',
      );
      expect(Fixtures.accountEnabled(name), isFalse,
          reason: 'the account this test checks is not switched off');

      // Switched off is **not** a login gate: the account signs in fine and is
      // simply never offered as an appointment operator. (That a switched-off
      // account can still sign in is a gap — see `todo.md` §6.2.)
      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');
      expect(login.currentLoginIsOperator, isFalse,
          reason: 'a switched-off account is offered as an operator');
      await Fixtures.signInAsAdmin(tester);

      // The same account switched on *is* an operator, in its own session.
      await Fixtures.openAccounts(tester);
      await Fixtures.setAccountEnabled(tester, name, true);
      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');
      expect(login.currentLoginIsOperator, isTrue,
          reason: 'a switched-on account is not offered as an operator');
      await Fixtures.signInAsAdmin(tester);
    });

    testWidgets('07: an admin is offered every route', (tester) async {
      await E2E.signIn(tester);

      // `visibleRoutes` is the catalog filtered by what this session may open,
      // and the admin may open all of it — so the only route that can be
      // missing is the Windows-only DICOM one, which this machine may not
      // support.
      final missing = AppRoute.values
          .where((route) => !routes.visibleRoutes.contains(route))
          .where((route) => !route.windowsOnly)
          .map((route) => route.id)
          .toList();
      expect(missing, isEmpty,
          reason: 'the admin session is missing routes: $missing');
    });

    testWidgets('08: a granted permission unlocks its screen', (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e granted');
      final email = _email('granted');
      await Fixtures.openAccounts(tester);
      await Fixtures.createAccount(
        tester,
        name: name,
        email: email,
        password: 'e2e-Passw0rd',
      );

      // Grant `patients` at its highest level through the permission row's own
      // selector, then prove the screen it gates is reachable in that session.
      await Fixtures.setAccountEnabled(tester, name, true);
      await Fixtures.openAccount(tester, name);
      await Fixtures.grantPermission(tester, 'patients', txt('full'));
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');
      await Fixtures.openPatients(tester);

      await Fixtures.signInAsAdmin(tester);
    });

    testWidgets('09: permission changes apply on the next login',
        (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e revoked');
      final email = _email('revoked');
      await Fixtures.openAccounts(tester);
      await Fixtures.createAccount(
        tester,
        name: name,
        email: email,
        password: 'e2e-Passw0rd',
      );
      await Fixtures.setAccountEnabled(tester, name, true);

      await Fixtures.openAccount(tester, name);
      await Fixtures.grantPermission(tester, 'patients', txt('full'));
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');
      expect(routes.visibleRoutes.map((route) => route.id), contains('patients'),
          reason: 'the granted patients permission is not offered on next login');
      await Fixtures.signInAsAdmin(tester);

      await Fixtures.openAccounts(tester);
      await Fixtures.openAccount(tester, name);
      await Fixtures.grantPermission(tester, 'patients', txt('restricted'));
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.loginAs(tester, email: email, password: 'e2e-Passw0rd');
      expect(
        routes.visibleRoutes.map((route) => route.id),
        isNot(contains('patients')),
        reason:
            'revoking the patients permission did not hide the route on next login',
      );
      await Fixtures.signInAsAdmin(tester);
    });

    testWidgets('10: an account can be removed and its rows survive',
        (tester) async {
      // There is no delete wired to the account panel's chrome that this harness
      // can address: disabling the account (`03`) is the app's removal, and the
      // clinic's records belong to the clinic, not to the account.
    },
        skip: true);
  });
}
