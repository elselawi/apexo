import 'dart:async';

import 'package:apexo/app/app.dart';
import 'package:apexo/app/panels/panels_manager.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show localSettings;
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart' show login;
import 'package:apexo/app/data/initialize_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'backend.dart';
import 'credentials.dart';

/// Helpers every end-to-end group shares.
///
/// Everything here has to work on a native window *and* in a browser: `dart:io`
/// compiles for web but throws `Unsupported operation` at runtime, so its use
/// always sits behind a `kIsWeb` check (see [Backend]).
abstract final class E2E {
  // --------------------------------------------------------------- setup

  /// Whether this process has already reset the backend and the local state.
  static bool _stateReset = false;

  /// Whether this process has already wired the stores up.
  static bool _storesInitialized = false;

  /// Whether the app has already had the chance to open a startup dialog. A
  /// fresh install pops the changelog dialog about a second in; it is dismissed
  /// once and does not come back (the app records the version it has shown).
  static bool _startupDialogsHandled = false;

  /// Every text the startup dialogs of the **first boot of the run** held.
  ///
  /// The first boot is the only one that can see the changelog dialog (the run
  /// starts from a wiped device, so there is no "last seen version" yet), and
  /// that boot is some *other* test's. Recording what was closed is how a test
  /// that runs later can assert on it — `login 13` does exactly that.
  static final List<String> firstBootDialogTitles = [];

  /// Every text the startup dialogs of the **most recent boot** held — empty
  /// when that boot found none, which is what "the dialog does not repeat"
  /// looks like from the outside.
  static final List<String> lastBootDialogTitles = [];

  /// Resets the backend and the local state, once per run.
  ///
  /// The server is reset through [Backend.resetServer] (the `data` and `public`
  /// collections are dropped and re-imported), and the app's own log goes to
  /// the test output — when a step fails, that log is usually what says why.
  static Future<void> resetState() async {
    Backend.initLogging();
    if (!hasCredentials) {
      fail('No backend configured: pass --dart-define=PB_SERVER, PB_EMAIL and '
          'PB_PASSWORD (tools/run_e2e.ps1 reads them from test/secret.dart).');
    }
    await Backend.resetLocalData();
    await Backend.resetServer();
  }

  /// The window the tests drive.
  ///
  /// 1600x1000 keeps the navigation pane expanded. At the app's own 1280 the
  /// pane goes compact as soon as a panel is open, and its header overflows
  /// (`CurrentAccount` — a real bug, recorded in `todo.md` §6, not a test
  /// problem). Give the pane room until that is fixed.
  static const Size _window = Size(1600, 1000);

  /// Installs the one filter the harness applies to framework errors.
  ///
  /// **fluent_ui 4.13.0, `AutoSuggestBox`.** It schedules a post-frame
  /// `_updateLocalItems()` from its text listener (`auto_suggest_box.dart:436`)
  /// and calls `setState` from it, and its `dispose()` runs `_unselectAll()`,
  /// which fires every item's `onFocusChange` — the app's own callback among
  /// them (`tag_input.dart`). Both land on an element that is already defunct,
  /// asserting `'_lifecycleState != _ElementLifecycle.defunct'` or "setState()
  /// … called when widget tree was locked". Neither `State.mounted` nor
  /// `context.mounted` can tell: both are still true in that window (`_element` /
  /// `_parent` are cleared only after `dispose()`/`unmount()` return).
  ///
  /// The callback fires during whichever frame runs next, so the test framework
  /// used to blame the *following* test — every labworks test reported "This
  /// test failed after it had already completed".
  ///
  /// The filter matches the **stack**, because the message carries only the
  /// assertion text: any error passing through fluent's `auto_suggest_box.dart`
  /// is dropped, and nothing else is. The app's own bugs still fail the suite.
  ///
  /// [boot] calls this for every test: the test binding installs its own
  /// `FlutterError.onError` per test, which would otherwise sit above this
  /// filter and record the error anyway.
  static void installKnownFlutterIssueFilters() {
    final inherited = FlutterError.onError;
    FlutterError.onError = (details) {
      final stack = details.stack?.toString() ?? '';
      if (stack.contains('auto_suggest_box.dart')) return;
      if (inherited != null) {
        inherited(details);
      } else {
        FlutterError.presentError(details);
      }
    };
  }

  /// Runs one boot stage, naming it and failing loudly if it does not finish.
  ///
  /// **A hang in the boot path used to freeze a whole run silently** — no
  /// timeout fires, because nothing in a `testWidgets` body is bounded by
  /// default and the framework's own per-test timeout only applies once the body
  /// returns to the event loop. Three groups were found stuck on their first
  /// test that way (todo.md §6.2), with the app alive and no output for ten
  /// minutes. Each stage is bounded and named now, so the same failure reads
  /// "the wipe did not finish within 120s" instead of nothing at all.
  static Future<void> stage(
    String name,
    Future<void> Function() body, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final started = DateTime.now();
    // ignore: avoid_print
    print('⏱️  $name …');
    try {
      await body().timeout(timeout);
    } on TimeoutException {
      // ignore: avoid_print
      print('⏱️  $name STUCK for ${timeout.inSeconds}s');
      fail(
          '[e2e] "$name" did not finish within ${timeout.inSeconds}s — the run '
          'was stuck there. See the boot-wedge entry in todo.md §6.2.');
    }
    // ignore: avoid_print
    print('⏱️  $name done in '
        '${DateTime.now().difference(started).inMilliseconds}ms');
  }

  /// Starts the app for one test, and returns with the login screen usable.
  ///
  /// Every test calls this first. A `testWidgets` does **not** inherit the
  /// widget tree the test before it pumped — measured, the tree is empty — so
  /// each test pumps the app itself and gets a clean tree. What does survive is
  /// the app's own global state (`login`, the stores, the open database), which
  /// is why [signIn] exists: a test that needs a session must say so instead of
  /// relying on the test above it to have left one behind.
  static Future<void> boot(WidgetTester tester) async {
    installKnownFlutterIssueFilters();
    // …and again on the way out: the fluent error below is reported while the
    // test's own tree is being finalized, which is after the body has ended but
    // still inside this test's scope.
    addTearDown(installKnownFlutterIssueFilters);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _window;

    if (!_stateReset) {
      _stateReset = true;
      await stage('reset backend + local data', resetState,
          timeout: const Duration(minutes: 2));
    }

    // The stores are wired up by the app's own `main()`, and a `testWidgets`
    // never runs that — so this process does it, after the wipe (a fresh ""
    // directory is what a fresh install looks like) and before the pump.
    // Everything the device keeps for itself lives in Hive: the theme, the
    // locale, the signed-in session, the DICOM caches, and the deferred push
    // queue. Failing is not fatal to the app — the singletons fall back to
    // their defaults, exactly as they do for a user whose device key is gone —
    // so it is logged rather than thrown.
    if (!_storesInitialized) {
      _storesInitialized = true;
      await stage('open the device storage', () async {
        try {
          initializeStores();
        } catch (e) {
          // ignore: avoid_print
          print('⚠️  the device storage did not open: $e');
        }
      }, timeout: const Duration(seconds: 60));
    }

    // Panels are app state, not widget state: a test that failed with one open
    // would leave it in the global list, and the next test would then boot into
    // a panel it never opened (failing for a reason that is not its own).
    PanelsManager.closeAll();

    // Let anything the wipe or the device-database open left in flight finish
    // *before* the app is built. The first build after a wipe hangs now and then
    // (todo.md §6.2), and the one thing that is different about it is that it is
    // the first frame after that work: pumping an empty tree first drains those
    // microtasks, and it cannot hang itself — there is nothing to build.
    await settle(tester, frames: 5);

    // The first build after a local-data wipe hangs now and then, and a hung
    // `pumpWidget` **never releases the test binding's guard**: from then on
    // every guarded call in every later test fails with "Guarded function
    // conflict", which reads like a hundred unrelated breakages. So there is no
    // retry — the stage's bound names the stage that hung and the run is over.
    await stage(
      'pump ApexoApp',
      () async {
        await tester.pumpWidget(const ApexoApp());
        await settle(tester, frames: 8);
      },
      timeout: const Duration(seconds: 90),
    );

    // A persisting singleton restores its stored value **asynchronously**, and
    // `login`'s restore is not a read: with a token stored it runs a full
    // `activate(url, [token], true)` (`_LoginService.fromJson`), which is what
    // flips `launch.open()` to `Open.staff` and takes the login screen away.
    // `ObservablePersistingObject.ready` completes only after that finishes, so
    // waiting on it is what makes the app's state — and the screen it shows —
    // settled before a test touches either. Without it a boot races its own
    // restore: `perf_budgets 02` caught a login form mid-flight, so `tapLogin`
    // spent 60s waiting for a button that had been taken away, and the app
    // logged a write into the disposed login screen's controller.
    await stage('restore the app\'s stored state', () async {
      // Real I/O and real network: it has to run outside the fake-async zone the
      // test body lives in. (`waitForDatabase` gets away without this because
      // its pumps are what let the database open land.)
      await tester.runAsync(() async {
        await Future.wait<void>([login.ready, localSettings.ready]);
      });
      await settle(tester, frames: 5);
    });

    // The ~1s startup-dialog timer only has to be waited out on the first boot
    // of the run: after the dialog has been seen once it cannot come back.
    final waitForAppTimer = !_startupDialogsHandled;
    _startupDialogsHandled = true;
    await stage(
      waitForAppTimer ? 'startup dialogs (with app timer)' : 'startup dialogs',
      () => dismissStartupDialogs(tester, waitForAppTimer: waitForAppTimer),
    );
  }

  /// Whether the login form is on screen — the *button*, which is what
  /// `tapLogin` waits for and what a restored session takes away.
  static bool get _loginFormIsUp =>
      find.byKey(WK.btnLogin).evaluate().isNotEmpty;

  /// Signs in with the credentials from `support/credentials.dart` and returns
  /// once the staff shell is up. Returns immediately when it is already there.
  ///
  /// "Already there" is the app's own session state, not a screen: a signed-in
  /// app can be showing any route, and the test before this one may have left it
  /// on one.
  static Future<void> signIn(WidgetTester tester) async {
    await boot(tester);
    if (launch.open() == Open.staff) {
      await waitForDatabase(tester);
      return;
    }

    // Belt and braces over `boot`'s restore wait: a session can also be restored
    // while this runs (`signIn` is also used right after a logout), and a login
    // form that disappears mid-flow must not turn into a 60s wait for a button
    // that is gone. The shell wait below judges the outcome either way.
    await settle(tester, frames: 5);
    if (_loginFormIsUp) {
      await stage('fill credentials', () async {
        await enterCredentials(
          tester,
          server: pbServer,
          email: pbEmail,
          password: pbPassword,
        );
      });
      await stage('submit login', () async {
        for (var i = 0; i < 25 && !_loginFormIsUp; i++) {
          await settle(tester, frames: 2);
        }
        if (_loginFormIsUp) await tapLogin(tester);
      });
    }
    // Generous: a first login on a cold device builds/opens the local
    // database, and on web the very first OPFS open is the slow one.
    try {
      await waitFor(
        tester,
        find.byKey(WK.globalActions),
        timeout: const Duration(minutes: 5),
        description: 'the staff shell',
      );
    } catch (_) {
      // A login that does not arrive says why on the login screen (or is still
      // loading). Report that instead of a bare timeout: on web it is usually
      // `localDatabaseFailed` or `alreadyRunningInAnotherTab`.
      fail('Signing in did not reach the staff shell. The app says: '
          '"${loginCtrl.loginError()}" (status: '
          '"${loginCtrl.loadingIndicator()}").');
    }

    // The shell is up before the local database has finished opening — the open
    // is part of the login. Anything that reads a store has to wait for it: with
    // none open, a read throws "The database is not open yet: AppDatabase.open()
    // runs at login" instead of returning rows.
    await waitForDatabase(tester);
  }

  /// Pumps until the app's stores have a persistence session.
  ///
  /// The shell is up before login has opened one — the open is part of the
  /// login — so anything that reads a store has to wait for it: with none open,
  /// a read sees an empty store instead of the clinic's rows.
  static Future<void> waitForDatabase(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (patients.local == null) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The local database never opened after signing in.');
      }
      await settle(tester, frames: 5);
    }
  }

  // ------------------------------------------------------------ pumping

  /// Pumps frames until [finder] matches, then returns.
  ///
  /// `pumpAndSettle` cannot be used on these screens: the app shows progress
  /// rings and other endlessly repeating animations, so "settled" never
  /// arrives and it gives up after its timeout with "pumpAndSettle timed out".
  static Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
    String? description,
  }) async {
    final what = description ?? finder.describeMatch(Plurality.many);
    final deadline = DateTime.now().add(timeout);
    var nextHeartbeat = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isNotEmpty) return;
      // A stalled frame used to make the run go completely silent, which reads
      // as "the suite is stuck" with nothing to go on (todo.md §6.2). Say where
      // we are instead; a healthy wait prints at most a couple of these.
      if (DateTime.now().isAfter(nextHeartbeat)) {
        nextHeartbeat = DateTime.now().add(const Duration(seconds: 10));
        // ignore: avoid_print
        print('⏳ still waiting for $what');
      }
    }
    fail('Timed out after ${timeout.inSeconds}s waiting for $what');
  }

  /// The opposite of [waitFor]: pumps until [finder] stops matching.
  static Future<void> waitForGone(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
    String? description,
  }) async {
    final what = description ?? finder.describeMatch(Plurality.many);
    final deadline = DateTime.now().add(timeout);
    var nextHeartbeat = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isEmpty) return;
      if (DateTime.now().isAfter(nextHeartbeat)) {
        nextHeartbeat = DateTime.now().add(const Duration(seconds: 10));
        // ignore: avoid_print
        print('⏳ still waiting for $what to disappear');
      }
    }
    fail(
        'Timed out after ${timeout.inSeconds}s waiting for $what to disappear');
  }

  /// Pumps a few frames — enough for a tap or a keystroke to be handled.
  static Future<void> settle(WidgetTester tester, {int frames = 5}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Waits for [finder] and taps it.
  ///
  /// `tap` on its own only *warns* when the widget is covered or off screen, and
  /// a tap that misses looks exactly like a feature that does not work: the
  /// next `waitFor` times out. Waiting first, and tapping by key here, keeps
  /// that failure where it happens.
  ///
  /// Do **not** pass a `.first`/`.last` finder: those throw `Bad state: No
  /// element` as soon as they match nothing, so they cannot wait. Use
  /// [tapFirst], or `waitFor` on the plain finder and then tap the narrowed one.
  static Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    String? description,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await waitFor(tester, finder, timeout: timeout, description: description);
    await tester.tap(finder);
    await settle(tester);
  }

  /// Waits for [finder] and taps its first match.
  ///
  /// Reach for this when the thing being tapped can legitimately be on screen
  /// more than once: a plain `find.text(name).first` throws on an empty match
  /// instead of waiting, which turns "not there yet" into a crash.
  static Future<void> tapFirst(
    WidgetTester tester,
    Finder finder, {
    String? description,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await waitFor(tester, finder, timeout: timeout, description: description);
    await tester.tap(finder.first);
    await settle(tester);
  }

  // ------------------------------------------------------------ dialogs

  /// Closes whatever dialog the app opened on its own.
  ///
  /// A freshly started app pops the changelog dialog about a second in (a
  /// fresh install has no "last seen version"), and a dialog sits over the login
  /// form. Every dialog in this app is a `ContentDialog` closed by the cancel
  /// icon in its title row.
  ///
  /// [waitForAppTimer] waits out that ~1s timer before deciding there is
  /// nothing to close — needed on the first boot of a run, wasteful on every
  /// boot after it, when the dialog cannot come back.
  ///
  /// Every dialog's texts are recorded before it is closed: see
  /// [firstBootDialogTitles] and [lastBootDialogTitles]. Closing a dialog a test
  /// wants to *assert on* would defeat the purpose, so this is how the startup
  /// ones are checked — by what they said.
  static Future<void> dismissStartupDialogs(
    WidgetTester tester, {
    bool waitForAppTimer = true,
  }) async {
    // Give the startup dialogs, which come from a ~1s timer, time to appear
    // before deciding there is nothing to close. The clock here is the test
    // binding's virtual one, so this is what actually lets that timer fire —
    // 20 frames (~0.3s) was not enough on a cold, wiped install, and the
    // changelog dialog then came up *after* this ran, on top of the login form.
    lastBootDialogTitles.clear();
    if (waitForAppTimer) await settle(tester, frames: 90);

    for (var attempt = 0; attempt < 3; attempt++) {
      final dialog = find.byType(ContentDialog);
      if (dialog.evaluate().isEmpty) return;

      final close = find.descendant(
        of: dialog,
        matching: find.byIcon(WindowsIcons.cancel),
      );
      if (close.evaluate().isEmpty) {
        fail('A dialog is open and has no cancel button to close it with: '
            '${dialog.evaluate().length} ContentDialog(s) on screen.');
      }
      final texts = [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: dialog, matching: find.byType(Text)),
        ))
          text.data ?? '',
      ];
      lastBootDialogTitles.addAll(texts);
      if (waitForAppTimer) firstBootDialogTitles.addAll(texts);
      // `warnIfMissed: false`: a dialog entry that is still animating in is a
      // legitimate miss here, and the loop below re-checks what is left.
      await tester.tap(close.first, warnIfMissed: false);
      await settle(tester, frames: 10);
    }

    if (find.byType(ContentDialog).evaluate().isNotEmpty) {
      fail('A dialog is still open after trying to close it three times — '
          'the next taps would silently miss.');
    }
  }

  // ------------------------------------------------------ login screen

  /// Types the three credentials into the login tab.
  ///
  /// `enterText` replaces whatever the field held, so this is safe to call
  /// again on a form a previous test filled in.
  static Future<void> enterCredentials(
    WidgetTester tester, {
    required String server,
    required String email,
    required String password,
  }) async {
    await tester.enterText(find.byKey(WK.serverField), server);
    await tester.enterText(find.byKey(WK.emailField), email);
    await tester.enterText(find.byKey(WK.passwordField), password);
    await settle(tester);
  }

  /// Presses the login button (the login tab is the default one).
  static Future<void> tapLogin(WidgetTester tester) async {
    await tap(tester, find.byKey(WK.btnLogin), description: 'the login button');
  }
}
