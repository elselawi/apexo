import 'package:apexo/services/backups.dart';
import 'package:apexo/services/login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed backup operations release all busy flags', () async {
    final oldPocketBase = login.pb;
    login.pb = null;
    try {
      await expectLater(backups.newBackup(), throwsA(anything));
      await expectLater(backups.delete('backup'), throwsA(anything));
      await expectLater(backups.downloadUri('backup'), throwsA(anything));
      await expectLater(backups.restore('backup'), throwsA(anything));
      expect(backups.creating(), isFalse);
      expect(backups.deleting(), isEmpty);
      expect(backups.downloading(), isEmpty);
      expect(backups.restoring(), isEmpty);
    } finally {
      login.pb = oldPocketBase;
    }
  });

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
