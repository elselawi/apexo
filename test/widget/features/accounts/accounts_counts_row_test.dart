// The accounts counts row overflowed at 300px (by 5.3px, and 16px from the
// refresh button), so it is pinned here instead of in the e2e harness.
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/transitions/rotate.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

/// The row as the screen builds it. A `Wrap`, not a `Row`: at 300px a `Row`
/// reports an overflow of 261px.
Widget countsRow(BuildContext context) {
  return Container(
    decoration: topBarDecoration(context, Colors.grey),
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 20,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Button(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RotatingWrapper(
                rotate: false,
                child: Icon(Icons.sync),
              ),
              const SizedBox(width: 5),
              Txt(txt("refresh")),
            ],
          ),
          onPressed: () {},
        ),
        Txt(txt("${txt("admins")}: 3")),
        Txt(txt("${txt("users")}: 12")),
      ],
    ),
  );
}

void main() {
  for (final double width in const [1280, 1264, 710, 300]) {
    testWidgets('the counts row fits a ${width.toInt()}px window',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        FluentApp(
          home: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: countsRow(context)),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'the counts row overflowed at ${width.toInt()}px');
    });
  }
}
