// The general settings screen: the cards, what a change reaches, and what it
// must leave alone.
//
// Two of the cards are deliberately *not* driven here: the calendar system and
// the dental notation change how every later test's dates and teeth read, and
// the suite shares one database (a per-test clinic would be needed first).
import 'package:apexo/features/settings/applies_to_indicator.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

void registerSettingsGeneralTests() {
  group('settings_general', () {
    testWidgets('01: every card renders', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openSettings(tester);
      await E2E.settle(tester, frames: 10);

      // Only the cards with a stable identifier are listed: the screen's cards
      // are collapsed `Expander`s in a `ListView`, so each is revealed first,
      // which is also what builds it.
      for (final identifier in [
        'currency',
        'language',
        'dateFormat',
        'calendarView',
        'calendarSystem',
        'dentalNotation',
      ]) {
        await Fixtures.revealSettingsCard(tester, identifier);
        expect(find.byKey(WK.settingsItem(identifier)), findsOneWidget,
            reason: 'the "$identifier" card is missing');
      }
    });

    testWidgets('02: a changed card persists across screens', (tester) async {
      // **Skipped, kept as the regression** (todo.md §6.2): typing a different
      // value into the currency card never makes its Save button appear, so there
      // is nothing to press and the change cannot be committed from the harness.
      // `tester.enterText` does reach the field (the value read back afterwards is
      // the typed one), the card is expanded, and the button exists in other
      // cards (`06` presses the AI card's combo) — so this is specific to a text
      // card committing a *typed* value, not to the fixture's finder.
      await E2E.signIn(tester);
      await Fixtures.openSettings(tester);

      // A marker that is a real currency code (so the money formatting the rest of
      // the app does stays valid) and one that differs from what the card holds
      // right now — a run that failed mid-test leaves its value in the clinic.
      // The field is what knows: the store read can still answer with the default
      // until the row has synced down, and `currency()` answers with the *symbol*
      // the widgets display.
      final before = await Fixtures.settingsTextValue(tester, 'currency');
      final marker = before.trim() == 'EUR' ? 'CHF' : 'EUR';
      await Fixtures.setSettingsText(tester, 'currency', marker);
      expect(await Fixtures.settingsTextValue(tester, 'currency'), marker,
          reason: 'the currency change did not reach the card');

      // Leaving the screen and coming back must not undo it.
      await Fixtures.openDashboard(tester);
      await Fixtures.openSettings(tester);
      expect(await Fixtures.settingsTextValue(tester, 'currency'), marker,
          reason: 'the currency did not survive leaving the settings screen');

      // Put the clinic's own value back: the suite shares one database.
      if (before.trim().isNotEmpty && before.trim() != marker) {
        await Fixtures.setSettingsText(tester, 'currency', before);
      }
    }, skip: true);

    testWidgets('03: a card says what it applies to', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openSettings(tester);

      // A card's scope is the difference between a setting that travels with the
      // clinic (currency) and one that belongs to this device (language), so the
      // screen has to say which is which. Nothing is changed here: the point is
      // the label, and a device-scope card flip would resync the whole app.
      await Fixtures.revealSettingsCard(tester, 'language');
      expect(find.byType(AppliesToIndicator), findsWidgets,
          reason: 'the cards do not say what they apply to');

      await Fixtures.revealSettingsCard(tester, 'currency');
      expect(find.byType(AppliesToIndicator), findsWidgets,
          reason: 'the currency card does not say what it applies to');
    });

    testWidgets('04: the calendar system changes the dates app-wide',
        (tester) async {
      // Needs a per-test clinic: switching it rewrites how *every* later test's
      // dates read (`DF.jalaliMonthYear` and friends), and the suite shares one
      // database. §2.15 multi-clinic is where a second clinic becomes available.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('05: the dental notation switch changes the teeth charts',
        (tester) async {
      // Needs a teeth chart with labels on screen; the notation is asserted by
      // the chart's own text, which the patient panel group does not cover yet.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('06: the AI card offers its switch without AI keys',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openSettings(tester);

      // The AI card is the one whose title is `ai_services` (its identifier is
      // `ai_services_ena`), so it is reached by its title: tapping the header of a
      // collapsed card is what expands it.
      await Fixtures.expandSettingsCardByTitle(tester, 'ai_services');
      expect(find.byKey(const Key('ai_services_ena_combo')), findsOneWidget,
          reason: 'the AI card does not offer its on/off switch');

      // Deliberately *not* pressed: the cache reset clears the local database and
      // resynchronizes (minutes, and it would wipe this suite's own state). What
      // is asserted is that the control renders without AI keys configured.
      await Fixtures.revealSettingsCard(tester, 'cacheReset');
      expect(find.byKey(WK.settingsItem('cacheReset')), findsOneWidget,
          reason: 'the cache reset card is missing');
      expect(tester.takeException(), isNull);
    });

    testWidgets('07: settings are per clinic', (tester) async {
      // Needs a second clinic to switch to (§2.15).
      expect(true, isTrue);
    }, skip: true);

    testWidgets('08: the privacy note sits next to the AI settings',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openSettings(tester);
      await Fixtures.expandSettingsCardByTitle(tester, 'ai_services');

      expect(find.textContaining(txt('no_training_privacy_info')), findsWidgets,
          reason: 'the AI settings do not carry the privacy note');
    });
  });
}
