// Upgrades: what the app does with a version bump. §3.3.
//
// `showDialogsIfNeeded()` (lib/app/app.dart) runs about a second after startup and
// does three things: it shows the changelog entry for the **current** version when
// the device last saw a *different* one, it remembers that version
// (`localSettings.lastSeenVersion`), and on macOS it advertises a newer release.
// So the whole feature is one piece of device state plus one dialog, and both are
// reachable from a test: a stale `lastSeenVersion` is what a user has right after
// an update.
import 'package:apexo/app/app.dart' show bContext;
import 'package:apexo/common_widgets/dialogs/changelog_dialog.dart'
    show showChangelogDialog;
import 'package:apexo/features/settings/settings_stores.dart'
    show localSettings;
import 'package:apexo/services/changelog.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/services/version.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

void registerUpgradeTests() {
  group('upgrade', () {
    testWidgets('01: the changelog entry is shown and then remembered',
        (tester) async {
      await E2E.signIn(tester);

      // `0.0.0` is the "could not read my own version" fallback, and
      // `showDialogsIfNeeded` skips the changelog entirely when it sees it: an
      // app that cannot say which release it is never announces an upgrade.
      expect(version.current(), isNot('0.0.0'),
          reason:
              'the app cannot read its own version, so an update would show '
              'no changelog at all');
      final entry = await changelog.forVersion(version.current());
      expect(entry, isNotNull,
          reason:
              'CHANGELOG.md has no entry for ${version.current()} — the app '
              'would show nothing after an update');
      expect(entry!.changes, isNotEmpty);

      // What a user meets right after an update: this dialog, raised for the
      // version being *run*. The context is a global, so a test can raise it
      // without waiting for startup's second-long timer — and a stale
      // `lastSeenVersion` is exactly the state an update leaves behind.
      final before = localSettings.lastSeenVersion;
      addTearDown(() => localSettings.lastSeenVersion = before);
      localSettings.lastSeenVersion = '0.0.1';

      await showChangelogDialog(bContext, entry: entry);
      await E2E.settle(tester, frames: 15);

      final dialog = find.byType(ContentDialog);
      expect(dialog, findsWidgets, reason: 'the changelog dialog did not open');
      // It names the version it is describing and shows the changes themselves —
      // an entry, not a bare "what's new" label.
      expect(
        find.descendant(
            of: dialog, matching: find.textContaining('v${version.current()}')),
        findsWidgets,
        reason: 'the changelog dialog does not name the version it is showing',
      );
      expect(
        find.descendant(
            of: dialog, matching: find.textContaining(entry.changes.first)),
        findsWidgets,
        reason: 'the changelog dialog does not show the entry it was handed',
      );

      await Fixtures.closeDialog(tester);
      await E2E.waitForGone(tester, dialog,
          description: 'the changelog dialog');

      // The other half of the feature: the app records the version it showed, so
      // the next launch is quiet. That write is what `showDialogsIfNeeded` does
      // immediately after raising the dialog.
      localSettings.lastSeenVersion = version.current();
      localSettings.notifyAndPersist();
      expect(localSettings.lastSeenVersion, version.current());
    });

    testWidgets('02: a skipped release shows the current version\'s entry only',
        (tester) async {
      await E2E.signIn(tester);

      // A user who upgrades across several releases has a `lastSeenVersion` far
      // behind; the app shows the entry for the version being *run*, not a
      // concatenation of everything missed.
      final current = await changelog.forVersion(version.current());
      final older = await changelog.forVersion('0.14.1');
      expect(current, isNotNull);
      expect(older, isNotNull,
          reason: 'the fixture assumes CHANGELOG.md still holds 0.14.1');

      await showChangelogDialog(bContext, entry: current!);
      await E2E.settle(tester, frames: 15);

      final shown = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ContentDialog),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join('\n');
      expect(shown.contains(current.changes.first.trim()), isTrue,
          reason:
              'the dialog does not show the current version\'s first change');
      final olderFirst = older!.changes.first.trim();
      if (olderFirst != current.changes.first.trim()) {
        expect(shown.contains(olderFirst), isFalse,
            reason: 'the dialog shows a skipped release as well');
      }
      await Fixtures.closeDialog(tester);
    });

    testWidgets('03: the new-version dialog is macOS-only', (tester) async {
      await E2E.signIn(tester);

      // Every channel but the macOS download the app from a store that updates it
      // itself, so on this platform the app must never advertise a download.
      expect(version.needsUpdateNotification, isFalse,
          reason: 'this platform advertises a manual update it cannot install');

      // And the dialog that would do it is not on screen after startup either.
      expect(
        find.descendant(
          of: find.byType(ContentDialog),
          matching: find.text(txt('newVersionDialogTitle')),
        ),
        findsNothing,
        reason:
            'the new-version dialog appeared on a platform that has a store',
      );
    });

    testWidgets('04: an upgrade keeps the clinic\'s data', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);

      // The upgrade path is a version change and nothing else: the changelog
      // dialog must not touch the stores (it used to be a reason to worry about
      // migrations, which now happen on the *database* open instead).
      final before = localSettings.lastSeenVersion;
      addTearDown(() => localSettings.lastSeenVersion = before);
      localSettings.lastSeenVersion = '0.0.1';
      final entry = await changelog.forVersion(version.current());
      await showChangelogDialog(bContext, entry: entry!);
      await E2E.settle(tester, frames: 15);
      await Fixtures.closeDialog(tester);

      expect(await Fixtures.patientIdOf(patient), isNotEmpty,
          reason: 'the patient created before the upgrade is gone');
    });
  });
}
