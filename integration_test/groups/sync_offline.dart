// What sync actually promises. §1.6.
//
// Two directions, one app:
//
//  * a row written **here** reaches the server — including a row written while
//    the app believed it was offline, which is the promise the whole offline
//    mode exists for;
//  * a row written **elsewhere** reaches here, and lands without disturbing
//    whatever the user is in the middle of.
//
// "Elsewhere" is a second writer on the same PocketBase (`RemoteRows`), because
// using the engine to fake another device would test the engine against itself.
// "Offline" is `network.isOnline(false)` — the app's own signal, the one
// `AppDatabase.hookDBToNetwork` listens to, which is what pauses the engine and
// disables the shell's sync action. The syncs themselves are driven through the
// shell's own button, never by calling into the engine.
//
// The suite shares one clinic, so every row this group creates is handed back on
// both sides (local store and server) before the test ends.
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';

/// One action of the shell, by the label it carries.
///
/// This branch's shell has no stable id per action, and matching the icon would
/// match a widget rather than the action — so the label is what is left. The
/// errors action is the one that changes its label with the state, which is why
/// it answers to either of its two.
NetworkAction _action(String id) {
  final wanted = switch (id) {
    'sync' => (NetworkAction a) => a.tooltip == txt('synchronizing'),
    'errors' => (NetworkAction a) =>
        a.tooltip == txt('errors') || a.tooltip == txt('reconnect'),
    _ => (NetworkAction a) => a.tooltip == id,
  };
  return networkActions.actions.firstWhere(wanted);
}

/// Puts the app in its **working-offline** state — the one the shell reads.
///
/// This is the app's own flag (`loginCtrl.proceededOffline`), and it is what
/// disables the shell's sync action; §3.4 `02` covers the same state for the
/// shell. It is *not* a network outage — see the skipped `02` for what the three
/// ways of faking one actually did.
Future<void> _workOffline(WidgetTester tester) async {
  loginCtrl.proceededOffline(true);
  await E2E.settle(tester, frames: 20);
  expect(_action('sync').disabled, isTrue,
      reason: 'the shell still offers a sync while the app works offline');
}

/// Back to working normally, with the app's own sync run once.
Future<void> _comeOnline(WidgetTester tester) async {
  loginCtrl.proceededOffline(false);
  await E2E.settle(tester, frames: 15);
  // Exactly what the shell's sync button runs: the callbacks the app registered
  // for its own database (`networkActions.resync()` calls these). Pressing the
  // button is the same call and is done in `01`/`03`/`04`/`05`; here the point is
  // to leave the app synced and online for the next test.
  for (final callback in networkActions.syncCallbacks.values) {
    callback();
  }
  await E2E.settle(tester, frames: 20);
}

/// Pumps until the app's local store holds [id].
Future<void> _waitForLocalRow(
  WidgetTester tester,
  String id, {
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (patients.get(id) != null) return;
    await E2E.settle(tester, frames: 5);
  }
  fail('the app never pulled $description ($id)');
}

/// Pumps until the server holds a patient row named [name].
Future<Map<String, dynamic>> _waitForRemoteRow(
  WidgetTester tester,
  String name, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await RemoteRows.named('patients', name);
    if (rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first.data['data'] as Map);
    }
    await E2E.settle(tester, frames: 5);
  }
  fail('"$name" never reached the server');
}

/// Hands a patient row back on both sides: the server keeps every record the
/// suite writes, and so does the clinic every later group reads.
Future<void> _handBack(WidgetTester tester, String id) async {
  await RemoteRows.delete(id);
  patients.purge(id);
  await E2E.settle(tester, frames: 5);
}

void registerSyncOfflineTests() {
  group('sync_offline', () {
    testWidgets('01: the login pulls the rows another device already wrote',
        (tester) async {
      // Written **before** the login: this is "somebody else added it while I was
      // away", and the login's own sync is the only sync in this test. The *run's*
      // first boot resets the server (`E2E.resetState`), so the boot has to come
      // first — otherwise the reset deletes the row this test just wrote, which is
      // exactly how the first version of it failed.
      await E2E.boot(tester);
      final name = Fixtures.stamp('e2e remote');
      final id =
          await RemoteRows.insert(store: 'patients', data: {'title': name});

      await E2E.signIn(tester);
      await _waitForLocalRow(tester, id, description: 'the pulled patient');
      expect(await Fixtures.patientIdOf(name), id,
          reason: 'the pulled row is not readable by name');

      // …and it is a patient the app can *use*, not just a row: the list finds it
      // by name and its panel opens. (The patient's name field is `title` on the
      // wire — `name` is not a field at all, which is what the first version of
      // this test wrote, and why the row arrived with no name.)
      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, name);
      await Fixtures.closePanel(tester);

      await _handBack(tester, id);
    });

    testWidgets(
        '02: a change made offline lands on the server after a reconnect',
        (tester) async {
      // **Skipped, kept as the regression** (todo.md §6.2): this harness cannot
      // put the app *genuinely* offline, and the difference matters.
      //
      // A clinic's local database is keyed by its URL (`AppDatabase.pathFor`), so
      // a login to an unreachable server is a **different clinic's** database —
      // what is written there can never be what the online clinic syncs. And the
      // in-process levers do not hold, measured over four runs of this test:
      //
      //  * `network.isOnline(false)` — `hookDBToNetwork` publishes that observable
      //    from the *engine's* status, which keeps reporting a usable state, so
      //    the flag flips back to `true` within a frame (the observer then resumes
      //    the engine). `Expected: false, Actual: <true>`.
      //  * `network.onOffline['localpocket']()` — what that observer itself calls
      //    (`setConnectivity(false)` + `pause()`): the engine is paused, the flag
      //    still reads online, and a row written while it is paused **never
      //    reached the server** on resume + sync, in three runs.
      //  * `sync.setConnectivity(false)` alone — no offline status is emitted
      //    either, so the shell keeps offering a sync that cannot push.
      //
      // What the promise needs is an outage the test can switch on: a server it
      // can stop (a local PocketBase, or `tools/run_e2e.ps1 -BadServer`). Until
      // then this body stays as the regression — the day that lever exists, this
      // is the test that proves the core promise.
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e offline');
      await Fixtures.createPatient(tester, name: name);
      final id = await Fixtures.patientIdOf(name);
      expect(id, isNotEmpty,
          reason: 'the offline patient never reached the local store at all');

      // With the app offline here, the server must not have it…
      expect(await RemoteRows.named('patients', name), isEmpty,
          reason: 'the app pushed a row while it was offline');

      // …and after coming back it must, with the row that was typed.
      await _comeOnline(tester);
      final remote = await _waitForRemoteRow(tester, name);
      expect(remote['title'], name,
          reason: 'the server got a different row than the one that was typed');

      await _handBack(tester, id);
    }, skip: true);

    testWidgets(
        '03: a change made on another device arrives on the app\'s next sync',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);

      final name = Fixtures.stamp('e2e other device');
      final id =
          await RemoteRows.insert(store: 'patients', data: {'title': name});

      // It cannot be here yet: the last sync ran before the write.
      expect(patients.get(id), isNull,
          reason: 'the row was already local before the sync this test drives');

      // The user's own sync — the shell's sync action, not a call into the
      // engine. It is **disabled while a sync is already running**, and one is:
      // the login's own sync and the navigation sync that opening the patients
      // list fires both land before this line. So this does not assert that the
      // action is free *now* — a reading that only ever said `false` while the
      // app bar ignored `NetworkAction.disabled` (§6.1) — it presses it, waiting
      // for it to become pressable and failing with that reason if it never does
      // (`Fixtures.tapGlobalAction`).
      await Fixtures.tapGlobalAction(tester, 'sync');

      await _waitForLocalRow(tester, id,
          description: 'the row another device wrote');
      expect(await Fixtures.patientIdOf(name), id,
          reason: 'the pulled row is not readable by name');

      // The screen was already up before the sync, so this also covers the
      // refresh: a pulled row has to appear in the list without a reload.
      await Fixtures.openPatient(tester, name);
      await Fixtures.closePanel(tester);

      await _handBack(tester, id);
    });

    testWidgets('04: a remote update does not take an open draft with it',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester);
      final id = await Fixtures.patientIdOf(name);
      await Fixtures.tapGlobalAction(tester, 'sync');

      // The user is typing a new name and has not saved it.
      await Fixtures.openPatient(tester, name);
      final draft = Fixtures.stamp('e2e unsaved');
      await tester.enterText(find.byKey(WK.fieldPatientName), draft);
      await E2E.settle(tester, frames: 10);

      // Another device renames the same patient, and this device syncs.
      await RemoteRows.patch(id, {'name': Fixtures.stamp('e2e renamed')});
      await Fixtures.tapGlobalAction(tester, 'sync');
      await E2E.settle(tester, frames: 40);

      expect(find.byKey(WK.fieldPatientName), findsOneWidget,
          reason: 'the incoming change closed the panel the user was in');
      expect(Fixtures.fieldText(tester, WK.fieldPatientName), draft,
          reason: 'the incoming change replaced the draft the user was typing');

      // Closing a dirty panel asks first; `closePanel` answers the prompt.
      await Fixtures.closePanel(tester);
      await _handBack(tester, id);
    });

    testWidgets('05: a row deleted on the server is not deleted here',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester);
      final id = await Fixtures.patientIdOf(name);
      await Fixtures.tapGlobalAction(tester, 'sync');
      expect(await RemoteRows.fields(id), isNotNull,
          reason: 'the row never reached the server, so nothing below is about '
              'a server-side delete');

      // Another device deletes it. PocketBase has **no delete feed**, so the
      // incremental pull (keyed on `updated`) cannot see this at all.
      await RemoteRows.delete(id);
      expect(await RemoteRows.fields(id), isNull);

      await Fixtures.tapGlobalAction(tester, 'sync');
      await E2E.settle(tester, frames: 40);

      // The local record is the user's data: a delete this device never saw must
      // not take it away.
      expect(patients.get(id), isNotNull,
          reason: 'a delete this device never saw removed the local record');

      // *What* the engine does about the still-local row is the store's
      // `missingRemote` policy (`recreate`), and it is worth reading rather than
      // asserting here: the log says whether the sync pushed it back.
      final resurrected = await RemoteRows.fields(id) != null;
      // ignore: avoid_print
      print('ℹ️ after the sync, the server has the row again: $resurrected');

      await _handBack(tester, id);
    });

    testWidgets('06: the sync indicator reports busy, then idle',
        (tester) async {
      await E2E.signIn(tester);

      // The observable, not the badge: the badge shows the *callback count* when
      // nothing is in flight, so it is not a busy/idle signal at all.
      final seen = <int>[];
      final sub = networkActions.isSyncing.stream.listen(seen.add);
      addTearDown(sub.cancel);

      await Fixtures.tapGlobalAction(tester, 'sync');

      // The sync has a whole `resync()` behind it (activate + every callback), so
      // "busy" can outlast a fixed number of frames: wait for the idle end rather
      // than sampling once.
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (seen.isNotEmpty &&
          seen.last != 0 &&
          DateTime.now().isBefore(deadline)) {
        await E2E.settle(tester, frames: 10);
      }

      expect(seen, contains(1),
          reason: 'nothing ever reported a sync in progress');
      expect(seen.last, 0,
          reason: 'the indicator stayed busy after the sync finished');
    });

    testWidgets('07: the lists stay populated while offline', (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester);
      // Whatever this test does, the next group must not inherit an app that
      // believes it is working offline.
      addTearDown(() => loginCtrl.proceededOffline(false));

      await _workOffline(tester);

      // Offline is not an empty clinic: the local rows are what the screens read.
      await Fixtures.openPatients(tester);
      expect(find.byKey(WK.listSearch), findsWidgets,
          reason: 'the patients screen did not render while offline');
      await Fixtures.openPatient(tester, name);
      expect(find.byKey(WK.fieldPatientName), findsOneWidget,
          reason: 'the local record could not be opened while offline');
      await Fixtures.closePanel(tester);

      // Back online, and the row this test created is handed back on both sides.
      await _comeOnline(tester);
      await _handBack(tester, await Fixtures.patientIdOf(name));
    });

    testWidgets(
        '08: queued local changes survive an offline persistence session',
        (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e deferred offline');
      final remote = patients.remote!;
      final originalStatus = remote.isOnline;
      remote.timer?.cancel();
      remote.isOnline = false;
      addTearDown(() => remote.isOnline = originalStatus);
      await Fixtures.createPatient(tester, name: name);
      final id = await Fixtures.patientIdOf(name);
      await patients.waitUntilChangesAreProcessed();
      expect(await RemoteRows.named('patients', name), isEmpty);
      expect((await patients.local!.getDeferred()).containsKey(id), isTrue);
      remote.isOnline = true;
      await patients.synchronize();
      await _waitForRemoteRow(tester, name);
      await _handBack(tester, id);
    });
  });
}
