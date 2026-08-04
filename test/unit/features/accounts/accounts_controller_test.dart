import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  group('Accounts Controller — observable defaults', () {
    test('accounts singleton exists', () {
      expect(accounts, isNotNull);
    });

    test('list is an ObservableState', () {
      expect(accounts.list, isNotNull);
      expect(accounts.list(), isEmpty);
    });

    test('loaded starts as false', () {
      expect(accounts.loaded(), false);
    });

    test('loading starts as false', () {
      expect(accounts.loading(), false);
    });

    test('creating starts as false', () {
      expect(accounts.creating(), false);
    });

    test('updating starts as empty map', () {
      expect(accounts.updating(), isEmpty);
    });

    test('deleting starts as empty map', () {
      expect(accounts.deleting(), isEmpty);
    });

    test('nameOrEmailFromID returns a string for any ID', () {
      final name = accounts.nameOrEmailFromID('nonexistent');
      expect(name, isNotNull);
    });

    test('operators is a list', () {
      final ops = accounts.operators;
      expect(ops, isNotNull);
    });

    test('name prefers profile name and falls back to email', () {
      final named = RecordModel.fromJson({
        'id': 'named',
        'name': 'Dr Name',
        'email': 'name@example.com',
      });
      final unnamed = RecordModel.fromJson({
        'id': 'unnamed',
        'name': '',
        'email': 'email@example.com',
      });

      expect(accounts.name(named), 'Dr Name');
      expect(accounts.name(unnamed), 'email@example.com');
    });

    test('operators includes only records with operate=1', () {
      final previous = accounts.list();
      try {
        accounts.list([
          RecordModel.fromJson({'id': 'operator', 'operate': 1}),
          RecordModel.fromJson({'id': 'non-operator', 'operate': 0}),
        ]);

        expect(accounts.operators.map((record) => record.id), ['operator']);
      } finally {
        accounts.list(previous);
      }
    });

    test('nameOrEmailFromID falls back to the first available account', () {
      final previous = accounts.list();
      try {
        accounts.list([
          RecordModel.fromJson({
            'id': 'admin',
            'type': 'admin',
            'name': 'Admin',
            'email': 'admin@example.com',
          }),
          RecordModel.fromJson({
            'id': 'user',
            'name': 'User',
            'email': 'user@example.com',
          }),
        ]);

        expect(accounts.nameOrEmailFromID('admin'), 'Admin');
        expect(accounts.nameOrEmailFromID('missing'), 'Admin');
      } finally {
        accounts.list(previous);
      }
    });

    test('reloadFromRemote exits cleanly without authenticated PocketBase',
        () async {
      final oldPb = login.pb;
      final oldToken = login.token;
      login.pb = null;
      login.token = '';
      await accounts.reloadFromRemote();

      expect(accounts.loading(), isFalse);
      expect(accounts.loaded(), isFalse);
      login.pb = oldPb;
      login.token = oldToken;
    });
  });
}
