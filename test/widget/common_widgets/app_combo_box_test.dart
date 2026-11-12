@Tags(['serial'])
library;

import 'package:apexo/common_widgets/app_combo_box.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('AppComboBox is as tall as a text field', (tester) async {
    final key = GlobalKey();
    await pumpApexoApp(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: AppComboBox<String>(
              key: key,
              isExpanded: true,
              items: const [ComboBoxItem(value: 'a', child: Text('A'))],
              value: 'a',
            ),
          ),
        ],
      ),
    );

    expect(tester.getSize(find.byKey(key)).height, kTextFieldHeight);
  });

  testWidgets('AppComboBox still opens and selects items', (tester) async {
    String? selected;
    await pumpApexoApp(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: AppComboBox<String>(
              isExpanded: true,
              value: 'a',
              items: const [
                ComboBoxItem(value: 'a', child: Text('A')),
                ComboBoxItem(value: 'b', child: Text('B')),
              ],
              onChanged: (value) => selected = value,
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();

    expect(selected, 'b');
  });
}
