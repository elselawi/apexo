import 'package:apexo/services/backups.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('_Backups — observable defaults', () {
    test('singleton exists', () {
      expect(backups, isNotNull);
    });

    test('list defaults to empty', () {
      expect(backups.list(), isEmpty);
    });

    test('loaded defaults to false', () {
      expect(backups.loaded(), false);
    });

    test('loading defaults to false', () {
      expect(backups.loading(), false);
    });

    test('creating defaults to false', () {
      expect(backups.creating(), false);
    });

    test('uploading defaults to false', () {
      expect(backups.uploading(), false);
    });

    test('downloading defaults to empty map', () {
      expect(backups.downloading(), isEmpty);
    });

    test('deleting defaults to empty map', () {
      expect(backups.deleting(), isEmpty);
    });

    test('restoring defaults to empty map', () {
      expect(backups.restoring(), isEmpty);
    });
  });
}
