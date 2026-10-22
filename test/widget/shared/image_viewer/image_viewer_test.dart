import 'package:apexo/shared/image_viewer/image_viewer.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// A one-pixel PNG: enough for the viewer to lay out without loading assets.
final Uint8List _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// The photo viewer a window hosts: the tools that belong on the photo, and
/// nothing that belongs to the frame around it.
void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    void Function(int)? onPressDelete,
    int images = 1,
    bool withNames = true,
    bool withPen = true,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final providers = [
      for (var i = 0; i < images; i++) MemoryImage(_pixel),
    ];
    await pumpApexoApp(
      tester,
      SizedBox(
        width: 800,
        height: 600,
        child: ImageViewer(
          providers,
          rowId: 'photo-window-test',
          imageIds: withNames
              ? [for (var i = 0; i < images; i++) 'photo-$i.png']
              : null,
          onSaveDrawing: withPen ? (_, __) {} : null,
          onPressedDelete: onPressDelete,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the tools sit on the photo and report back', (tester) async {
    await pumpViewer(tester, images: 3);

    expect(find.text(txt('draw')), findsWidgets);
    expect(find.text(txt('download')), findsWidgets);

    // Drawing opens the pens; the eraser only exists while drawing.
    expect(find.text(txt('erase')), findsNothing);
    await tester.tap(find.text(txt('draw')).first);
    await tester.pump();
    expect(find.text(txt('erase')), findsWidgets);

    await tester.tap(find.text(txt('draw')).first);
    await tester.pump();
    expect(find.text(txt('erase')), findsNothing);

    expect(tester.takeException(), isNull);
    // fluent_ui holds a short tap-feedback timer: let it fire so the test ends
    // without one pending.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a window brings its own frame, so the photo draws no close',
      (tester) async {
    await pumpViewer(tester);

    // Closing belongs to the window header; the body never offers a second way
    // out, and offers no delete where the caller does not delete.
    expect(find.text(txt('close')), findsNothing);
    expect(find.text(txt('delete')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete is offered only where the caller deletes',
      (tester) async {
    await pumpViewer(tester);
    expect(find.text(txt('delete')), findsNothing);

    await pumpViewer(
      tester,
      onPressDelete: (_) {},
    );
    expect(find.text(txt('delete')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a photo on its own is not a carousel', (tester) async {
    await pumpViewer(tester);

    // One photo has nowhere to page to, so it draws no counter and no arrows.
    expect(find.text('1/1'), findsNothing);
    expect(find.byIcon(WindowsIcons.chevron_right), findsNothing);
    expect(find.byIcon(FluentIcons.play_resume), findsNothing);
  });

  testWidgets('several photos page with the arrows, the keys and the count',
      (tester) async {
    await pumpViewer(tester, images: 3);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byIcon(WindowsIcons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(find.byIcon(WindowsIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);

    // The window takes focus as it opens, so the arrow keys work on their own.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('the pen and the file tools appear only where they can act',
      (tester) async {
    await pumpViewer(tester, withNames: false, withPen: false);

    // No names: nothing to download and nothing to delete by. No pen: nothing
    // to draw with.
    expect(find.text(txt('download')), findsNothing);
    expect(find.text(txt('delete')), findsNothing);
    expect(find.text(txt('draw')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
