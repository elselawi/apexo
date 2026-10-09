// Deleted Items — the archived records of every kind in one screen.
//
// The list shows a *row per archived record*; archiving is the app's delete (it
// is restorable), so this screen is where a user goes to undo one. Its rows are
// titled by the store's own idea of a record (a patient by name, an appointment
// by patient-and-date, …), which is why the assertions here are about a patient's
// name and about the *kind* filter rather than about a note's title.
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:flutter/material.dart' show ListTile;
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

void registerDeletedItemsTests() {
  group('deleted_items', () {
    testWidgets('01: an archived record is listed', (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e deleted-item'));

      await Fixtures.openPatient(tester, name);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openDeletedItems(tester);
      await E2E.waitFor(tester, find.text(name),
          description: 'the "$name" archived row');
    });

    testWidgets('02: the kind filter narrows the list', (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e filtered-item'));

      await Fixtures.openPatient(tester, name);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openDeletedItems(tester);
      await E2E.waitFor(tester, find.text(name),
          description: 'the "$name" archived row');

      // Filter to another kind: the patient has to leave the list. The filter is
      // a combo box with a "show all" placeholder, and the item is the *last*
      // match for the label — the overlay is painted after the screen behind it.
      await E2E.tapFirst(tester, find.text(txt('showAll')),
          description: 'the store filter');
      await E2E.settle(tester, frames: 10);
      await E2E.tap(tester, find.text(txt('notes')).last,
          description: 'the notes filter');
      await E2E.settle(tester, frames: 20);
      // By row, not by text: the screen's search box can still hold the name.
      expect(
        find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
        findsNothing,
        reason: 'the patient is still listed under the notes filter',
      );
    });

    testWidgets('03: restoring a record puts it back in its screen',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e restored-item'));

      await Fixtures.openPatient(tester, name);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openDeletedItems(tester);
      await E2E.waitFor(tester, find.text(name),
          description: 'the "$name" archived row');
      await Fixtures.restoreFromDeletedItems(tester, name);
      expect(find.text(name), findsNothing,
          reason: 'the restored patient is still listed in Deleted Items');

      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, name);
      expect(Fixtures.fieldText(tester, WK.fieldPatientName), name,
          reason: 'restoring the patient did not put it back on the patients screen');
      await Fixtures.closePanel(tester);
    });
  });
}
