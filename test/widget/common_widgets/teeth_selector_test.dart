import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// A tooth whose bounding-box centre is inside its own outline, and the two
/// incisors whose centre falls outside it — the pair the web QA pass caught the
/// accessibility node for: the node for tooth 11 opened 12, and 12 opened 13.
const incisorsAndNeighbours = ['11', '12', '13', '14', '21', '33'];

Future<void> pumpTeethSelector(WidgetTester tester) => pumpApexoApp(
      tester,
      SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: TeethSelector(
            notation: (iso) => 'Tooth $iso',
            onNote: (iso, note) {},
            type: StateType.state,
          ),
        ),
      ),
    );

void main() {
  testWidgets('every tooth exposes one node with its own tap action',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTeethSelector(tester);

    for (final iso in incisorsAndNeighbours) {
      final finder = find.bySemanticsLabel('Tooth $iso');
      expect(finder, findsOneWidget, reason: 'tooth $iso must have a node');

      final data = tester.getSemantics(finder).getSemanticsData();
      // The action is what makes an assistive activation open *this* tooth:
      // without it the node is a label only, and the activation is delivered as
      // a synthetic pointer event at the node's centre.
      expect(
        data.hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'tooth $iso must be activatable',
      );
    }

    handle.dispose();
  });

  for (final iso in incisorsAndNeighbours) {
    testWidgets('activating the $iso node opens tooth $iso, not its neighbour',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTeethSelector(tester);

      final node = tester.getSemantics(find.bySemanticsLabel('Tooth $iso'));
      // The action an assistive technology or a `flt-tappable` click dispatches
      // — deliberately not a pointer tap, which is what used to land on the
      // neighbouring tooth.
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      final wheel =
          tester.widget<ToothStateWheel>(find.byType(ToothStateWheel));
      expect(wheel.iso, iso, reason: 'tooth $iso opened ${wheel.iso}');

      handle.dispose();
    });
  }
}
