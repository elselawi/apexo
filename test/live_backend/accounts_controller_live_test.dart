@Tags(['live_backend', 'serial'])
library;

import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import '../secret.dart';

/// Runs against a real PocketBase using the credentials in `test/secret.dart`,
/// so it stays out of unit runs (`flutter test --tags live_backend`).
void main() {
  group('Accounts controller — PocketBase integration', () {
    setUpAll(() async {
      if (login.pb == null || login.pb!.authStore.isValid == false) {
        login.pb = PocketBase(testPBServer);
        await login.pb!
            .collection('_superusers')
            .authWithPassword(testPBEmail, testPBPassword);
        login.token = login.pb!.authStore.token;
      }
    });

    test('reloadFromRemote fetches profile records and settles loading',
        () async {
      await accounts.reloadFromRemote();

      expect(accounts.loaded(), isTrue);
      expect(accounts.loading(), isFalse);
      expect(accounts.list(), isNotEmpty);
    });

    test('loaded records have a stable display name fallback', () {
      final account = accounts.list().first;
      final displayName = accounts.name(account);

      expect(displayName, isNotEmpty);
      expect(accounts.nameOrEmailFromID(account.id), displayName);
    });

    test('operators contain only records with operate=1', () {
      expect(
        accounts.operators
            .every((record) => record.getIntValue('operate') == 1),
        isTrue,
      );
    });
  });
}
