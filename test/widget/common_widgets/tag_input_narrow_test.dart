import 'package:apexo/common_widgets/tag_input.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('a narrow, full tag field has valid constraints', (tester) async {
    await pumpApexoApp(
      tester,
      SizedBox(
        width: 7,
        child: TagInputWidget(
          suggestions: const [],
          initialValue: [
            TagInputItem(value: 'patient', label: 'Patient'),
          ],
          strict: false,
          limit: 1,
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
