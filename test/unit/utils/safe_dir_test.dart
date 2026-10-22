@Tags(['serial'])
library;

import 'package:apexo/utils/safe_dir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('baseDir', () {
    test('equals "apexo-files"', () {
      expect(baseDir, 'apexo-files');
    });
  });

  group('appFilesDir', () {
    test('returns a non-empty path string', () async {
      final dir = await appFilesDir();
      expect(dir, isNotEmpty);
    });

    test('path ends with baseDir', () async {
      final dir = await appFilesDir();
      expect(dir.endsWith(baseDir), true);
    });

    test('returns consistent path across multiple calls', () async {
      final dir1 = await appFilesDir();
      final dir2 = await appFilesDir();
      expect(dir1, dir2);
    });

    test('path contains baseDir', () async {
      final dir = await appFilesDir();
      expect(dir.contains(baseDir), true,
          reason: 'Expected path to contain "$baseDir", got: $dir');
    });

    test('uses platform path joining when documents directory is available',
        () async {
      final dir = await appFilesDir();
      expect(path.basename(dir), baseDir);
      expect(path.normalize(dir), dir);
    });
  });

  group('filesDir', () {
    test('returns a non-empty path string', () async {
      final dir = await filesDir();
      expect(dir, isNotEmpty);
    });

    test('returns consistent path across multiple calls', () async {
      final dir1 = await filesDir();
      final dir2 = await filesDir();
      expect(dir1, dir2);
    });

    test('a test process keeps its files in a directory of its own', () async {
      // Hive locks the files it opens, and the test runner runs several test
      // files at once: two processes sharing one directory would fail to open
      // the same box.
      expect(isTestEnvironment, isTrue);
      final dir = await filesDir();
      expect(path.isAbsolute(dir), isTrue);
      expect(dir, contains('apexo-test-'));
      expect(dir, isNot(contains(baseDir)),
          reason: 'a test must not touch the files of the real app');
    });
  });
}
