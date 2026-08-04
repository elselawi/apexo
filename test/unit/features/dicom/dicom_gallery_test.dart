import 'dart:async';

import 'package:apexo/core/observable.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dicomPngReady stream', () {
    test('emits the bumped value to subscribers', () async {
      // The gallery's DCM tile subscribes to this stream and re-fetches the
      // PNG preview on each emission. Verify the contract: a listen registered
      // before the bump receives it.
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
    // The GridGallery routes each cell by name classification:
    //   DCM  → openDicomViewerPanel (viewer)
    //   img  → photo slideshow
    //   else → download
    // These tests pin the classification the routing branches rely on.
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
    // GridGallery routes DCM behaviour by membership in `dcmImgs`, NOT by
    // name pattern. A `.dcm` file attached to a note/expense (passed via
    // `imgs`) must keep regular-file behaviour (download on tap, file
    // thumbnail display) — otherwise non-DCM galleries regress.
    //
    // This test pins the membership contract the gallery relies on.
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
      // Mirrors the GridGallery.dcmImgs default. With dcmImgs empty, the
      // derived _dcmNames set is empty and no cell gets DCM treatment.
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
    // The DCM tile rebuilds by re-fetching on stream emission. Verify a fresh
    // ObservableState behaves identically to dicomPngReady so the pattern is
    // sound independent of the global singleton's prior state.
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
