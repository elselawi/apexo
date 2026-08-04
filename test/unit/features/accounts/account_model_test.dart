import 'package:apexo/features/accounts/open_account_panel.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('AccountModel.fromJson', () {
    test('parses admin account', () {
      final a = AccountModel.fromJson({
        'id': 'adm1',
        'email': 'admin@test.com',
        'password': 'secret',
        'name': 'Admin User',
        'permissions': [2, 2, 2, 2, 2, 2, 2, 2, 2],
        'operate': 1,
        'type': 'admin',
      });

      expect(a.id, 'adm1');
      expect(a.email, 'admin@test.com');
      expect(a.name, 'Admin User');
      expect(a.isAdmin, true);
      expect(a.operates, true);
    });

    test('parses regular user account', () {
      final a = AccountModel.fromJson({
        'id': 'usr1',
        'email': 'user@test.com',
        'name': 'Regular User',
        'operate': 0,
        'type': 'user',
      });

      expect(a.isAdmin, false);
      expect(a.operates, false);
      expect(a.name, 'Regular User');
    });

    test('determines isAdmin from type or isAdmin key', () {
      expect(AccountModel.fromJson({'id': 'a', 'type': 'admin'}).isAdmin, true);
      expect(
          AccountModel.fromJson({'id': 'b', 'type': 'user', 'isAdmin': true})
              .isAdmin,
          true);
    });

    test('malformed or missing permissions fall back to padded zeroes', () {
      final missing = AccountModel.fromJson({'id': 'missing'});
      final malformed = AccountModel.fromJson({
        'id': 'malformed',
        'permissions': 'not-json',
      });

      expect(missing.permissions, List<int>.filled(Perm.count, 0));
      expect(malformed.permissions, List<int>.filled(Perm.count, 0));
    });

    test('short permissions are padded and long permissions are preserved', () {
      final short = AccountModel.fromJson({
        'permissions': [2, 1],
      });
      final long = AccountModel.fromJson({
        'permissions': List<int>.filled(Perm.count + 2, 1),
      });

      expect(short.permissions, [2, 1, ...List<int>.filled(Perm.count - 2, 0)]);
      expect(long.permissions.length, Perm.count + 2);
    });

    test('null flags use false defaults and title falls back to email', () {
      final account = AccountModel.fromJson({
        'id': 'defaults',
        'email': 'fallback@example.com',
        'name': null,
        'type': 'user',
        'operate': 0,
      });

      expect(account.name, isEmpty);
      expect(account.title, 'fallback@example.com');
      expect(account.isAdmin, isFalse);
      expect(account.operates, isFalse);
    });

    test('determines operates from operate or operates key', () {
      expect(AccountModel.fromJson({'id': 'a', 'operate': 1}).operates, true);
      expect(
          AccountModel.fromJson({'id': 'b', 'operates': true}).operates, true);
    });

    test('title is name if set, otherwise email', () {
      final withName = AccountModel.fromJson(
          {'id': 'a', 'email': 'e@t.com', 'name': 'Name'});
      expect(withName.title, 'Name');

      final noName = AccountModel.fromJson({'id': 'b', 'email': 'e@t.com'});
      expect(noName.title, 'e@t.com');
    });
  });

  group('AccountModel.toJson', () {
    test('round-trip preserves core fields', () {
      final a = testAccount(
          id: 'rt1', email: 'test@t.com', name: 'Test', isAdmin: false);
      final json = a.toJson();
      expect(json['id'], 'rt1');
      expect(json['email'], 'test@t.com');
      expect(json['type'], 'user');
    });

    test('admin serializes with type admin', () {
      final a = testAccount(id: 'adm', isAdmin: true);
      expect(a.toJson()['type'], 'admin');
    });

    test('operate serialized as 1 or 0', () {
      expect(testAccount(id: 'op1', operates: true).toJson()['operate'], 1);
      expect(testAccount(id: 'op2', operates: false).toJson()['operate'], 0);
    });

    test('serialization includes all account fields and normalizes flags', () {
      final account = AccountModel.fromJson({
        'id': 'complete',
        'email': 'e@example.com',
        'password': 'pw',
        'name': 'Complete',
        'permissions': [2, 1],
        'operates': true,
        'isAdmin': true,
      });
      final json = account.toJson();

      expect(json, {
        'id': 'complete',
        'title': 'Complete',
        'email': 'e@example.com',
        'password': 'pw',
        'name': 'Complete',
        'permissions': [2, 1, ...List<int>.filled(Perm.count - 2, 0)],
        'operate': 1,
        'type': 'admin',
      });
    });
  });

  group('accountFromJson', () {
    test('returns AccountModel', () {
      final a = accountFromJson(
          {'id': 'afj1', 'email': 'e@t.com', 'name': 'Test', 'operate': 1});
      expect(a, isA<AccountModel>());
      expect(a.id, 'afj1');
    });
  });

  group('AccountModel.copy', () {
    test('copy returns a Model', () {
      final orig = testAccount(
          id: 'cpy1', email: 'orig@t.com', name: 'Original', isAdmin: true);
      final clone = orig.copy(false);
      expect(clone.id, 'cpy1');
      expect(clone.archived, isNull);
    });

    test('copy creates independent instance', () {
      final orig = testAccount(id: 'cpy2', name: 'Orig');
      final clone = orig.copy(false);
      clone.archived = true;
      expect(orig.archived, isNull);
      expect(clone.archived, true);
    });

    test('copy deep-copies permissions and preserves account fields', () {
      final original = testAccount(
        id: 'deep-copy',
        email: 'original@example.com',
        permissions: [2, 1, 0, 0, 0, 0, 0, 0, 0],
      );
      final clone = original.copy(false);
      clone.permissions[0] = 0;
      clone.name = 'Changed';

      expect(original.permissions[0], 2);
      expect(original.name, 'Test User');
      expect(clone.email, original.email);
      expect(clone.name, 'Changed');
    });
  });
}
