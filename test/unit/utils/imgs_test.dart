import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:path/path.dart' as path;

void main() {
  group('Image File Operations', () {
    final testDir = Directory('test_dir');
    const testImagePath = 'test.jpg';

    setUp(() async {
      await testDir.create(recursive: true);
      // Create a test image file
      final File testImage = await getOrCreateFile(testImagePath);
      await testImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // Basic JPEG header
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
      final file = await getOrCreateFile('newfile.txt');
      expect(file, isA<File>());
      await file.writeAsString("Test content");
      expect(await file.exists(), true);
    });

    test('savePickedImage copies image correctly', () async {
      final sourceImage = File(testImagePath);
      final result = await savePickedImage(sourceImage, 'copied.jpg');
      expect(await result.exists(), true);
      expect(path.basename(result.path), 'copied.jpg');
    });
  });

  group('Network Image Operations', () {
    test('getImageExtensionFromURL returns correct extension', () async {
      final jpgExtension = await getImageExtensionFromURL('https://cdn.culture.ru/c/710339.jpg');
      expect(jpgExtension, '.jpg');

      final pngExtension = await getImageExtensionFromURL('https://apexo.app/assets/images/logo.png');
      expect(pngExtension, '.png');
    });

    test('saveImageFromUrl downloads and saves image', () async {
      const imageUrl = 'https://picsum.photos/200/300';
      final savedImage = await saveImageFromUrl(imageUrl, 'test_download.jpg');
      expect(await savedImage.exists(), true);
      expect(await savedImage.length(), greaterThan(0));
    });
  });
}
