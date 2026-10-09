import 'package:apexo/app/routing/app_route.dart' show AppRoute;
import 'package:apexo/app/routing/routes.dart' show routes;
import 'package:apexo/common_widgets/dialogs/first_launch_dialog.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show localSettings;
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart' show locale, txt;
import 'package:apexo/services/login.dart' show login;
import 'package:apexo/services/version.dart' show version;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/backend.dart';
import '../support/credentials.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';
import 'package:apexo/features/patients/patient_model.dart';

/// The flow every other group starts from: the app boots on the login screen,
/// a server that cannot be reached is reported, real credentials reach the
/// dashboard, and logging out goes back to the login screen — plus what the
/// same screen does when the password is wrong, the url is messy, the language
/// is switched, the credentials are cleared, the session is taken offline, the
/// reset email is asked for, and the app meets a server that has nothing on it.
///
/// Registered from `integration_test/e2e_test.dart`; every test boots the app
/// for itself (see [E2E.boot]) and signs in with [E2E.signIn] when it needs a
/// session, so any single test can be run on its own with `--plain-name`.
///
/// Three of the backlog's items are **skipped with their reason** rather than
/// written: a restart, a second browser tab and a database that will not open
/// are all things one test process cannot stage (`todo.md` §1.1 — the last one
/// for the same reason `errors_and_recovery 03`/`04` carry).
void registerLoginTests() {
  group('login', () {
    testWidgets('01: the login screen is shown', (tester) async {
      await E2E.boot(tester);
      await E2E.waitFor(
        tester,
        find.byKey(WK.btnLogin),
        timeout: const Duration(seconds: 60),
        description: 'the login button',
      );
      expect(find.byKey(WK.appLogo), findsWidgets);
      expect(find.byKey(WK.serverField), findsOneWidget);
      expect(find.byKey(WK.emailField), findsOneWidget);
      expect(find.byKey(WK.passwordField), findsOneWidget);
    });

    testWidgets('02: a server that is not there is reported', (tester) async {
      await E2E.boot(tester);
      // A boot restores the stored session, so the login screen is only
      // reachable the way a user reaches it — by signing out (a no-op when the
      // form is already up).
      await Fixtures.signOut(tester);
      await E2E.enterCredentials(
        tester,
        server: 'http://127.0.0.1:1/',
        email: 'e2e@example.com',
        password: 'not-a-password',
      );
      await E2E.tapLogin(tester);
      await E2E.waitFor(
        tester,
        find.byKey(WK.loginErr),
        timeout: const Duration(seconds: 90),
        description: 'the login error bar',
      );
    });

    testWidgets('03: signing in reaches the dashboard', (tester) async {
      await E2E.signIn(tester);
      // The staff shell is up before the dashboard's own reads are: wait for the
      // screen rather than catching it half-built.
      await E2E.waitFor(
        tester,
        find.byKey(WK.dashboardScreen),
        description: 'the dashboard',
      );
    });

    testWidgets('04: logging out returns to the login screen', (tester) async {
      await E2E.signIn(tester);

      // There are two logout buttons on this screen (the navigation pane header
      // and the dashboard's own command bar); the dashboard's is the one that
      // survives every window size.
      final logout = find.descendant(
        of: find.byKey(WK.dashboardScreen),
        matching: find.byKey(WK.btnLogout),
      );
      await E2E.tap(tester, logout, description: 'the dashboard logout button');
      try {
        await E2E.waitFor(
          tester,
          find.byKey(WK.btnLogin),
          description: 'the login screen',
        );
      } catch (_) {
        // Report what the app is showing instead of a bare timeout: after a
        // logout it can still be restoring the patient-side link.
        fail('Logout did not reach the login screen. The app says: '
            '"${loginCtrl.loginError()}" (status: '
            '"${loginCtrl.loadingIndicator()}", patient side: '
            '${loginCtrl.loadingPatientSide()}).');
      }
      expect(find.byKey(WK.dashboardScreen), findsNothing);
    });

    testWidgets('05: a wrong password is reported', (tester) async {
      await E2E.boot(tester);
      await Fixtures.signOut(tester);
      // A real server, a real account, the wrong password: the answer comes from
      // PocketBase's auth endpoint as a `400`, and the app has its own words for
      // it (`activate`'s `statusCode == 400` branch).
      await E2E.enterCredentials(
        tester,
        server: pbServer,
        email: pbEmail,
        password: 'not-the-password',
      );
      await E2E.tapLogin(tester);
      await E2E.waitFor(
        tester,
        find.byKey(WK.loginErr),
        timeout: const Duration(seconds: 90),
        description: 'the login error bar',
      );

      expect(loginCtrl.loginError(), 'Invalid email or password.',
          reason: 'the app reported something else');
      expect(find.text('Invalid email or password.'), findsWidgets,
          reason: 'the error was not shown on the screen');
      // …and no session was started: still on the login route, with the form up.
      // (`WK.globalActions` is the app bar's action row, which the login screen
      // has too — it is not a "the shell is up" finder.)
      expect(launch.open(), Open.login);
      expect(find.byKey(WK.btnLogin), findsOneWidget,
          reason: 'the app left the login screen without a session');
      expect(find.byKey(WK.dashboardScreen), findsNothing);
    });

    testWidgets('06: the server URL is normalised', (tester) async {
      await E2E.boot(tester);

      // What a user pastes and types: a url with trailing slashes, an email with
      // stray spaces and caps. `loginButton` strips the slashes and trims +
      // lowercases the email *before* either is used.
      await E2E.enterCredentials(
        tester,
        server: '$pbServer///',
        email: '  ${pbEmail.toUpperCase()}  ',
        password: pbPassword,
      );
      await E2E.tapLogin(tester);
      await E2E.waitFor(
        tester,
        find.byKey(WK.globalActions),
        timeout: const Duration(minutes: 3),
        description: 'the staff shell',
      );

      // The login succeeded — so the normalised url is one the server answered
      // on — and the app holds the normalised pair, which is what it will store
      // and fill the form with next time the login screen is up.
      expect(login.url, pbServer.replaceAll(RegExp(r'/+$'), ''),
          reason: 'the server url was kept as typed: "${login.url}"');
      expect(login.email, pbEmail.trim().toLowerCase(),
          reason: 'the email was not normalised: "${login.email}"');
    });

    testWidgets('07: the language can be switched from the login screen',
        (tester) async {
      await E2E.signIn(tester);
      // A boot restores the stored session, so the login screen is only
      // reachable the way a user reaches it — by signing out.
      await Fixtures.signOut(tester);
      expect(launch.open(), Open.login);
      // The login screen has its own picker — the settings screen is not
      // reachable before a session — so it is the one thing a user can change
      // here.
      addTearDown(() async {
        // The locale is a singleton: leaving it switched takes every later
        // group's labels with it.
        localSettings.selectedLocale = 0;
        localSettings.notifyAndPersist();
      });

      expect(find.text(txt('login')), findsWidgets,
          reason: 'the login tab is not labelled in the current language');

      final second = locale.list[1];
      await E2E.tap(tester, find.byKey(WK.loginLangComboBox),
          description: 'the login language picker');
      await E2E.settle(tester, frames: 15);
      await E2E.tapFirst(tester, find.text(second.$name),
          description: 'the second language');
      await E2E.settle(tester, frames: 20);

      expect(localSettings.selectedLocale, 1,
          reason: 'the picker did not change the locale');
      expect(locale.s.$code, second.$code,
          reason: 'the app did not switch to "${second.$code}"');
      // The screen's own labels follow it: the tab, the button and the field
      // labels are all translated, so the English "Login" has to be gone.
      expect(find.text(txt('login')), findsWidgets,
          reason: 'the labels did not follow the locale');
      expect(find.text('Login'), findsNothing,
          reason: 'an English label survived the switch');

      // …and back, which is what a user who picked the wrong language by
      // accident does.
      await E2E.tap(tester, find.byKey(WK.loginLangComboBox),
          description: 'the login language picker');
      await E2E.settle(tester, frames: 15);
      await E2E.tapFirst(tester, find.text(locale.list[0].$name),
          description: 'the first language');
      await E2E.settle(tester, frames: 20);
      expect(localSettings.selectedLocale, 0);
      expect(find.text('Login'), findsWidgets,
          reason: 'the screen stayed in the other language');
    });

    testWidgets('08: clearing credentials empties the form', (tester) async {
      await E2E.signIn(tester);
      // Signing out the way the dashboard's own button does (`logout(false)`)
      // *keeps* the clinic's address and the last email — that convenience is
      // what the clear button undoes.
      await Fixtures.signOut(tester);
      expect(Fixtures.fieldText(tester, WK.serverField), isNotEmpty,
          reason: 'the login form came back empty — nothing to clear');
      expect(Fixtures.fieldText(tester, WK.emailField), isNotEmpty);

      final clear = find.widgetWithText(Button, txt('clear'));
      expect(clear, findsWidgets,
          reason: 'the clear button is not offered with credentials set');
      // `findsWidgets` and `.first`: a `Txt` builds a `Text` of its own, so the
      // button's label matches twice — inside the *same* button.
      await E2E.tap(tester, clear.first, description: 'the clear button');

      // "Clear" clears the **form**, not only the stored values behind it.
      expect(Fixtures.fieldText(tester, WK.serverField), isEmpty,
          reason: 'the server url stayed in the field');
      expect(Fixtures.fieldText(tester, WK.emailField), isEmpty,
          reason: 'the email stayed in the field');
      expect(Fixtures.fieldText(tester, WK.passwordField), isEmpty);
      expect(login.url, isEmpty, reason: 'the url was not forgotten');
      expect(login.email, isEmpty, reason: 'the email was not forgotten');
      expect(launch.open(), Open.login);
    });

    testWidgets('09: proceeding offline reaches the shell', (tester) async {
      await E2E.signIn(tester);

      // A row in the clinic's **local** database: an offline session has no
      // server to read from, so this is what "the shell renders the clinic's
      // data" can only mean here. Handed back below, server first — a leftover
      // row would turn up in every later group's lists and counts.
      patients.setAll([
        Patient.fromJson({
          'id': _offlinePatientId,
          'title': _offlinePatientName,
        }),
      ]);
      await E2E.settle(tester, frames: 5);
      expect(await patients.total(), greaterThan(0),
          reason: 'the clinic has no local rows to render offline');
      addTearDown(() async {
        // Server first, then local: a local purge drops the row *and* its outbox
        // entry, so it is never pushed and the next pull brings it back
        // (`todo.md` §6.2). The second remote delete covers a push that was in
        // flight when the row was purged.
        await RemoteRows.delete(_offlinePatientId);
        patients.purge(_offlinePatientId);
        await RemoteRows.delete(_offlinePatientId);
      });

      await Fixtures.signOut(tester);
      expect(launch.open(), Open.login);

      // A *failed* sign-in is what offers the way in: the offline button exists
      // only next to the error.
      await E2E.enterCredentials(
        tester,
        server: pbServer,
        email: pbEmail,
        password: 'not-the-password',
      );
      await E2E.tapLogin(tester);
      await E2E.waitFor(
        tester,
        find.byKey(WK.btnProceedOffline),
        timeout: const Duration(seconds: 90),
        description: 'the proceed-offline button',
      );
      await E2E.tap(tester, find.byKey(WK.btnProceedOffline),
          description: 'the proceed-offline button');

      // The shell comes up without a session…  (Not by waiting for
      // `WK.globalActions`: that action row is in the app bar of *every* route,
      // the login screen's included — the app's own state is the truth.)
      await _waitForStaff(tester, 'the offline session');
      expect(launch.open(), Open.staff);
      expect(loginCtrl.loginError(), isEmpty,
          reason: 'the error that offered the offline button is still up');
      await E2E.waitFor(tester, find.byKey(WK.dashboardScreen),
          description: 'the dashboard');

      // …and it knows: the session is marked offline, so the shell does not
      // offer a sync. (`NetworkAction.disabled` used to be ignored by the shell
      // widget, and pressing that button re-activated a session with no token —
      // which threw the user back onto the login screen with an error.)
      expect(loginCtrl.proceededOffline(), isTrue,
          reason: 'the app does not know the session is offline');
      expect(Fixtures.globalActionDisabled(tester, 'sync'), isTrue,
          reason: 'the shell still offers a sync to an offline session');

      // The clinic's own data is readable, which is the point of an offline
      // login: the local database, not the network.
      expect(await patients.total(), greaterThan(0),
          reason: 'the offline session cannot read the clinic\'s rows');
      // ignore: avoid_print
      print('ℹ️ offline session: isAdmin=${login.isAdmin}, '
          'accessible routes='
          '${routes.visibleRoutes.length}/${AppRoute.values.length}, '
          'local patients=${await patients.total()}');

      addTearDown(() async {
        // Leave a normal online session behind: an offline one keeps the shell's
        // sync action disabled, and every later group signs in expecting it.
        //
        // **Not** `Fixtures.signOut` + `E2E.signIn`: a tearDown runs after the
        // test framework has taken the widget tree down, so there is no login
        // button and no pane to tap there — the first version of this waited a
        // full minute for a nav item that could not exist. This is the same call
        // the shell's own reconnect makes, and it needs no UI.
        await login.activate(login.url, [pbEmail, pbPassword], true);
      });
    });

    testWidgets('10: the password reset email is sent', (tester) async {
      await E2E.boot(tester);
      await Fixtures.signOut(tester);
      addTearDown(() {
        // Both are singletons, and the next test that types into the form wants
        // the **login** tab.
        loginCtrl.selectedTab(0);
        loginCtrl.resetInstructionsSent(false);
      });

      await _openResetTab(tester);
      expect(loginCtrl.selectedTab(), 1,
          reason: 'the reset-password tab did not open');
      // `findsWidgets`: a `Txt` hands its key to the `Text` it builds, so the
      // finder matches both (todo.md §6.3).
      expect(find.byKey(WK.msgWillSendReset), findsWidgets,
          reason: 'the tab does not say what its button will do');

      // An address with no account: PocketBase answers `204` either way (it does
      // not disclose whether an email exists), so nothing is sent anywhere and
      // the app's success path is what is exercised. Measured against this
      // server before the test was written.
      await tester.enterText(find.byKey(WK.serverField), pbServer);
      await tester.enterText(
          find.byKey(WK.emailField), 'e2e-no-such-account@example.com');
      await E2E.settle(tester);

      await E2E.tap(tester, find.byKey(WK.btnResetPassword),
          description: 'the reset-password button');
      await E2E.waitFor(
        tester,
        find.byKey(WK.msgSentReset),
        timeout: const Duration(seconds: 90),
        description: 'the confirmation that the instructions were sent',
      );

      expect(loginCtrl.resetInstructionsSent(), isTrue);
      expect(loginCtrl.loginError(), isEmpty,
          reason: 'the reset reported an error: "${loginCtrl.loginError()}"');
      // The button goes away once there is nothing left to send, so a second
      // press cannot mail the same person twice.
      expect(find.byKey(WK.btnResetPassword), findsNothing);
      expect(find.text(txt('beenSent')), findsWidgets);
    });

    testWidgets('11: the session survives a restart', (tester) async {
      // Not writable here, and not because of the app: a restart is a new
      // **process**. Re-pumping the tree (`localization_rtl 05` does that for the
      // locale) keeps every singleton — `login` among them — in memory, so it
      // would prove nothing about what is *stored*. The restore itself is
      // exercised by every test that boots: `E2E.boot` waits on `login.ready`,
      // whose async restore runs a whole `activate(url, [token], true)`, and
      // `E2E.signIn` then returns straight to the shell on that session.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('12: the first-launch dialog is shown on an empty server',
        (tester) async {
      await E2E.boot(tester);
      await Fixtures.signOut(tester);

      // Run in a dedicated process: dropping collections while previous sessions
      // are synchronizing creates a schema-reset race.
      // A brand new PocketBase has no `data` collection *at all* — that, and not
      // an empty one, is what the app treats as "this clinic does not exist yet"
      // (`launch.isFirstLaunch`, set when the collection probe 404s). The next
      // login puts the collections back, so this is the same destructive reset a
      // run starts with, and the login group is where the suite begins.
      addTearDown(() async {
        launch.isFirstLaunch(false);
        launch.dialogShown(false);
        await Backend.resetServer();
      });
      launch.isFirstLaunch(false);
      launch.dialogShown(false);
      await Backend.dropCollections();

      await E2E.enterCredentials(
        tester,
        server: pbServer,
        email: pbEmail,
        password: pbPassword,
      );
      await E2E.tapLogin(tester);
      await _waitForStaff(tester, 'the newly initialized clinic');
      expect(launch.isFirstLaunch(), isTrue,
          reason:
              'The collection reset did not produce a first-launch session.');
      await E2E.waitFor(
        tester,
        find.byType(FirstLaunchDialog),
        timeout: const Duration(minutes: 3),
        description: 'the first-launch dialog',
      );
      expect(find.byType(ContentDialog), findsWidgets);

      // …and it behaves like every other dialog: closing it leaves a usable
      // shell behind, because the login created the collections it found missing.
      await E2E.dismissStartupDialogs(tester, waitForAppTimer: false);
      await E2E.waitFor(
          tester, find.byKey(const Key('dashboard_screen_button')),
          description: 'the staff shell');
    }, skip: !const bool.fromEnvironment('E2E_ISOLATED_FIRST_LAUNCH'));

    testWidgets('13: the changelog dialog is shown on a fresh install',
        (tester) async {
      await E2E.boot(tester);

      // A fresh install has no "last seen version", so the app opens the
      // changelog about a second in — and that boot is test `01`'s, not this one.
      // The harness records what it closed on the first boot of the run
      // (`E2E.firstBootDialogTitles`) instead of just swallowing it.
      expect(
          E2E.firstBootDialogTitles
              .any((text) => text.contains(txt('changelogDialogTitle'))),
          isTrue,
          reason: 'the first boot of the run did not show the changelog: '
              '${E2E.firstBootDialogTitles}');

      // Shown **once**: the app records the version it has shown, which is what
      // makes it a post-update notice rather than a nuisance.
      expect(localSettings.lastSeenVersion, version.current(),
          reason: 'the app did not record the version it showed');
      // The dialog is on a ~1s timer, so "it did not come back" has to be
      // checked after that timer would have fired.
      await tester.pump(const Duration(milliseconds: 1300));
      await E2E.settle(tester, frames: 5);
      expect(find.byType(ContentDialog), findsNothing,
          reason: 'the changelog came back on a device that has seen it');
      expect(E2E.lastBootDialogTitles, isEmpty,
          reason: 'this boot opened a startup dialog: '
              '${E2E.lastBootDialogTitles}');
    });

    testWidgets('14: a second tab is refused', (tester) async {
      // Web-only, and the harness drives one document: `alreadyRunningInAnother
      // Tab` comes from `LocalPocket.claimSingleInstance`, which a second
      // *browser tab* fails — nothing inside this process can hold the same
      // database twice. It belongs to the web run's list (`todo.md` §4.1).
      expect(true, isTrue);
    }, skip: true);

    testWidgets('15: a clinic whose database is missing is told so',
        (tester) async {
      // Not writable from the harness, for the reason `errors_and_recovery
      // 03`/`04` carry: the local database is opened **once per process**, and
      // the only way to reach `localDatabaseFailed` is to hand the app a
      // database it cannot read (`AppDatabase.pathFor(url)` is that file) — which
      // every later test, and the next run's reset, would inherit. The screen and
      // its way out exist (`loginCtrl.loginError` + `WK.btnProceedOffline`); the
      // missing piece is a seam that fails the open for one test only.
      expect(true, isTrue);
    }, skip: true);
  });
}

/// The one patient `09` puts in the clinic's local database: fifteen
/// alphanumerics, the shape the engine's own record ids have.
const _offlinePatientId = 'e2offline000000';

/// Its name — the point of the offline session's read, and handed back at the
/// end of the test.
const _offlinePatientName = 'e2e offline patient';

/// Opens the login screen's reset-password tab.
///
/// **By icon**, like `Fixtures.openPanelTab`: fluent builds the tab's header
/// button with the `Tab`'s own key, so `find.byKey(WK.forgotPasswordTab)` is two
/// widgets and `tap` refuses an ambiguous target. The tab bodies are built one at
/// a time, so the icon in the strip is the only one until the tab opens (the
/// reset button in the body has the same icon).
Future<void> _openResetTab(WidgetTester tester) async {
  await E2E.tapFirst(tester, find.byIcon(FluentIcons.password_field),
      description: 'the reset-password tab');
  await E2E.settle(tester, frames: 15);
}

/// Pumps until the app is on the staff route, and says why not if it never is.
///
/// `E2E.signIn` gets away with waiting for `WK.globalActions` because the
/// database wait behind it is the real gate; a test that drives the login itself
/// has to watch the app's own state.
Future<void> _waitForStaff(WidgetTester tester, String what) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (launch.open() != Open.staff) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what never reached the staff shell (the app is on '
          '"${launch.open()}", its login error is '
          '"${loginCtrl.loginError()}", status '
          '"${loginCtrl.loadingIndicator()}").');
    }
    await E2E.settle(tester, frames: 5);
  }
}
