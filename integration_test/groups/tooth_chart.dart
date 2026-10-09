// The teeth chart: its nodes, its labels, and — the point of this group — *where
// a tap lands*. §4.2.
//
// A dental chart that records a condition on the wrong tooth is a clinical bug,
// and one was written down: the node for tooth 11 opened 12. The incisors'
// bounding boxes overlap their neighbours, so an activation delivered at the
// *label's* centre landed on the tooth drawn after it — `TeethSelector`'s own
// comment records it, and the fix was to attach the action to the tooth's node
// instead of to a label-only semantics node. Nothing asserted that fix until now;
// the first two tests here are that regression.
//
// The chart is driven through the patient panel's dental-notes tab, which is the
// chart a user actually edits. Conditions are recorded into the panel's *draft*,
// which is exactly what the tooth keys reflect (`WK.tooth(iso, selected:)`), so a
// test can see which tooth a tap recorded without saving anything to the record.
import 'package:apexo/features/settings/settings_stores.dart'
    show localSettings;
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

/// The 32 permanent teeth in FDI/ISO notation — the chart's own keys.
const _isoTeeth = [
  '11', '12', '13', '14', '15', '16', '17', '18', //
  '21', '22', '23', '24', '25', '26', '27', '28', //
  '31', '32', '33', '34', '35', '36', '37', '38', //
  '41', '42', '43', '44', '45', '46', '47', '48', //
];

/// The text drawn *inside* the node of a clean tooth [iso].
///
/// Scoped to the node on purpose: in Palmer notation every quadrant's first
/// tooth is labelled `1`, so a bare `find.text('1')` would match four teeth.
Finder _node(String iso) => find.byKey(WK.tooth(iso, selected: false));

/// Sets the device's dental notation directly and lets the chart rebuild.
///
/// This group is about how the chart renders the notation it was given; the
/// settings card path is exercised in `settings_general`/`localization_rtl`.
Future<void> _useNotation(WidgetTester tester, String code) async {
  if (localSettings.dentalNotation == code) return;
  localSettings.dentalNotation = code;
  localSettings.notifyAndPersist();
  await E2E.settle(tester, frames: 20);
  expect(localSettings.dentalNotation, code,
      reason: 'changing the dental notation to "$code" did not stick');
}

void registerToothChartTests() {
  group('tooth_chart', () {
    /// A fresh patient's dental-notes tab — an empty chart, all 32 teeth.
    Future<void> openChart(WidgetTester tester) async {
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'dentalNotes');
      await E2E.waitFor(tester, find.byKey(WK.tooth('11', selected: false)),
          description: 'the teeth chart');
    }

    testWidgets('01: every permanent tooth is drawn and keyed by its ISO code',
        (tester) async {
      await E2E.signIn(tester);
      await openChart(tester);

      for (final iso in _isoTeeth) {
        expect(find.byKey(WK.tooth(iso, selected: false)), findsOneWidget,
            reason: 'tooth $iso is not on the chart');
      }
      await Fixtures.closePanel(tester);
    });

    testWidgets('02: a tap records the condition on the tooth it was drawn on',
        (tester) async {
      await E2E.signIn(tester);
      await openChart(tester);

      // The regression: this used to land on 12. The neighbours are asserted
      // too, because "recorded somewhere" is not the claim — "recorded on this
      // tooth and no other" is.
      await Fixtures.setToothCondition(tester, '11', 'filling');

      expect(find.byKey(WK.tooth('11', selected: true)), findsOneWidget,
          reason: 'the condition was not recorded on tooth 11');
      expect(find.byKey(WK.tooth('12', selected: false)), findsOneWidget,
          reason:
              'tooth 12 took the condition meant for 11 — the reported bug');
      expect(find.byKey(WK.tooth('21', selected: false)), findsOneWidget,
          reason: 'tooth 21 took the condition meant for 11');
      await Fixtures.closePanel(tester);
    });

    testWidgets('03: two teeth keep their own conditions', (tester) async {
      await E2E.signIn(tester);
      await openChart(tester);

      await Fixtures.setToothCondition(tester, '36', 'filling');
      await Fixtures.setToothCondition(tester, '37', 'caries');

      expect(find.byKey(WK.tooth('36', selected: true)), findsOneWidget);
      expect(find.byKey(WK.tooth('37', selected: true)), findsOneWidget);
      for (final clean in ['35', '38', '46']) {
        expect(find.byKey(WK.tooth(clean, selected: false)), findsOneWidget,
            reason: 'tooth $clean picked up a neighbour\'s condition');
      }
      await Fixtures.closePanel(tester);
    });

    testWidgets('04: the label inside a tooth follows the notation',
        (tester) async {
      await E2E.signIn(tester);
      final original = localSettings.dentalNotation;
      addTearDown(() async => _useNotation(tester, original));

      // Palmer is the app's default: the label is the tooth's own digit, and the
      // quadrant is drawn as the cell's borders. Setting it here rather than
      // assuming it keeps the test honest on a device that was left differently.
      await _useNotation(tester, 'p');
      await openChart(tester);
      expect(Fixtures.labelText(tester, _node('11')), '1',
          reason: 'Palmer notation should label tooth 11 "1"');
      expect(Fixtures.labelText(tester, _node('48')), '8',
          reason: 'Palmer notation should label tooth 48 "8"');
      await Fixtures.closePanel(tester);

      // ISO: the full two-digit code.
      await _useNotation(tester, 'i');
      await openChart(tester);
      expect(Fixtures.labelText(tester, _node('11')), '11',
          reason: 'ISO notation should label tooth 11 "11"');
      expect(Fixtures.labelText(tester, _node('48')), '48');
      await Fixtures.closePanel(tester);

      // Universal: the FDI number mapped to 1-32, starting at the upper-right
      // third molar (tooth 18 is 1, so tooth 11 is 8 and tooth 48 is 32).
      await _useNotation(tester, 'u');
      await openChart(tester);
      expect(Fixtures.labelText(tester, _node('18')), '1');
      expect(Fixtures.labelText(tester, _node('11')), '8');
      expect(Fixtures.labelText(tester, _node('48')), '32');
      await Fixtures.closePanel(tester);
    });

    testWidgets('05: the state wheel names the tooth it will write to',
        (tester) async {
      await E2E.signIn(tester);
      final original = localSettings.dentalNotation;
      addTearDown(() async => _useNotation(tester, original));

      // ISO, so the tooth's own name is on screen inside the wheel and can be
      // asserted: with Palmer the wheel would say "6" and the chart would too.
      await _useNotation(tester, 'i');
      await openChart(tester);

      await E2E.tap(tester, _node('36'), description: 'tooth 36');
      final wheel = find.byType(FlyoutContent);
      await E2E.waitFor(tester, wheel, description: 'the tooth state wheel');
      expect(
        find.descendant(of: wheel, matching: find.text('36')),
        findsWidgets,
        reason: 'the wheel does not say which tooth it is editing',
      );
      await E2E.tap(
        tester,
        find.descendant(
          of: wheel,
          matching: find.widgetWithText(FilledButton, txt('close')),
        ),
        description: 'the tooth wheel close button',
      );
      await Fixtures.closePanel(tester, allowPrompt: true);
    });
  });
}
