import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart' show FileImage, NetworkImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory testDir;
  late String testImagePath;

  group('Image File Operations', () {
    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('apexo-imgs-');
      testImagePath = path.join(testDir.path, 'test.jpg');
      await testDir.create(recursive: true);
      // Create a test image file
      final File testImage = await getOrCreateFile(testImagePath);
      await testImage
          .writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // Basic JPEG header
    });

    tearDown(() async {
      if (testDir.existsSync()) {
        await testDir.delete(recursive: true);
      }
    });

    test('createDirectory creates directory if not exists', () async {
      final newDir = '${testDir.path}/newdir';
      await createDirectory(newDir);
      expect(Directory(newDir).existsSync(), true);
    });

    test('checkIfFileExists returns correct existence status', () async {
      await getOrCreateFile(testImagePath);
      expect(await checkIfFileExists(testImagePath), true);
      expect(await checkIfFileExists('nonexistent.jpg'), false);
    });

    test('getOrCreateFile returns valid file', () async {
      final file =
          await getOrCreateFile(path.join(testDir.path, 'newfile.txt'));
      expect(file, isA<File>());
      await file.writeAsString("Test content");
      expect(file.existsSync(), true);
    });

    test('savePickedImage copies image correctly', () async {
      final srcName = path.join(testDir.path, 'test_src.jpg');
      final dstName = path.join(testDir.path, 'test_dst.jpg');
      final sourceImage = await getOrCreateFile(srcName);
      await sourceImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
      final result = await savePickedImage(sourceImage, dstName);
      expect(result.existsSync(), true);
      expect(path.basename(result.path), path.basename(dstName));
      expect(await result.readAsBytes(), [0xFF, 0xD8, 0xFF, 0xE0]);
    });
  });

  group('Image name and URL classification', () {    test('recognizes every supported image extension case-insensitively', () {
      for (final extension in [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
        'svg',
        'tiff',
        'tif',
        'ico',
        'heic',
        'heif',
        'avif',
        'jfif',
      ]) {
        expect(isAnImageName('photo.$extension'), isTrue);
        expect(isAnImageName('photo.${extension.toUpperCase()}'), isTrue);
      }
      expect(isAnImageName('photo.dcm'), isFalse);
      expect(isAnImageName('photo'), isFalse);
    });

    test('recognizes DICOM extensions case-insensitively', () {
      expect(isADcmName('scan.dcm'), isTrue);
      expect(isADcmName('scan.DICOM'), isTrue);
      expect(isADcmName('scan.png'), isFalse);
    });

    test('recognizes only HTTP and HTTPS URLs', () {
      expect(isUrl('https://example.com/image.png'), isTrue);
      expect(isUrl('http://example.com/image.png'), isTrue);
      expect(isUrl('ftp://example.com/image.png'), isFalse);
      expect(isUrl('blob:image'), isFalse);
    });

    test('strips generated hash suffixes from display names', () {
      expect(displayNameForFile('invoice_abcdef.pdf'), 'invoice.pdf');
      expect(displayNameForFile('invoice_abcdef_123456.pdf'), 'invoice.pdf');
      expect(displayNameForFile('https://host/path/photo_abcdef.jpg'),
          'photo.jpg');
      expect(displayNameForFile('plain.pdf'), 'plain.pdf');
    });
  });

  group('Image caching', () {
    late int resolveCalls;
    Future<String?> countedResolve(String rowId, String name) async {
      resolveCalls++;
      return 'https://files.test/$name';
    }

    Future<void> clearFixtures() async {
      for (final name in [
        'cached_photo_ab12cd.jpg',
        'preview_photo_cd34ef.jpg',
        'original_photo_ef56gh.jpg',
        'dcm_ab12cd34.dcm.png',
        'local_original_ij78kl.png',
        'local_preview_mn90op.png',
      ]) {
        for (final fileName in [
          name,
          '${path.withoutExtension(name)}.thumb${path.extension(name)}',
          '${path.withoutExtension(name)}.thumb640${path.extension(name)}',
        ]) {
          final file = await getOrCreateFile(fileName);
          if (file.existsSync()) await file.delete();
        }
      }
      imgMemoryCache.clear();
    }

    setUp(() async {
      resolveCalls = 0;
      await clearFixtures();
    });
    tearDown(clearFixtures);

    test('the generated avatar keeps its root URL and is cached', () async {
      const url = 'https://person.alisaleem.workers.dev/';
      final first = await getImage('avatar-row', url, true, countedResolve);
      final second = await getImage('avatar-row', url, true, countedResolve);

      expect(first, isA<NetworkImage>());
      expect((first! as NetworkImage).url, '$url?no-cache=avatar-row');
      expect(second, same(first));
      expect(resolveCalls, 0);
    });

    test('a picture already on disk is resolved once, then cached', () async {
      const name = 'cached_photo_ab12cd.jpg';
      final thumb = await getOrCreateFile('cached_photo_ab12cd.thumb.jpg');
      await thumb.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);

      final first = await getImage('row-1', name, true, countedResolve);
      expect(first, isNotNull);
      expect(resolveCalls, 0, reason: 'the thumb is on disk: nothing to ask');

      // The file leaves the disk; the cache is what answers now.
      await thumb.delete();
      final second = await getImage('row-1', name, true, countedResolve);
      expect(identical(first, second), isTrue,
          reason: 'the same picture is the same provider');
      expect(resolveCalls, 0, reason: 'the memory cache answered');
    });

    test('a large preview is kept apart from the thumb', () async {
      const name = 'preview_photo_cd34ef.jpg';
      final thumb = await getOrCreateFile('preview_photo_cd34ef.thumb.jpg');
      await thumb.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);
      final preview =
          await getOrCreateFile('preview_photo_cd34ef.thumb640.jpg');
      await preview.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE1]);

      final small = await getImage('row-2', name, true, countedResolve);
      final large =
          await getImage('row-2', name, true, countedResolve, kPreviewSize);
      expect(resolveCalls, 0, reason: 'both pictures are on disk');
      expect(small, isA<FileImage>());
      expect(large, isA<FileImage>());
      expect(path.basename((small! as FileImage).file.path),
          'preview_photo_cd34ef.thumb.jpg');
      expect(path.basename((large! as FileImage).file.path),
          'preview_photo_cd34ef.thumb640.jpg',
          reason: 'the preview is its own file, not the grid thumb');

      await preview.delete();
      final again =
          await getImage('row-2', name, true, countedResolve, kPreviewSize);
      expect(identical(large, again), isTrue,
          reason: 'the preview was cached on its own entry');
      expect(resolveCalls, 0);
    });

    test('the original is cached too, apart from any thumb', () async {
      const name = 'original_photo_ef56gh.jpg';
      final original = await getOrCreateFile('original_photo_ef56gh.jpg');
      await original.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);

      final full = await getImage('row-3', name, false, countedResolve);
      expect(full, isNotNull);
      expect(resolveCalls, 0, reason: 'the original is on disk');

      await original.delete();
      final again = await getImage('row-3', name, false, countedResolve);
      expect(identical(full, again), isTrue,
          reason: 'a viewer reopened must not read the file again');
      expect(resolveCalls, 0);
    });

    test('an X-ray asks for its PNG preview, never the raw .dcm', () async {
      const name = 'dcm_ab12cd34.dcm';
      final thumb = await getOrCreateFile('dcm_ab12cd34.dcm.thumb.png');
      await thumb.writeAsBytes(const [0x89, 0x50, 0x4E, 0x47]);

      final image =
          await getImage('row-4', name, true, countedResolve);
      expect(image, isNotNull);
      expect(resolveCalls, 0, reason: 'the preview thumb is on disk');
      expect(imgMemoryCache.containsKey('dcm_ab12cd34.dcm.png'), isTrue,
          reason: 'the entry is named after the PNG the tile shows');
    });

    test('a thumb is drawn from the local original, not fetched', () async {
      const name = 'local_original_ij78kl.png';
      final original = await getOrCreateFile('local_original_ij78kl.png');
      await original.writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=='));

      final image = await getImage('row-5', name, true, countedResolve);
      expect(image, isNotNull,
          reason: 'the picture itself is here: it can be shown');
      expect(resolveCalls, 0,
          reason: 'a picture on the disk is not asked for again');
      expect(await checkIfFileExists('local_original_ij78kl.thumb.png'), isTrue,
          reason: 'the thumb is drawn beside it, so the next open is free');
    });

    test('a large preview is drawn from the local original too', () async {
      const name = 'local_preview_mn90op.png';
      final original = await getOrCreateFile('local_preview_mn90op.png');
      await original.writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=='));

      final image =
          await getImage('row-6', name, true, countedResolve, kPreviewSize);
      expect(image, isNotNull);
      expect(resolveCalls, 0);
      expect(await checkIfFileExists('local_preview_mn90op.thumb640.png'), isTrue,
          reason: 'the preview is drawn from the picture, at its own size');
    });
  });
}
