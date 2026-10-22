import 'dart:async';
import 'dart:typed_data';

import 'package:apexo/shared/image_viewer/photo_viewer_window.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

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

/// The photo window: the wait for a photo happens inside it, and a failure is
/// reported there rather than in a dialog over the app.
void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    required Future<List<ImageProvider<Object>>> Function() load,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Pumped by hand: the window's waiting state is a spinner, and a spinner
    // never settles.
    await tester.pumpWidget(
      FluentApp(
        home: material.Directionality(
          textDirection: TextDirection.ltr,
          child: FluentTheme(
            data: FluentThemeData.light(),
            child: SizedBox(
              width: 760,
              height: 620,
              child: PhotoViewerWindow(
                rowId: 'photo-window-test',
                images: const ['xray.png'],
                load: load,
                onClosed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a photo loads inside its window', (tester) async {
    final loading = Completer<List<ImageProvider<Object>>>();
    await pumpViewer(tester, load: () => loading.future);

    // The window is up, showing what it is waiting for — the app behind it is
    // not covered by a dialog.
    expect(find.text(txt('gettingImages')), findsWidgets);
    expect(find.byType(ProgressRing), findsOneWidget);

    loading.complete([MemoryImage(_pixel)]);
    await tester.pumpAndSettle();

    expect(find.text(txt('gettingImages')), findsNothing);
    // The photo is up: its own toolbar (download, and delete where allowed) is drawn on it.
    expect(find.text(txt('download')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a photo that will not load says so, and can be tried again',
      (tester) async {
    var fail = true;
    await pumpViewer(
      tester,
      load: () async {
        if (fail) throw StateError('no such file');
        return [MemoryImage(_pixel)];
      },
    );
    await tester.pumpAndSettle();

    expect(find.text(txt('couldNotOpenImage')), findsWidgets);
    expect(find.text(txt('retry')), findsWidgets);

    fail = false;
    await tester.tap(find.text(txt('retry')).first);
    await tester.pumpAndSettle();

    expect(find.text(txt('couldNotOpenImage')), findsNothing);
    // The photo is up: its own toolbar (download, and delete where allowed) is drawn on it.
    expect(find.text(txt('download')), findsWidgets);

    // fluent_ui holds a short tap-feedback timer: let it fire so the test ends
    // without one pending.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
