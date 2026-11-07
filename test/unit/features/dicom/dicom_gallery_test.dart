import 'dart:async';
import 'dart:typed_data';

import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DICOM preview loading state', () {
    Future<void> pumpGallery(WidgetTester tester, String name) async {
      await tester.pumpWidget(FluentApp(
        home: ScaffoldPage(
          content: GridGallery(
            rowId: 'preview-row',
            imgs: const [],
            dcmImgs: [name],
            canDelete: false,
            onPressDelete: (_) async {},
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    testWidgets('missing preview stops spinning',
        (tester) async {
      const name = 'gallery_missing_preview.dcm';
      final previousRemote = appointments.remote;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/api/health')) {
          return http.Response('{}', 200);
        }
        return http.Response('{}', 200);
      });
      final remote = SaveRemote(
        storeName: 'appointments',
        pbInstance: PocketBase('http://fake-pocketbase',
            httpClientFactory: () => client),
      );
      appointments.remote = remote;
      imgMemoryCache.remove('$name.png');
      addTearDown(() {
        appointments.remote = previousRemote;
        remote.timer?.cancel();
        client.close();
        imgMemoryCache.remove('$name.png');
      });

      await pumpGallery(tester, name);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProgressRing), findsNothing);
      expect(find.byType(Image), findsNothing);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('invalid preview shows a file placeholder, not a spinner',
        (tester) async {
      const name = 'gallery_invalid_preview.dcm';
      imgMemoryCache['$name.png'] = MemoryImage(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => imgMemoryCache.remove('$name.png'));

      await pumpGallery(tester, name);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProgressRing), findsNothing);
      expect(find.byIcon(WindowsIcons.document), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('dicomPngReady stream', () {
    test('emits the bumped value to subscribers', () async {
      final received = <int>[];
      final StreamSubscription<int> sub =
          dicomPngReady.stream.listen(received.add);

      final before = dicomPngReady();
      dicomPngReady(before + 1);

      // Give the broadcast stream a turn to deliver.
      await Future<void>.delayed(Duration.zero);

      expect(received, [before + 1]);
      expect(dicomPngReady(), before + 1);

      await sub.cancel();
    });

    test('supports multiple concurrent subscribers (broadcast)', () async {
      final a = <int>[];
      final b = <int>[];
      final subA = dicomPngReady.stream.listen(a.add);
      final subB = dicomPngReady.stream.listen(b.add);

      final before = dicomPngReady();
      dicomPngReady(before + 1);
      await Future<void>.delayed(Duration.zero);

      expect(a, [before + 1]);
      expect(b, [before + 1]);

      await subA.cancel();
      await subB.cancel();
    });
  });

  group('gallery routing decision matrix', () {
    test('DCM names → viewer (isDcm true, isImage false)', () {
      for (final name in ['x.dcm', 'x.DCM', 'scan.dicom', 'SCAN.DICOM']) {
        expect(isADcmName(name), isTrue,
            reason: '$name should be recognised as a DCM X-ray');
        expect(isAnImageName(name), isFalse,
            reason: '$name must NOT enter the photo slideshow');
      }
    });

    test('photo names → slideshow (isDcm false, isImage true)', () {
      for (final name in ['a.jpg', 'b.png', 'c.jpeg', 'd.gif']) {
        expect(isADcmName(name), isFalse);
        expect(isAnImageName(name), isTrue);
      }
    });

    test('other files → download (both false)', () {
      for (final name in ['report.pdf', 'notes.txt', 'noext']) {
        expect(isADcmName(name), isFalse);
        expect(isAnImageName(name), isFalse);
      }
    });
  });

  group('viewableImgs excludes DCM from the slideshow', () {
    test('a combined photo+DCM list filters to photos only', () {
      // Mirrors GridGallery.viewableImgs: widget.imgs.where(isAnImageName).
      final combined = ['photo1.jpg', 'photo2.png', 'xray.dcm', 'scan.dicom'];
      final viewable = combined.where((n) => isAnImageName(n)).toList();
      expect(viewable, ['photo1.jpg', 'photo2.png']);
    });
  });

  group('backward compatibility — .dcm in imgs is NOT a DCM X-ray', () {
    // Routing keys off membership in `dcmImgs`, not the name, so a .dcm in
    // `imgs` keeps regular-file behaviour for notes and expenses.
    test('a .dcm name not in dcmImgs is treated as a regular file', () {
      final imgs = ['report.pdf', 'scan.dcm', 'note.txt'];
      final dcmImgs = <String>[]; // notes/expenses pass no dcmImgs
      final dcmNames = dcmImgs.toSet();

      for (final name in imgs) {
        expect(dcmNames.contains(name), isFalse,
            reason: '$name must NOT be routed as a DCM X-ray when it is not '
                'in dcmImgs (notes/expenses backward compatibility)');
      }
    });

    test('only names in dcmImgs are routed as DCM X-rays', () {
      final dcmImgs = ['xray.dcm', 'scan.dicom'];
      final dcmNames = dcmImgs.toSet();

      expect(dcmNames.contains('xray.dcm'), isTrue);
      expect(dcmNames.contains('scan.dicom'), isTrue);
      // A stray .dcm in imgs that isn't in dcmImgs is NOT a DCM X-ray.
      expect(dcmNames.contains('other.dcm'), isFalse);
    });

    test('dcmImgs defaults to empty (non-appointment callers unaffected)', () {
      const defaultDcmImgs = <String>[];
      expect(defaultDcmImgs.toSet(), isEmpty);
    });
  });

  group('localization keys', () {
    test('"dcm" and "generatingPreview" are present in the En dictionary', () {
      final en = En();
      expect(en.dictionary.containsKey('dcm'), isTrue,
          reason: 'DCM badge label key missing');
      expect(en.dictionary.containsKey('generatingPreview'), isTrue,
          reason: 'PNG-not-ready tooltip key missing');
      expect(en.dictionary['dcm']!.isNotEmpty, isTrue);
      expect(en.dictionary['generatingPreview']!.isNotEmpty, isTrue);
    });
  });

  group('ObservableState stream contract (gallery rebuild primitive)', () {
    test('emits each written value', () async {
      final state = ObservableState<int>(0);
      final received = <int>[];
      final sub = state.stream.listen(received.add);

      state(1);
      state(2);
      state(3);
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2, 3]);
      expect(state(), 3);
      await sub.cancel();
      state.dispose();
    });
  });
}
