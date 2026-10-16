import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/common_widgets/teeth_selector/opg_dental_chart.dart';
import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  void setWideViewport(WidgetTester tester,
      {double width = 1400, double height = 900}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'wide viewport automatically renders the OPG panoramic chart with all 32 permanent teeth',
      (tester) async {
    setWideViewport(tester);

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          onNote: (iso, note) {},
          type: StateType.state,
        ),
      ),
    );

    expect(find.byType(OpgDentalChart), findsOneWidget);
    expect(find.byKey(const ValueKey('opg-dental-chart')), findsOneWidget);

    for (final iso in [...kOpgUpperPermanent, ...kOpgLowerPermanent]) {
      expect(
        find.byKey(WK.tooth(iso, selected: false)),
        findsOneWidget,
        reason: 'permanent tooth $iso must be rendered on the OPG chart',
      );
    }
  });

  testWidgets(
      'OPG chart arranges upper teeth 18..11 then 21..28 from left to right',
      (tester) async {
    setWideViewport(tester);

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          onNote: (iso, note) {},
          type: StateType.state,
        ),
      ),
    );

    double? previousCenterDx;
    for (final iso in kOpgUpperPermanent) {
      final center =
          tester.getCenter(find.byKey(WK.tooth(iso, selected: false)));
      if (previousCenterDx != null) {
        expect(
          center.dx,
          greaterThan(previousCenterDx),
          reason:
              'tooth $iso should be positioned to the right of the previous tooth in OPG view',
        );
      }
      previousCenterDx = center.dx;
    }

    // Upper teeth sit above lower teeth
    final upper11 =
        tester.getCenter(find.byKey(WK.tooth('11', selected: false)));
    final lower41 =
        tester.getCenter(find.byKey(WK.tooth('41', selected: false)));
    expect(upper11.dy, lessThan(lower41.dy));
  });

  testWidgets(
      'OPG chart opens ToothStateWheel on tap and records condition & extra notes on the exact tooth',
      (tester) async {
    setWideViewport(tester);
    final current = <String, String>{};
    final extra = <String, String>{};

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          type: StateType.treatment,
          currentNotes: current,
          extraNotes: extra,
          onNote: (iso, value) {
            if (value == null) {
              current.remove(iso);
              extra.remove(iso);
            } else {
              current[iso] = value;
            }
          },
          onExtraNote: (iso, text) => extra[iso] = text,
        ),
      ),
    );

    await tester.tap(find.byKey(WK.tooth('11', selected: false)));
    await tester.pumpAndSettle();

    final wheel = tester.widget<ToothStateWheel>(find.byType(ToothStateWheel));
    expect(wheel.iso, '11');

    await tester.tap(find.text(txt('filling')).first);
    await tester.pumpAndSettle();

    expect(current, {'11': 'filling'});
    expect(find.byKey(WK.tooth('11', selected: true)), findsOneWidget);
    expect(find.byKey(WK.tooth('12', selected: false)), findsOneWidget);

    final field = tester.widget<LiveTranscribingTextField>(
        find.byType(LiveTranscribingTextField));
    field.controller!.text = 'Mesial composite';
    field.onChanged!('Mesial composite');
    await tester.pumpAndSettle();
    expect(extra, {'11': 'Mesial composite'});

    await tester.tap(find.byKey(const ValueKey('wheel-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ToothStateWheel), findsNothing);

    // Inline history strip below tooth 11 shows the recorded note
    expect(find.text('Mesial composite'), findsOneWidget);
  });

  testWidgets(
      'OPG chart displays per-tooth history and appointment notes beside the tooth and opens wheel when tapped',
      (tester) async {
    setWideViewport(tester);

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          type: StateType.treatment,
          currentNotes: const {'36': 'crown'},
          oldNotes: const {'16': 'rCT'},
          history: [
            ToothHistory(
              label: '2026-05-10',
              date: DateTime(2026, 5, 10),
              appointmentId: 'apt-16',
              teeth: const {'16': 'rCT'},
              notes: const {'16': '3 canals obturated'},
            ),
          ],
          onNote: (iso, note) {},
        ),
      ),
    );

    expect(find.text('3 canals obturated'), findsOneWidget);
    // Date is kept in the tooltip, not cluttering the 90-degree rotated text beside the tooth
    expect(find.text('2026-05-10'), findsNothing);

    // Tooltip on a tooth with history/notes shows its history/notes rather than the tooth name,
    // while a clean tooth with no history/notes shows its tooth name.
    final tooltip16 = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const ValueKey('opg-col-16')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip16.message, contains('2026-05-10'));
    expect(tooltip16.message, contains('3 canals obturated'));

    final tooltip11 = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const ValueKey('opg-col-11')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip11.message, 'Tooth 11');

    // Tapping the rotated text beside tooth 16 opens the selection wheel rather than jumping to the appointment
    await tester.tap(find.text('3 canals obturated'));
    await tester.pumpAndSettle();
    expect(find.byType(ToothStateWheel), findsOneWidget);
  });

  testWidgets('OPG chart toggles primary dentition on and off cleanly',
      (tester) async {
    setWideViewport(tester);

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          onNote: (iso, note) {},
          type: StateType.state,
        ),
      ),
    );

    expect(find.byKey(WK.tooth('51', selected: false)), findsNothing);

    await tester.tap(find.text(txt('showPrimary')).first);
    await tester.pumpAndSettle();

    for (final iso in [...kOpgUpperPrimary, ...kOpgLowerPrimary]) {
      expect(
        find.byKey(WK.tooth(iso, selected: false)),
        findsOneWidget,
        reason: 'primary tooth $iso must appear when Show Primary is checked',
      );
    }
  });

  testWidgets('every tooth on OPG chart exposes semantics tap action',
      (tester) async {
    setWideViewport(tester);
    final handle = tester.ensureSemantics();

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          onNote: (iso, note) {},
          type: StateType.state,
        ),
      ),
    );

    for (final iso in ['11', '12', '13', '14', '16', '21', '36', '48']) {
      final finder = find.bySemanticsLabel('Tooth $iso');
      expect(finder, findsOneWidget);
      final data = tester.getSemantics(finder).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }

    handle.dispose();
  });

  testWidgets(
      'OPG chart renders all treatment visual layers, overlapping history, apex icon without circle, and rotated beside-tooth text',
      (tester) async {
    setWideViewport(tester);
    final openedAppointments = <String>[];

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          type: StateType.treatment,
          currentNotes: const {
            '11': 'filling',
            '12': 'veneer',
            '13': 'ortho',
            '14': 'pulpotomy',
            '15': 'temporary',
            '16': 'crown',
            '21': 'surgery',
            '24': 'overlay',
            '26': 'implant',
            '36': 'bridge',
            '37': 'pontic',
            '46': 'extraction',
          },
          oldNotes: const {
            '16': 'rCT',
            '31': 'recession',
            '32': 'caries',
            '33': 'fractured',
            '34': 'mobility',
            '35': 'clean',
            '41': 'whitening',
            '42': 'malposition',
            '43': 'impacted',
            '44': 'rroot',
            '45': 'rprimary',
          },
          history: [
            ToothHistory(
              label: '2026-04-01',
              date: DateTime(2026, 4, 1),
              appointmentId: 'apt-rct-16',
              teeth: const {'16': 'rCT'},
              notes: const {'16': 'MB2 canal located'},
            ),
            ToothHistory(
              label: '2026-05-10',
              date: DateTime(2026, 5, 10),
              appointmentId: 'apt-fill-16',
              teeth: const {'16': 'filling'},
              notes: const {'16': 'Core build-up'},
            ),
          ],
          onOpenAppointment: openedAppointments.add,
          onNote: (iso, note) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // RotatedBox (quarterTurns: 3 = 90 degrees counter-clockwise) is used for beside-tooth notes
    final rotatedBoxes = tester
        .widgetList<RotatedBox>(find.descendant(
          of: find.byKey(const ValueKey('opg-col-16')),
          matching: find.byType(RotatedBox),
        ))
        .toList();
    expect(rotatedBoxes, isNotEmpty);
    expect(rotatedBoxes.first.quarterTurns, 3);

    // Historical-only teeth use neutral radiographic color for their apex icon,
    // whereas current-draft teeth keep their vibrant treatment color.
    final histIcon = tester.widget<Icon>(
      find
          .descendant(
            of: find.byKey(const ValueKey('opg-col-32')),
            matching: find.byType(Icon),
          )
          .first,
    );
    final currentIcon = tester.widget<Icon>(
      find
          .descendant(
            of: find.byKey(const ValueKey('opg-col-11')),
            matching: find.byType(Icon),
          )
          .first,
    );
    expect(histIcon.color, isNot(equals(labelToColor('caries'))));
    expect(currentIcon.color, equals(labelToColor('filling')));
  });

  testWidgets(
      'OPG chart hides duplicate historical icon and beside-tooth text when current chart has the same treatment',
      (tester) async {
    setWideViewport(tester);

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          type: StateType.treatment,
          currentNotes: const {'11': 'filling'},
          oldNotes: const {'11': 'filling'},
          history: [
            ToothHistory(
              label: '2026-04-01',
              date: DateTime(2026, 4, 1),
              appointmentId: 'apt-11',
              teeth: const {'11': 'filling'},
              notes: const {},
            ),
          ],
          onNote: (iso, note) {},
        ),
      ),
    );

    final col11 = find.byKey(const ValueKey('opg-col-11'));
    // Only one icon (colored for current draft) and one rotated text tag for 'filling'
    final icons = tester.widgetList<Icon>(
      find.descendant(of: col11, matching: find.byType(Icon)),
    );
    expect(icons.length, 1);
    expect(icons.first.color, equals(labelToColor('filling')));

    final rotatedTags = tester.widgetList<RotatedBox>(
      find.descendant(of: col11, matching: find.byType(RotatedBox)),
    );
    expect(rotatedTags.length, 1);
  });

  testWidgets(
      'phone / narrow screen bends each jaw into one 16-tooth arch that fits without scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          type: StateType.treatment,
          currentNotes: const {'11': 'filling', '36': 'crown'},
          oldNotes: const {'26': 'rCT'},
          onNote: (iso, note) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(OpgDentalChart), findsOneWidget);

    const selected = {'11', '36'};
    Offset centerOf(String iso) => tester.getCenter(
          find.byKey(WK.tooth(iso, selected: selected.contains(iso))),
        );

    // Every permanent tooth of the arch is drawn, inside the phone's width.
    for (final iso in [...kOpgUpperPermanent, ...kOpgLowerPermanent]) {
      final finder = find.byKey(
        WK.tooth(iso, selected: selected.contains(iso)),
      );
      expect(finder, findsOneWidget, reason: 'tooth $iso is missing');
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }

    // Patient's right first: 18..11 then 21..28, left to right.
    expect(centerOf('18').dx, lessThan(centerOf('11').dx));
    expect(centerOf('11').dx, lessThan(centerOf('21').dx));
    expect(centerOf('21').dx, lessThan(centerOf('28').dx));
    expect(centerOf('48').dx, lessThan(centerOf('41').dx));
    expect(centerOf('31').dx, lessThan(centerOf('38').dx));

    // Ovoid / pyramidal arch shape: each posterior pair widens progressively
    // from canine (3) -> first premolar (4) -> second premolar (5) -> first
    // molar (6) -> second molar (7) -> wisdom tooth (8).
    double pairSpan(String leftIso, String rightIso) =>
        (centerOf(rightIso).dx - centerOf(leftIso).dx).abs();

    expect(pairSpan('12', '22'), greaterThan(pairSpan('11', '21')));
    expect(pairSpan('13', '23'), greaterThan(pairSpan('12', '22')));
    expect(pairSpan('14', '24'), greaterThan(pairSpan('13', '23')));
    expect(pairSpan('15', '25'), greaterThan(pairSpan('14', '24')));
    expect(pairSpan('16', '26'), greaterThan(pairSpan('15', '25')));
    expect(pairSpan('17', '27'), greaterThan(pairSpan('16', '26')));
    expect(pairSpan('18', '28'), greaterThan(pairSpan('17', '27')));

    expect(pairSpan('43', '33'), greaterThan(pairSpan('42', '32')));
    expect(pairSpan('44', '34'), greaterThan(pairSpan('43', '33')));
    expect(pairSpan('45', '35'), greaterThan(pairSpan('44', '34')));
    expect(pairSpan('46', '36'), greaterThan(pairSpan('45', '35')));
    expect(pairSpan('47', '37'), greaterThan(pairSpan('46', '36')));
    expect(pairSpan('48', '38'), greaterThan(pairSpan('47', '37')));

    // One arch per jaw, not a second row: the front teeth stand across the top
    // of the mouth and the back ones run down its sides.
    expect(centerOf('11').dy, lessThan(centerOf('18').dy));
    expect(centerOf('21').dy, lessThan(centerOf('28').dy));
    expect(centerOf('41').dy, greaterThan(centerOf('48').dy));
    expect(centerOf('31').dy, greaterThan(centerOf('38').dy));

    // The two jaws face each other across the middle of the mouth: the upper
    // arch sits above the lower one everywhere, back teeth included.
    expect(centerOf('11').dy, lessThan(centerOf('41').dy));
    expect(centerOf('18').dy, lessThan(centerOf('48').dy));
    expect(centerOf('28').dy, lessThan(centerOf('38').dy));

    // The incisors stand upright across the anterior segment, while the canines
    // sit at the corner angle where the arch bends into the buccal segments.
    expect((centerOf('11').dy - centerOf('12').dy).abs(), lessThan(6));
    expect(centerOf('13').dy, greaterThan(centerOf('12').dy + 4));
    expect(centerOf('14').dy, greaterThan(centerOf('13').dy + 8));
    expect((centerOf('41').dy - centerOf('42').dy).abs(), lessThan(6));
    expect(centerOf('43').dy, lessThan(centerOf('42').dy - 4));

    // The mouth is centred on the panel's midline, and the two sides mirror
    // each other: the incisors sit level to either side of it.
    final midline =
        tester.getRect(find.byKey(const ValueKey('opg-dental-chart'))).width /
            2;
    expect(centerOf('11').dx + centerOf('21').dx, closeTo(midline * 2, 1));
    expect(centerOf('11').dy, closeTo(centerOf('21').dy, 1));
    expect(centerOf('41').dx + centerOf('31').dx, closeTo(midline * 2, 1));

    // The arch reaches out to the panel's sides, so no width is left unused.
    final chartWidth =
        tester.getRect(find.byKey(const ValueKey('opg-dental-chart'))).width;
    expect(centerOf('18').dx, lessThan(chartWidth * 0.22));
    expect(centerOf('28').dx, greaterThan(chartWidth * 0.78));

    // The whole chart fits the phone's height with room to spare for the
    // panel's own chrome: nothing here has to scroll.
    expect(
      tester.getRect(find.byKey(const ValueKey('opg-dental-chart'))).height,
      lessThanOrEqualTo(740 - 190),
    );

    // The switches pick one dentition: turning the primary teeth on shows them
    // in place of the permanent ones, in the same space and without overflow.
    await tester.tap(find.text(txt('showPrimary')).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(WK.tooth('16', selected: false)), findsNothing);
    for (final iso in [...kOpgUpperPrimary, ...kOpgLowerPrimary]) {
      final rect = tester.getRect(find.byKey(WK.tooth(iso, selected: false)));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
    expect(
      tester.getRect(find.byKey(const ValueKey('opg-dental-chart'))).height,
      lessThanOrEqualTo(740 - 190),
    );

    //And back again: the permanent teeth return and the primary ones go.
    await tester.tap(find.text(txt('showPermanent')).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(WK.tooth('16', selected: false)), findsOneWidget);
    expect(find.byKey(WK.tooth('55', selected: false)), findsNothing);

    // Tapping each tooth's visual center on the curved arch opens that exact
    // tooth's wheel, without adjacent rotated cells stealing the hit.
    for (final iso in [
      '11',
      '12',
      '13',
      '14',
      '15',
      '16',
      '17',
      '18',
      '33',
      '46'
    ]) {
      final finder =
          find.byKey(WK.tooth(iso, selected: selected.contains(iso)));
      await tester.tapAt(tester.getCenter(finder));
      await tester.pumpAndSettle();

      final wheel =
          tester.widget<ToothStateWheel>(find.byType(ToothStateWheel));
      expect(
        wheel.iso,
        iso,
        reason:
            'tapping center of compact tooth $iso should open $iso, not ${wheel.iso}',
      );

      await tester.tap(find.byKey(const ValueKey('wheel-close')));
      await tester.pumpAndSettle();
    }
  });

  test(
      'computePanelWidth widens dental tabs on wide screens, fills phone width, and preserves 350px elsewhere',
      () {
    // Phone screen (< 490): fills the full screen width even when not minimized
    expect(
      computePanelWidth(
        screenWidth: 360,
        minimized: false,
        activeTabTitleKey: 'dentalNotes',
      ),
      360,
    );

    // Narrow tablet screen on dental tab: widens to 440 for the compact arch
    expect(
      computePanelWidth(
        screenWidth: 800,
        minimized: false,
        activeTabTitleKey: 'dentalNotes',
      ),
      440,
    );

    // Narrow tablet screen on non-dental tab: stays 350
    expect(
      computePanelWidth(
        screenWidth: 800,
        minimized: false,
        activeTabTitleKey: 'patientDetails',
      ),
      350,
    );

    // Wide screen on non-dental tab (e.g. patientDetails): stays 350
    expect(
      computePanelWidth(
        screenWidth: 1600,
        minimized: false,
        activeTabTitleKey: 'patientDetails',
      ),
      350,
    );

    // Wide screen on dentalNotes or operativeDetails: widens up to kOpgWidePanelWidth
    expect(
      computePanelWidth(
        screenWidth: 1600,
        minimized: false,
        activeTabTitleKey: 'dentalNotes',
      ),
      kOpgWidePanelWidth,
    );
    expect(
      computePanelWidth(
        screenWidth: 1600,
        minimized: false,
        activeTabTitleKey: 'operativeDetails',
      ),
      kOpgWidePanelWidth,
    );
  });
}
