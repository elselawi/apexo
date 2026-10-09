import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/store_ext.dart';
import '../support/fixtures.dart';

/// The patient list and its panel: the screen every other flow starts from.
void registerPatientsTests() {
  group('patients', () {
    testWidgets('01: the patients screen renders', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);

      expect(find.byKey(WK.btnNewPatient), findsOneWidget);
      expect(find.byKey(WK.listSearch), findsOneWidget);
    });

    testWidgets('02: a patient can be created', (tester) async {
      await E2E.signIn(tester);
      final name = Fixtures.stamp('e2e created');

      await Fixtures.createPatient(
        tester,
        name: name,
        yearOfBirth: '1990',
        email: 'e2e@example.com',
        phone: '+9647701234567',
        address: 'e2e street 1',
      );

      await Fixtures.openPatients(tester);
      expect(find.text(name), findsWidgets,
          reason: 'the created patient is not in the list');
    });

    testWidgets('03: a patient can be edited and saves', (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e edit'));

      await Fixtures.openPatient(tester, name);
      await tester.enterText(find.byKey(WK.fieldPatientAddress), 'e2e edited');
      await E2E.settle(tester);
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openPatient(tester, name);
      expect(Fixtures.fieldText(tester, WK.fieldPatientAddress), 'e2e edited');
      await Fixtures.closePanel(tester);
    });

    testWidgets('04: an untouched new patient cannot be saved', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);
      await Fixtures.openNewPatientPanel(tester);

      await Fixtures.waitForSaveState(tester, expectChanges: false);

      await Fixtures.closePanel(tester);
    });

    testWidgets('05: a phone number is stored in the E.164 form',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(
        tester,
        name: Fixtures.stamp('e2e phone'),
        phone: '07701234567',
      );

      // The stored value, not the field: the field holds what was typed, the
      // record holds what the app understood.
      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, name);
      final stored = Fixtures.fieldText(tester, WK.fieldPatientPhone);
      expect(stored.startsWith('+'), isTrue,
          reason: 'the phone was stored as "$stored" instead of the '
              'international form');
      await Fixtures.closePanel(tester);
    });

    testWidgets('06: search filters the list', (tester) async {
      await E2E.signIn(tester);
      final keeper = Fixtures.stamp('e2e search keep');
      final other = Fixtures.stamp('e2e search drop');
      await Fixtures.createPatient(tester, name: keeper);
      await Fixtures.createPatient(tester, name: other);
      await Fixtures.openPatients(tester);

      await tester.enterText(find.byKey(WK.listSearch), keeper);
      await E2E.settle(tester, frames: 8);

      expect(find.text(keeper), findsWidgets);
      expect(find.text(other), findsNothing,
          reason: 'search did not filter the second patient out');
    });

    testWidgets('07: an existing tag can be picked from the tag input',
        (tester) async {
      await E2E.signIn(tester);
      final tag = Fixtures.stamp('e2e tag');
      final seedName = await Fixtures.createPatient(tester);
      final seed =
          patients.docs.values.singleWhere((row) => row.title == seedName);
      patients.set(seed.copy(false)..tags = [tag]);
      await patients.waitUntilChangesAreProcessed();
      await Fixtures.openPatients(tester);
      await Fixtures.openNewPatientPanel(tester);
      final name = Fixtures.stamp('e2e tag patient');
      await tester.enterText(find.byKey(WK.fieldPatientName), name);
      await E2E.settle(tester);

      await Fixtures.pickTag(tester, WK.fieldPatientTags, tag);

      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);
      expect(find.text(name), findsWidgets);
      expect(patients.docs.values.singleWhere((row) => row.title == name).tags,
          contains(tag));
    });

    // Synthetic Enter needs the input focused, just like a physical keystroke.
    testWidgets('08: a tag is committed with Enter', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);
      await Fixtures.openNewPatientPanel(tester);
      final name = Fixtures.stamp('e2e enter patient');
      final tag = Fixtures.stamp('e2e enter tag');
      await tester.enterText(find.byKey(WK.fieldPatientName), name);
      await E2E.settle(tester);

      final box = find.descendant(
        of: find.byKey(WK.fieldPatientTags),
        matching: find.byType(AutoSuggestBox<String>),
      );
      await E2E.tap(tester, box, description: 'the tag input');
      await tester.enterText(box, tag);
      await E2E.settle(tester, frames: 8);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await E2E.settle(tester, frames: 8);

      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);
      await Fixtures.openPatient(tester, name);
      expect(
          patients.docs.values
              .singleWhere((patient) => patient.title == name)
              .tags,
          contains(tag));
      await Fixtures.closePanel(tester);
    });

    testWidgets('09: archiving takes a patient out of the list',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e archive'));

      await Fixtures.openPatient(tester, name);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openPatients(tester);
      expect(find.text(name), findsNothing,
          reason: 'the archived patient is still in the list');
    });

    testWidgets('10: a clean panel closes without asking', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);
      await Fixtures.openNewPatientPanel(tester);

      // Nothing typed, so closing must not put a "discard your changes?"
      // flyout in the user's way.
      await Fixtures.closePanel(tester);
      expect(find.byType(FlyoutContent), findsNothing,
          reason: 'closing an untouched panel asked for confirmation');
    });

    testWidgets(
        '11: sorting by name and toggling the direction reorders the list',
        (tester) async {
      await E2E.signIn(tester);
      final a = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e sort A'));
      final z = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e sort Z'));
      await Fixtures.openPatients(tester);

      // Narrow to the two under test: the list is paged, and the suite's other
      // patients sort around them.
      await tester.enterText(find.byKey(WK.listSearch), 'e2e sort');
      await E2E.settle(tester, frames: 20);

      await E2E.tapFirst(tester, find.text(txt('byName')),
          description: 'the sort-by-name toggle');
      await E2E.settle(tester, frames: 20);
      final ascendingBefore = Fixtures.rowY(tester, find.text(a)) <
          Fixtures.rowY(tester, find.text(z));

      // The board opens sorted by name already, so the first press on the
      // checked toggle is a *direction* flip — assert the order reversed, not
      // which way it went.
      await E2E.tapFirst(tester, find.text(txt('byName')),
          description: 'the sort-by-name toggle');
      await E2E.settle(tester, frames: 20);
      expect(
          Fixtures.rowY(tester, find.text(a)) <
              Fixtures.rowY(tester, find.text(z)),
          isNot(ascendingBefore),
          reason: 'toggling the sort direction did not reorder the list');

      await E2E.tapFirst(tester, find.text(txt('byName')),
          description: 'the sort-by-name toggle');
      await E2E.settle(tester, frames: 20);
      expect(
          Fixtures.rowY(tester, find.text(a)) <
              Fixtures.rowY(tester, find.text(z)),
          ascendingBefore,
          reason: 'the second toggle did not put the order back');
    });

    testWidgets('12: show more pages through the list', (tester) async {
      await E2E.signIn(tester);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final prefix = 'e2e paged $stamp';
      // More than one slice: the list shows a slice of its rows and the page bar
      // is what brings the rest in. No search here — the screen filters the rows
      // it has *loaded*, so a filter can never surface a row that is not on the
      // page yet (which is exactly the property this test is about).
      await Fixtures.seedPatients(tester, count: 26, prefix: prefix);
      await Fixtures.openPatients(tester);

      final target = find.textContaining('$prefix 25 ');
      expect(target, findsNothing,
          reason: 'the last seeded row is already shown, so nothing is paged');

      // The bar's own label is the evidence: it says how many of how many are
      // shown, so a failure here reports the real counts instead of a timeout.
      final bar = find.textContaining(txt('showing'));
      await E2E.waitFor(tester, bar, description: 'the page bar');
      final before = Fixtures.labelText(tester, bar);
      expect(find.byKey(WK.showMore), findsOneWidget,
          reason: 'the page bar has no show-more control (it reads "$before")');

      await E2E.tap(tester, find.byKey(WK.showMore),
          description: 'the show-more button');
      await E2E.settle(tester, frames: 30);
      expect(Fixtures.labelText(tester, bar), isNot(before),
          reason: 'show more did not page the list (still "$before")');
    });

    testWidgets('13: An archived patient is in Deleted Items, and restorable',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e restore'));

      await Fixtures.openPatient(tester, name);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openPatients(tester);
      // Assert by *row*: `find.text(name)` also matches the copy the search box
      // holds, and the box keeps the last search (see `Fixtures.openPatient`).
      final archivedRow = find.ancestor(
        of: find.text(name),
        matching: find.byType(ListTile),
      );
      expect(archivedRow, findsNothing,
          reason: 'the archived patient is still in the patients list');

      // It is the archived *record* that Deleted Items lists, and restoring it
      // has to put it back — the two halves the archiving test left open.
      await Fixtures.openDeletedItems(tester);
      await E2E.waitFor(tester, find.text(name),
          description: 'the "$name" archived row');
      await Fixtures.restoreFromDeletedItems(tester, name);
      await Fixtures.openPatient(tester, name);
      expect(find.byKey(WK.panelSave), findsOneWidget,
          reason: 'the restored patient does not open');
      await Fixtures.closePanel(tester);
    });

    testWidgets('14: closing a dirty panel asks before discarding',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);
      await Fixtures.openNewPatientPanel(tester);
      await tester.enterText(
          find.byKey(WK.fieldPatientName), Fixtures.stamp('e2e discard'));
      await E2E.settle(tester);
      await Fixtures.waitForSaveState(tester, expectChanges: true);

      await E2E.tap(tester, find.byKey(WK.panelClose),
          description: 'the panel close button');
      await E2E.waitFor(tester, find.byType(FlyoutContent),
          description: 'the unsaved-changes prompt');
      expect(find.textContaining(txt('sureClosePanel')), findsWidgets,
          reason: 'the prompt does not say what closing would discard');

      await Fixtures.confirmFlyout(tester);
      await E2E.waitForGone(tester, find.byKey(WK.panelSave),
          description: 'the panel');
    });

    testWidgets('15: archiving a patient keeps its appointments',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester);
      final day = DateTime.now();

      // The appointment this test is about is the one the booking adds.
      final beforeIds = appointments.forDay(day).map((a) => a.id).toSet();
      await Fixtures.createAppointment(tester, patientName: name, day: day);
      final rows = appointments.forDay(day);
      final booked = rows.firstWhere((a) => !beforeIds.contains(a.id));
      final patientID = booked.patientID;
      expect(patientID, isNotNull, reason: 'the booking has no patient');

      // Archived through the store: reopening the patient's panel after a
      // booking is the one thing this harness cannot drive yet (§6.2 records
      // it), and the rule under test is the store's, not the panel's.
      patients.archive(patientID!);

      // The product rule, pinned down: archiving a patient is **not** a cascade
      // and is not a delete — every appointment of that day is still there. (The
      // UI consequence, that the agenda can no longer resolve an archived
      // patient's name for the tile, is the separate finding in §6.2.)
      expect(appointments.forDay(day).length, rows.length,
          reason: 'archiving the patient took its appointments with it');
    });

    testWidgets('16: invalid email cannot be saved', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);
      await Fixtures.openNewPatientPanel(tester);
      final name = Fixtures.stamp('e2e invalid email');
      await tester.enterText(find.byKey(WK.fieldPatientName), name);
      await tester.enterText(find.byKey(WK.fieldPatientEmail), 'not-an-email');
      await E2E.settle(tester);
      await E2E.tap(tester, find.byKey(WK.panelSave),
          description: 'save invalid email');
      expect(patients.docs.values.where((row) => row.title == name), isEmpty);
      await E2E.dismissStartupDialogs(tester, waitForAppTimer: false);
      await E2E.discardDraft(tester);
    });

    testWidgets('17: list and grid views show the same patients',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester);
      await E2E.tap(tester, find.byKey(WK.dataTableListView),
          description: 'grid view');
      expect(find.byKey(const Key('patientsGrid')), findsOneWidget);
      expect(find.text(name), findsWidgets);
      await E2E.tap(tester, find.byKey(WK.dataTableListView),
          description: 'list view');
      expect(find.byKey(const Key('patientsGrid')), findsNothing);
      expect(find.text(name), findsWidgets);
    });
  });
}
