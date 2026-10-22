// The accounts screen's counts row, off the e2e harness.
//
// `lifecycle_platform 05` (a 300px window, via a 1280px desktop window first)
// reported `A RenderFlex overflowed by 5.3 pixels on the right` from
// `accounts_screen.dart`'s counts row, and 16px from the refresh button inside
// it. A layout overflow reds whatever test is running, so the row is pinned
// here where it costs a second to check instead of a minute.
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/transitions/rotate.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

/// The row as the screen builds it: a refresh button and two counts.
///
/// It is a `Wrap`, not a `Row`: the strip is drawn at every width the app
/// allows (a phone layout is 300px), and a `Row` lays its children out at their
/// natural width and then reports an overflow by 261px at 300px.
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
