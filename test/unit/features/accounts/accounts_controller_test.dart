@Tags(['serial'])
library;

import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/services/login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('profile lookup server errors do not create another profile', () async {
    final oldPb = login.pb;
    final oldToken = login.token;
    final oldErrorDialogShown = errorDialogShown;
    var profileCreates = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.queryParameters['filter']?.contains('account_id') ==
              true) {
        return http.Response(
          '{"code":500,"message":"temporary failure"}',
          500,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST') profileCreates++;
      return http.Response(
        '{"id":"user"}',
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    login.pb = PocketBase(
      'https://accounts.test',
      httpClientFactory: () => client,
    );
    login.token = '';
    errorDialogShown = true;
    try {
      await accounts.update(
        id: 'user',
        isAdmin: false,
        email: 'user@example.com',
        password: '',
        name: 'User',
        permissions: const [],
        operates: false,
      );

      expect(profileCreates, 0);
      expect(accounts.updating(), isEmpty);
    } finally {
      login.pb = oldPb;
      login.token = oldToken;
      errorDialogShown = oldErrorDialogShown;
      client.close();
    }
  });
}
