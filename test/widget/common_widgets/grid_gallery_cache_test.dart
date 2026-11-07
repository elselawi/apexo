@Tags(['serial'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/shared/image_viewer/photo_viewer_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/services/file_links.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pictures are resolved per tile, per open, so a reopened gallery must be
/// answered from memory rather than by another round trip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileLinkResolver? previousResolver;
  late int resolveCalls;
  late int httpRequests;

  setUp(() {
    previousResolver = fileLinkResolver;
    resolveCalls = 0;
    httpRequests = 0;
    imgMemoryCache.clear();
    fileLinkResolver = (rowId, name) async {
      resolveCalls++;
      return 'https://files.test/$rowId/$name';
    };
  });

  tearDown(() {
    WindowsManager.closeAll();
    fileLinkResolver = previousResolver;
    imgMemoryCache.clear();
  });

  /// Lets the tiles' real file work finish: a widget test's own clock does not
  /// advance it.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget gallery({
    required String rowId,
    List<String> imgs = const [],
    List<String> dcmImgs = const [],
    double? size,
  }) =>
      FluentApp(
        home: ScaffoldPage(
          content: GridGallery(
            rowId: rowId,
            imgs: imgs,
            dcmImgs: dcmImgs,
            canDelete: false,
            size: size,
            onPressDelete: (_) async {},
          ),
        ),
      );

  Future<void> withMockedHttp(Future<void> Function() body) {
    final client = MockClient((request) async {
      httpRequests++;
      return http.Response.bytes(const [0xFF, 0xD8, 0xFF, 0xE0], 200);
    });
    return http.runWithClient(body, () => client);
  }

  testWidgets('deleting finishes owner progress after the gallery closes',
      (tester) async {
    final deleting = Completer<void>();
    final progress = <bool>[];
    imgMemoryCache['pending-delete.png'] = MemoryImage(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM1kAAAAASUVORK5CYII='));
    await tester.pumpWidget(FluentApp(
      home: ScaffoldPage(
        content: GridGallery(
          rowId: 'delete-row',
          imgs: const ['pending-delete.png'],
          size: 43,
          canDelete: true,
          onProgress: progress.add,
          onPressDelete: (_) => deleting.future,
        ),
      ),
    ));
    await settle(tester);
    await tester.tap(find.byType(Image).first);
    await tester.pump();
    final viewer = WindowsManager.open().single.window.body as PhotoViewerWindow;
    viewer.onDelete!(0);
    expect(progress, [true]);

    await tester.pumpWidget(const SizedBox.shrink());
    deleting.complete();
    await tester.pump();

    expect(progress, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the large preview is not fetched again when reopened',
      (tester) async {
    await withMockedHttp(() async {
      const photo = 'reopen_preview_ab12cd.jpg';

      // The 640px preview the big tile shows, already on the disk.
      await tester.runAsync(() async {
        final preview = await getOrCreateFile('reopen_preview_ab12cd.thumb640.jpg');
        await preview.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);
      });

      // No `size`: the gallery draws its first picture bigger, from a preview.
      await tester.pumpWidget(gallery(rowId: 'reopen-row', imgs: const [photo]));
      await settle(tester);
      expect(resolveCalls, 0, reason: 'the preview is on disk');
      expect(httpRequests, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);

      // The preview is gone from disk, so only the memory cache can answer now.
      await tester.runAsync(() async {
        final preview = await getOrCreateFile('reopen_preview_ab12cd.thumb640.jpg');
        await preview.delete();
      });

      await tester.pumpWidget(gallery(rowId: 'reopen-row', imgs: const [photo]));
      await settle(tester);
      expect(resolveCalls, 0,
          reason: 'a reopened gallery must not look the picture up again');
      expect(httpRequests, 0,
          reason: 'a reopened gallery must not download the picture again');
    });
  });

  testWidgets('tiles are not looked up again when reopened', (tester) async {
    await withMockedHttp(() async {
      const photo = 'reopen_tile_cd34ef.jpg';
      const xray = 'dcm_reopen_ef56gh.dcm';
      await tester.runAsync(() async {
        final thumb = await getOrCreateFile('reopen_tile_cd34ef.thumb.jpg');
        await thumb.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);
        final dcmThumb =
            await getOrCreateFile('dcm_reopen_ef56gh.dcm.thumb.png');
        await dcmThumb.writeAsBytes(const [0x89, 0x50, 0x4E, 0x47]);
      });

      Widget tileGrid() => gallery(
            rowId: 'tile-row',
            imgs: const [photo],
            dcmImgs: const [xray],
            // The size a visit card's gallery uses: a grid of thumbs.
            size: 43,
          );

      await tester.pumpWidget(tileGrid());
      await settle(tester);
      expect(resolveCalls, 0, reason: 'both thumbs are on disk');

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.runAsync(() async {
        await (await getOrCreateFile('reopen_tile_cd34ef.thumb.jpg')).delete();
        await (await getOrCreateFile('dcm_reopen_ef56gh.dcm.thumb.png'))
            .delete();
      });

      await tester.pumpWidget(tileGrid());
      await settle(tester);
      expect(resolveCalls, 0, reason: 'the cache answered both tiles');
      expect(httpRequests, 0);
    });
  });
}
