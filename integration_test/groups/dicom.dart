// The X-ray link: the DICOM screen, the folder watch that feeds it, and what a
// scan makes of a file (§2.12).
//
// **Native Windows only, by construction**: `DicomController.isSupported` is
// `!kIsWeb && Platform.isWindows` and the route is gated on it, so on any other
// platform the route does not exist and there is nothing to open. Every test
// says so with `skip:` rather than failing on web (§4.1).
//
// The group drives the app's own scan: a real `.dcm` (the sample the repo ships
// for exactly this, `test/fixtures/dicom/sample.dcm`) is copied into a real
// folder, the folder is set as the clinic's watch directory, and the controller
// scans it with the real parser. What a test cannot do is answer the OS folder
// picker or the file picker — those items are skipped with their reasons at the
// bottom.
import 'dart:io';

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_importer.dart'
    show DicomPendingImport;
import 'package:apexo/services/dicom/dicom_skipped.dart' show dicomSkippedLog;
import 'package:apexo/services/login.dart' show login;
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/dicom_fixture.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';
import 'package:apexo/features/appointments/appointment_model.dart';

/// DICOM is a Windows feature: on web `isSupported` is false and the route is
/// not registered at all, so the tests below are skipped there rather than
/// pretending to pass. (`skip:` is a `bool` in this version of `flutter_test`,
/// which is why the reason lives here and not in the marker.)
final bool _skipOffWindows = !DicomController.isSupported;

void registerDicomTests() {
  group('dicom', () {
    // The engine and the scan lifecycle `main()` would have started.
    setUp(() async {
      if (!DicomController.isSupported) return;
      await DicomFixture.startEngine();
    });

    testWidgets('01: the screen renders with no DICOM files', (tester) async {
      await E2E.signIn(tester);
      await _openDicom(tester);

      // Nothing configured yet: the screen says which of the two empty states
      // this is, and the scan button is offered but *disabled* (a scan with no
      // folder has nothing to do, and the button knows it).
      await E2E.waitFor(tester, find.text(txt('dicomWatchDir_notSet')),
          description: 'the "no watch folder" empty state');
      expect(_buttonDisabled(tester, WK.dicomScanButton), isTrue,
          reason: 'the scan button is pressable with no folder configured');
      expect(dicomCtrl.pending(), isEmpty,
          reason: 'the screen starts with pending imports');
      expect(find.byKey(WK.listSearch), findsOneWidget,
          reason: 'the screen did not draw its search box');
    }, skip: _skipOffWindows);

    testWidgets('02: the auto-import toggle persists', (tester) async {
      await E2E.signIn(tester);
      await _openDicom(tester);

      final before = globalSettings.dicomAutoImport;
      addTearDown(() => globalSettings.dicomAutoImport = before);

      // The switch lives in the "Linked patients" dialog, which the command
      // bar's far item opens.
      await _openLinkedPatients(tester);
      final toggle = find.byKey(WK.dicomAutoImportToggle);
      expect(toggle, findsOneWidget,
          reason: 'the dialog does not hold the auto-import switch');

      await E2E.tap(tester, toggle, description: 'the auto-import switch');
      expect(globalSettings.dicomAutoImport, !before,
          reason: 'the switch did not reach the clinic settings');

      // …and the dialog shows the stored value when it is opened again, which is
      // what makes it a setting rather than a button.
      await _closeDialog(tester);
      await _openLinkedPatients(tester);
      expect(_toggleValue(tester, WK.dicomAutoImportToggle), !before,
          reason: 'the switch did not read its value back from the settings');
    }, skip: _skipOffWindows);

    testWidgets('04: a file dropped in the watched folder is imported',
        (tester) async {
      await E2E.signIn(tester);
      await _openDicom(tester);
      final dir = await DicomFixture.watchFolderWithSample();
      addTearDown(() => DicomFixture.cleanup([dir]));

      final pending = await _scan(tester, dir);
      expect(pending.length, 1,
          reason: 'the scan built ${pending.length} pending import(s) from one '
              'file — ${await _skippedSummary()}');
      final import = pending.first;
      expect(import.files, isNotEmpty,
          reason: 'the pending import names no files');
      expect(import.fileCount, greaterThanOrEqualTo(1));
      expect(import.dicomPatientName, isNotEmpty,
          reason: 'the file was parsed but claims no patient');

      // …and the screen shows it: the card is keyed by the record key the
      // pending import carries.
      await E2E.waitFor(
          tester, find.byKey(WK.dicomPendingCard(import.dicomPatientId)),
          description: 'the pending import card');
      expect(find.textContaining('${import.fileCount}'), findsWidgets,
          reason: 'the card does not say how many files it holds');
    }, skip: _skipOffWindows);

    testWidgets('06: an imported file is matched to a patient by name and date',
        (tester) async {
      await E2E.signIn(tester);

      // The sample says who it is for: the patient is created with **that** name
      // (the matcher scores name similarity at 0.6 and the dates at 0.4), plus a
      // visit on the study date, so both halves of the match have something to
      // find. Hard-coding a name would break on a new sample.
      final identity = await DicomFixture.sampleIdentity();
      final date = identity.date;
      expect(date, isNotNull,
          reason: 'the sample has no study date, so the date half of the match '
              'cannot be tested');
      final name =
          await Fixtures.createPatient(tester, name: identity.patientName);
      final id = await Fixtures.patientIdOf(name);
      expect(id, isNotEmpty,
          reason:
              'the patient was not stored'); // The patient has to go back at the end: a later scan in this group (and
      // any other group that scans) would match it again, and `07` wants a file
      // with nobody to match.
      addTearDown(() async {
        await RemoteRows.delete(id);
        patients.purge(id);
        await RemoteRows.delete(id);
      });
      appointments.setAll([
        Appointment.fromJson({
          'id': 'e2dcmvisit00001',
          'patientID': id,
          'operatorsIDs': [login.currentAccountID],
          'date': dateToWire(date!),
          'price': 0,
        }),
      ]);
      addTearDown(() async {
        appointments.purge('e2dcmvisit00001');
        patients.purge(id);
      });

      await _openDicom(tester);
      final dir = await DicomFixture.watchFolderWithSample();
      addTearDown(() => DicomFixture.cleanup([dir]));

      final pending = await _scan(tester, dir);
      expect(pending.length, 1, reason: await _skippedSummary());
      final import = pending.first;
      expect(import.matchedPatientId, id,
          reason: 'the scan matched "${import.dicomPatientName}" to '
              '"${import.matchedPatientName ?? "(nobody)"}" (confidence '
              '${import.confidence}) instead of the patient of that name');
      expect(import.confidence, greaterThan(0.9),
          reason: 'a name *and* a date match should score near 1.0');
      expect(dicomCtrl.matchingDates(import, id), isNotEmpty,
          reason: 'the study date does not line up with the patient\'s visit');

      // The card shows both sides of the match, which is what the dentist reads.
      await E2E.waitFor(
          tester, find.byKey(WK.dicomPendingCard(import.dicomPatientId)),
          description: 'the matched pending card');
      expect(find.text(identity.patientName), findsWidgets,
          reason: 'the card does not name the file\'s patient');
      expect(find.text(name), findsWidgets,
          reason: 'the card does not name the matched patient');
      expect(find.byKey(WK.dicomApprove), findsOneWidget,
          reason: 'a matched import is not offered for approval');
    }, skip: _skipOffWindows);

    testWidgets('07: an unmatched file appears in the unmatched list',
        (tester) async {
      await E2E.signIn(tester);
      // A patient of a completely different name: the file has nobody to match,
      // which is the state the dentist has to resolve by hand.
      await Fixtures.createPatient(tester, name: 'zzz unrelated patient');
      await _openDicom(tester);
      final dir = await DicomFixture.watchFolderWithSample();
      addTearDown(() => DicomFixture.cleanup([dir]));

      final pending = await _scan(tester, dir);
      expect(pending.length, 1, reason: await _skippedSummary());
      final import = pending.first;
      expect(import.matchedPatientId, isNull,
          reason: 'the scan matched a file to "${import.matchedPatientName}" '
              'although no patient has that name (confidence '
              '${import.confidence})');

      await E2E.waitFor(
          tester, find.byKey(WK.dicomPendingCard(import.dicomPatientId)),
          description: 'the unmatched pending card');
      expect(find.text(txt('dicomNoMatch')), findsWidgets,
          reason: 'the card does not say the match has to be picked by hand');
      expect(find.text(import.dicomPatientName), findsWidgets,
          reason: 'the card does not name the file\'s patient');
      expect(find.byKey(WK.dicomApprove), findsNothing,
          reason: 'an unmatched import is offered for approval');
      expect(find.byKey(WK.dicomChangeMatch), findsOneWidget,
          reason: 'the card does not offer to pick a patient');
    }, skip: _skipOffWindows);

    testWidgets('09: the matching dialog lets the user pick a patient',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e dicom'));
      final id = await Fixtures.patientIdOf(name);
      await _openDicom(tester);
      final dir = await DicomFixture.watchFolderWithSample();
      addTearDown(() => DicomFixture.cleanup([dir]));

      final pending = await _scan(tester, dir);
      expect(pending.length, 1, reason: await _skippedSummary());
      final import = pending.first;
      await E2E.waitFor(
          tester, find.byKey(WK.dicomPendingCard(import.dicomPatientId)),
          description: 'the pending card');

      await E2E.tap(tester, find.byKey(WK.dicomChangeMatch),
          description: 'the "change match" button');
      // The picker lists every patient by name, narrowed by the search box.
      await E2E.tap(tester, find.text(name),
          description: 'the patient in the picker');

      // Picking one opens the date-alignment step, which is where the dentist
      // sees whether the file's dates line up with the patient's visits.
      await E2E.waitFor(tester, find.text(txt('dicomDateAlignment')),
          description: 'the date-alignment step');
      expect(find.textContaining(txt('dicomMatchingPatient')), findsWidgets,
          reason: 'the alignment step does not name the patient it is about');
      await E2E.tap(tester, find.text(txt('save')),
          description: 'the alignment step\'s save button');

      // …and the pick is kept: the card is matched now. (`manualMatch` sets the
      // matched patient and its confidence on the pending import itself — the
      // id field is only filled by a scan's own matching pass.)
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        final now = dicomCtrl.pending();
        if (now.isNotEmpty && now.first.matchedPatient?.id == id) break;
        await E2E.settle(tester, frames: 10);
      }
      expect(dicomCtrl.pending().first.matchedPatient?.id, id,
          reason: 'the patient the dentist picked was not remembered');
      expect(find.byKey(WK.dicomApprove), findsOneWidget,
          reason: 'the card is not offered for approval after picking a '
              'patient');
    }, skip: _skipOffWindows);

    // ── Not writable from the harness, each with the reason it is not ──────
    testWidgets('03: a folder can be chosen as the watch directory',
        (tester) async {
      // The picker is `FilePicker.getDirectoryPath` — an OS dialog a widget test
      // cannot answer, and the dialog's buttons have no key either. What the
      // *setting* does is covered by `04`, and `04` may set the watch folder
      // directly (`globalSettings.setDicomWatchDirs`), which is the store the
      // dialog writes to.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('05: a .dcm can be uploaded on web', (tester) async {
      // Not a test problem: **the web import path does not exist.**
      // `handleNewDcm` returns `''` on web (`lib/utils/imgs.dart:193`), the DICOM
      // route is Windows-gated (`lib/app/routing/routes.dart`), and the gallery's file picker
      // sends every picked file through `handleNewImage` — so a `.dcm` picked on
      // web lands as an ordinary attachment, never as an X-ray. Recorded in
      // `todo.md` §6.2 as a missing feature rather than a bug.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('08: a skipped file says why', (tester) async {
      // There is no UI for it: `DicomSkippedLog` keeps the reason (`dicom_skipped`
      // in the device database) and its own doc says the screen does not surface
      // it. The registry is unit-covered (`dicom_importer_test.dart`), so what is
      // missing is a screen change, not a test.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('10: the viewer opens and renders the image', (tester) async {
      // The dialog is opened from a gallery entry that is in the record's
      // `dcmImgs` column (which needs an approved import — see `12`), and neither
      // `_DicomViewerDialog` nor the `DicomViewer` widget carries a key, so there
      // is nothing to wait for. The rendering itself is the native engine's, and
      // the export path behind it is unit-covered.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('11: the viewer controls work', (tester) async {
      // No keys on any control (zoom, the two window-level sliders, the presets,
      // reset) and the sliders are fluent's, which wrap material's — the same
      // shape as the a11y note in §4. The *preference* they write is
      // `localSettings.dicomViewerPrefs`, which `dicom_viewer_prefs_test.dart`
      // covers; what is missing is a way to reach the controls.
      expect(true, isTrue);
    }, skip: true);

    testWidgets(
        '12: a preview png is uploaded to the record and named correctly',
        (tester) async {
      // This needs a **full approve**: the `.dcm` is copied, uploaded under the
      // record's `dcmImgs` column, and a PNG preview is rendered and uploaded to
      // the same PocketBase group (whose name the server rewrites, which is why
      // the app resolves the sibling by group). The naming rule is unit-covered
      // (`dicom_helpers_test.dart`, `dicom_orphans_cleaner_test.dart`) and the
      // gallery's resolution by group is `dicom_gallery_test.dart`; what an e2e
      // would add is the upload, which is the one step that needs a rendered
      // image off the native engine.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('13: deleting the record removes the DICOM link',
        (tester) async {
      // A link only exists after an approve (`dicom_links` is written by the
      // import, and `DicomLinksStore` is unit-covered for add/unlink/removeKey);
      // without `12` there is no row to delete. `unlinkPatient` — the call the
      // Linked Patients dialog makes — is covered by the same unit tests.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('14: the registries survive a restart', (tester) async {
      // The registries moved out of Hive into the **device** database
      // (`dicom_links`, `dicom_file_meta`, `dicom_lru`, `dicom_skipped`,
      // `dicom_pending_matches`, `dicom_unmatched`), and that database is opened
      // once per process — so "a restart" is exactly the thing this harness
      // cannot stage (same reason as `errors_and_recovery 03`/`04`). Their
      // persistence is unit-covered (`dicom_dedup_test.dart`,
      // `dicom_registry_concurrency_test.dart`, `dicom_file_cache_test.dart`).
      expect(true, isTrue);
    }, skip: true);
  });
}

/// Opens the DICOM screen and waits for it to be there.
Future<void> _openDicom(WidgetTester tester) => Fixtures.openRoute(
      tester,
      'dicom',
      find.byKey(WK.dicomScreen),
      description: 'the X-ray link screen',
    );

/// Scans with [dir] configured as the watch folder and returns what it found.
///
/// The scan is the app's own (`applyScanSettings` → a `refresh()`), but it is
/// also *asynchronous* — the parse runs off the UI thread — and a periodic tick
/// can be in flight, in which case `refresh()` returns immediately
/// (re-entrant-safe). So the result is waited for, and a scan that finds nothing
/// fails with the reason the importer recorded.
Future<List<DicomPendingImport>> _scan(
    WidgetTester tester, Directory dir) async {
  await DicomFixture.watch([dir.path]);
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (dicomCtrl.pending().isEmpty && DateTime.now().isBefore(deadline)) {
    await E2E.settle(tester, frames: 10);
  }
  return dicomCtrl.pending();
}

/// The last thing the importer refused, for a failure message that says why a
/// scan found nothing (the registry is what the screen does not show — §2.12
/// `08`).
Future<String> _skippedSummary() async {
  final records = await dicomSkippedLog.all;
  if (records.isEmpty) return 'the skipped log is empty too';
  return 'last skip: ${records.first.path} — ${records.first.reason}';
}

/// Whether a fluent [Button] is disabled (its `onPressed` is null).
bool _buttonDisabled(WidgetTester tester, Key key) =>
    tester.widget<Button>(find.byKey(key)).onPressed == null;

/// Whether a fluent [ToggleSwitch] is on.
bool _toggleValue(WidgetTester tester, Key key) =>
    tester.widget<ToggleSwitch>(find.byKey(key)).checked;

/// Opens the command bar's "Linked patients" dialog (the auto-import switch
/// lives in it). The far item has no key, so it is addressed by its label, which
/// is the only thing that identifies it.
Future<void> _openLinkedPatients(WidgetTester tester) async {
  await E2E.tapFirst(
    tester,
    find.textContaining(txt('dicomLinkedPatients')),
    description: 'the linked patients dialog',
  );
  await E2E.settle(tester, frames: 10);
}

/// Closes the open dialog through its own close button.
Future<void> _closeDialog(WidgetTester tester) async {
  await E2E.tapFirst(tester, find.text(txt('close')),
      description: 'the dialog\'s close button');
  await E2E.settle(tester, frames: 10);
}
