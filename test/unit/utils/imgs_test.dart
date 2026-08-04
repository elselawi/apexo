import 'dart:io';
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
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('createDirectory creates directory if not exists', () async {
      final newDir = '${testDir.path}/newdir';
      await createDirectory(newDir);
      expect(await Directory(newDir).exists(), true);
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
      expect(await file.exists(), true);
    });

    test('savePickedImage copies image correctly', () async {
      final srcName = path.join(testDir.path, 'test_src.jpg');
      final dstName = path.join(testDir.path, 'test_dst.jpg');
      final sourceImage = await getOrCreateFile(srcName);
      await sourceImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
      final result = await savePickedImage(sourceImage, dstName);
      expect(await result.exists(), true);
      expect(path.basename(result.path), path.basename(dstName));
      expect(await result.readAsBytes(), [0xFF, 0xD8, 0xFF, 0xE0]);
    });
  });

  group('Image name and URL classification', () {
    test('recognizes every supported image extension case-insensitively', () {
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
}
