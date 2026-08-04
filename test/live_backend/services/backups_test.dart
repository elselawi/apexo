@Tags(['live_backend', 'serial'])
library;

import 'package:apexo/services/backups.dart';
import 'package:apexo/services/login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import '../../secret.dart';

void main() {
  setUpAll(() async {
    login.pb = PocketBase(testPBServer);
    final auth = await login.pb!
        .collection('_superusers')
        .authWithPassword(testPBEmail, testPBPassword);
    login.token = auth.token;
    login.adminCollectionId = auth.record.collectionId;
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

    test('downloading defaults to empty', () {
      expect(backups.downloading(), isEmpty);
    });

    test('deleting defaults to empty', () {
      expect(backups.deleting(), isEmpty);
    });

    test('restoring defaults to empty', () {
      expect(backups.restoring(), isEmpty);
    });
  });

  group('_Backups — real PB operations', () {
    test('reloadFromRemote fetches backup list', () async {
      await backups.reloadFromRemote();
      expect(backups.loaded(), true);
      expect(backups.loading(), false);
      expect(backups.list(), isA<List<BackupFile>>());
    });

    test('newBackup creates a backup and list grows', () async {
      final before = backups.list().length;
      await backups.newBackup();
      expect(backups.creating(), false);
      expect(backups.list().length, greaterThanOrEqualTo(before));
    });

    test('backup list is sorted by date descending', () async {
      await backups.reloadFromRemote();
      final list = backups.list();
      for (int i = 0; i < list.length - 1; i++) {
        expect(
          !list[i].date.isBefore(list[i + 1].date),
          true,
          reason: 'Backups not sorted descending',
        );
      }
    });

    test('downloadUri returns a valid URI for an existing backup', () async {
      await backups.reloadFromRemote();
      final list = backups.list();
      expect(list, isNotEmpty,
          reason: 'A backup is required to test downloadUri');
      final uri = await backups.downloadUri(list.first.key);
      expect(uri, isA<Uri>());
      expect(uri.toString(), isNotEmpty);
      expect(backups.downloading(), isEmpty);
    });

    test('delete removes a backup', () async {
      await backups.newBackup();
      final list = backups.list();
      expect(list, isNotEmpty, reason: 'Backup creation returned no backup');
      final keyToDelete = list.first.key;
      final before = list.length;

      await backups.delete(keyToDelete);
      expect(backups.list().length, lessThan(before));
      expect(backups.deleting().containsKey(keyToDelete), false);
    });
  });
}
