// Scale: what the app does when the clinic is not a demo. §4.4.
//
// Every test here seeds real volume into the store, drives the screen the way a
// user would, and asserts a **budget** on the elapsed time while printing the
// measurement (`Fixtures.measure`). A budget is deliberately generous — this runs
// on a loaded desktop CI box — so it catches an order-of-magnitude regression
// (an N+1 read, a query without its index, a synchronous decode of every row in
// `build`) rather than a stopwatch difference.
//
// The seeded rows are handed back at the end of the group: the suite shares one
// clinic, and a thousand leftover patients would change every later group's
// paging and search.
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/stats/widgets/charts/bar.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';

/// How many patients the scale tests seed.
const _patients = 1000;

/// The name every seeded patient is given, so this group can tell its own rows
/// from the ones the rest of the suite shares the server with.
const _seedPrefix = 'e2e bulk';

/// How many visits the calendar and the insights tests seed (across one month).
const _visits = 200;

/// How many notes `07` seeds into one board column.
const _notesInAColumn = 200;

void registerPerfBudgetTests() {
  group('perf_budgets', () {
    // Seeded by `01`, which is this group's **fixture**: `setUpAll` cannot seed,
    // because the clinic database is opened by a login and a login only happens
    // inside a test (`Bad state: The database is not open yet`). Every test after
    // `01` therefore depends on it, exactly like the other groups depend on the
    // groups before them.
    var patientIDs = <String>[];
    var visitIDs = <String>[];

    tearDownAll(() async {
      // A safety net for a run that seeded and then failed: `06` hands the rows
      // back itself, and both calls are no-ops once the lists are empty.
      if (visitIDs.isNotEmpty) {
        await Fixtures.purgeSeeded(null, 'appointments', visitIDs);
      }
      if (patientIDs.isNotEmpty) {
        await Fixtures.purgeSeeded(null, 'patients', patientIDs);
      }
    });

    testWidgets('01: the clinic is filled to scale', (tester) async {
      await E2E.signIn(tester);

      // One write per thousand rows, not a thousand writes: the seeding is the
      // fixture, and a row-at-a-time seed would dominate every measurement below.
      final ms =
          await Fixtures.measure('seeding $_patients patients', () async {
        patientIDs = await Fixtures.seedPatientsBulk(tester, count: _patients);
      });
      await Fixtures.measure('seeding $_visits visits', () async {
        visitIDs = await Fixtures.seedVisitsThisMonth(tester,
            count: _visits, patientIDs: patientIDs);
      });

      expect(patientIDs.length, _patients);
      expect(visitIDs.length, _visits);
      expect(ms, lessThan(30000), reason: 'the bulk patient seed took ${ms}ms');
    });

    testWidgets('02: the patients screen opens with 1000 patients',
        (tester) async {
      await E2E.signIn(tester);

      final ms =
          await Fixtures.measure('opening the patients screen', () async {
        await Fixtures.openPatients(tester);
        // Wait for the screen's own total, not for a particular row: the list is
        // paged *and* sorted by whatever column the screen defaults to (not the
        // title), so page one need not hold any seeded name. The total is the
        // screen stating that it has folded every patient in — which is the work
        // being measured, because each row also carries that patient's
        // appointment-derived columns, where an N+1 read would show up.
        await E2E.waitFor(tester, find.textContaining('$_patients'),
            description: 'the patients list to know about $_patients patients',
            timeout: const Duration(seconds: 60));
      });

      // The page bar reports the total the screen loaded, which is what makes
      // "with a thousand patients" a real statement rather than a hope.
      expect(find.textContaining('$_patients'), findsWidgets,
          reason: 'the list does not know about all $_patients patients');
      expect(ms, lessThan(20000), reason: 'opening 1000 patients took ${ms}ms');
    });

    testWidgets('03: the calendar opens a month holding 200 visits',
        (tester) async {
      await E2E.signIn(tester);

      final ms = await Fixtures.measure('opening the calendar', () async {
        await Fixtures.openCalendar(tester);
        await E2E.settle(tester, frames: 20);
      });

      // The seeded visits are inside the month the calendar opens on, and they
      // all belong to the signed-in account, so the month's own count is what
      // an aggregation bug would under-report.
      await Fixtures.openInsights(tester);
      await E2E.settle(tester, frames: 10);
      expect(
          chartsCtrl.filteredAppointments.length, greaterThanOrEqualTo(_visits),
          reason: 'insights sees fewer visits than were seeded into the month');
      expect(ms, lessThan(25000), reason: 'opening the calendar took ${ms}ms');
    });

    testWidgets('04: searching 1000 patients finds one row', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);

      // A name in the middle of the seeded range: it is not on the first page,
      // so the search is what has to find it. The assertion is scoped to a
      // **row**, because `find.text(wanted)` on its own also matches the search
      // box — which holds the very string being searched for. That is how this
      // test passed while every seeded patient had no name at all (the fixture
      // wrote `name`; the patient's name field is `title`).
      const wanted = 'e2e bulk 0500';
      final row = find.ancestor(
        of: find.text(wanted),
        matching: find.byType(ListTile),
      );
      final ms = await Fixtures.measure('searching 1000 patients', () async {
        await tester.enterText(find.byKey(WK.listSearch), wanted);
        await E2E.waitFor(tester, row,
            description: 'the searched-for patient row',
            timeout: const Duration(seconds: 45));
      });

      expect(ms, lessThan(15000), reason: 'the search took ${ms}ms');
      // `findsWidgets`, not `findsOneWidget`: the row draws the name twice (a
      // `Txt` builds a `Text` of its own), and the *row* is what the wait above
      // proved. What must not pass is the box holding the term — which is why the
      // finder descends from a `ListTile`.
      expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text(wanted),
          ),
          findsWidgets,
          reason: 'the search found the box that holds the term, not a row');
    });

    testWidgets('05: the insights screen aggregates the seeded visits',
        (tester) async {
      await E2E.signIn(tester);

      final ms = await Fixtures.measure('opening insights', () async {
        await Fixtures.openInsights(tester);
        await E2E.waitFor(tester, find.byType(StyledBarChart),
            description: 'the insights charts',
            timeout: const Duration(seconds: 60));
      });

      // The aggregation is over the month the seeded visits live in, and the
      // seeded prices are all the same, so a wrong total is visible as a number.
      final visits = chartsCtrl.filteredAppointments.length;
      expect(visits, greaterThanOrEqualTo(_visits),
          reason: 'insights aggregated $visits visits, not the seeded ones');
      expect(ms, lessThan(30000), reason: 'opening insights took ${ms}ms');
    });

    testWidgets('06: the seeded rows are handed back', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);

      // **Server first, then local**, in verified passes.
      //
      // A local purge of rows that exist on the server does not stick: the next
      // pull brings them back (a first pass left 24 of a thousand, a second 28),
      // because `Store.purge` drops the row's outbox entry with the row, so the
      // deletion is never pushed while the server still has the record to pull.
      // Deleting on the server first is the order that converges — but one pass
      // is not enough either: a burst of concurrent DELETE requests comes back
      // with client-side errors for rows that were in fact deleted (173 of a
      // thousand reported success, 160 really were still there). So each pass
      // deletes, then **re-reads the server** and takes what is left as the next
      // pass's work — until both sides agree there is nothing.
      final seededVisits = {...visitIDs};
      var pendingPatients = [...patientIDs];
      var pendingVisits = [...visitIDs];
      for (var pass = 1; pass <= 8; pass++) {
        if (pendingPatients.isEmpty && pendingVisits.isEmpty) break;
        final visitsGone = await RemoteRows.deleteMany(pendingVisits);
        final patientsGone = await RemoteRows.deleteMany(pendingPatients);
        // What the server still holds *now* — its answer, not the requests'.
        pendingPatients = [
          for (final row
              in await RemoteRows.titledLike('patients', _seedPrefix))
            row.id,
        ];
        pendingVisits = [
          for (final row in await RemoteRows.inStore('appointments'))
            if (seededVisits.contains(row.id)) row.id,
        ];
        // ignore: avoid_print
        print('ℹ️ hand-back pass $pass: patients $patientsGone, '
            'visits $visitsGone — the server still has '
            '${pendingPatients.length} patient(s), '
            '${pendingVisits.length} visit(s)');
      }

      await Fixtures.purgeSeeded(tester, 'patients', patientIDs);
      await Fixtures.purgeSeeded(tester, 'appointments', visitIDs);

      // …then let the app settle: the shell's own sync pushes anything left and
      // pulls what is gone, and both sides are asserted below.
      await Fixtures.tapGlobalAction(tester, 'sync');
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        if (await patients.total() == 0 &&
            (await RemoteRows.titledLike('patients', _seedPrefix)).isEmpty) {
          break;
        }
        await E2E.settle(tester, frames: 20);
      }
      final leftInStore = await patients.total();
      final leftOnServer =
          (await RemoteRows.titledLike('patients', _seedPrefix)).length;
      // ignore: avoid_print
      print('ℹ️ after the purge: $leftInStore patient row(s) in the clinic, '
          '$leftOnServer on the server');
      expect(leftInStore, 0,
          reason: 'the purge left $leftInStore patients in the store');
      expect(leftOnServer, 0,
          reason: 'the purge left $leftOnServer patients on the server');
      patientIDs = [];
      visitIDs = [];

      // …and the screen agrees: every other group shares this clinic, so a
      // leftover thousand patients would change their paging and their searches.
      // The assertion is scoped to the *rows* because the search box holds the
      // very text being searched for.
      await tester.enterText(find.byKey(WK.listSearch), _seedPrefix);
      final leftovers = find.descendant(
        of: find.byType(ListTile),
        matching: find.textContaining(_seedPrefix),
      );
      final screenDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (leftovers.evaluate().isNotEmpty &&
          DateTime.now().isBefore(screenDeadline)) {
        await E2E.settle(tester, frames: 10);
      }
      expect(leftovers, findsNothing,
          reason: 'the scale fixture left patients behind for the next group');
      expect(txt('patients'), isNotEmpty);
    });
    testWidgets('07: the notes board opens a column holding 200 notes',
        (tester) async {
      await E2E.signIn(tester);
      final seeded =
          await Fixtures.seedNotesBulk(tester, count: _notesInAColumn);

      final ms = await Fixtures.measure('opening the board', () async {
        await Fixtures.openNotes(tester);
        await Fixtures.waitForColumn(tester, 'e2e scale column',
            timeout: const Duration(seconds: 60));
        // The board reads every note it will show and files it under a column
        // before it draws anything, so two hundred notes in one column is where a
        // per-note read — or a query localpocket cannot index — shows up.
        final column = await Fixtures.boardColumn('e2e scale column');
        await E2E.waitFor(tester, column,
            description: 'the seeded board column',
            timeout: const Duration(seconds: 60));
      });

      expect(await Fixtures.columnExists('e2e scale column'), isTrue);
      expect(await Fixtures.storedNote('e2e note 0199'), isNotNull,
          reason: 'the board dropped notes from the seeded column');
      expect(ms, lessThan(25000), reason: 'opening the board took ${ms}ms');

      await Fixtures.purgeSeeded(tester, 'notes', seeded.notes);
      notes.purge(seeded.column);
      await E2E.settle(tester, frames: 5);
    });
  });
}
