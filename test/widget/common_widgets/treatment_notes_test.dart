import 'package:apexo/common_widgets/item_title.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('original treatment label shows note without opening tooltip',
      (tester) async {
    await pumpApexoApp(
        tester,
        SizedBox(
            width: 320,
            child: TreatmentLabels(
              showPalmer: true,
              labels: [
                TreatmentLabel(
                    string: 'filling',
                    color: Colors.blue,
                    icon: WindowsIcons.edit,
                    iso: '11',
                    extraNote: 'Review sensitivity at next appointment')
              ],
            )));
    expect(find.text('Review sensitivity at next appointment'), findsOneWidget);
    expect(find.byType(SingleTreatmentLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
