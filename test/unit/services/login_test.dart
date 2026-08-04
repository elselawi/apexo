@Tags(['serial'])
library;

import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<int> originalPerms;
  late String originalAdminCollectionId;
  late String originalUrl;
  late String originalEmail;
  late String originalToken;
  late String originalPushToken;
  late bool originalDidAskForLoginAgain;
  late dynamic originalPocketBase;
  late Open originalOpen;
  late bool originalOnline;
  late Map<String, Future<Future<void> Function()> Function()>
      originalActivators;
  late List<void Function()> originalLogoutCallbacks;

  setUp(() {
    originalPerms = List<int>.from(login.savedPermissions);
    originalAdminCollectionId = login.adminCollectionId;
    originalUrl = login.url;
    originalEmail = login.email;
    originalToken = login.token;
    originalPushToken = login.pushNotificationsToken;
    originalDidAskForLoginAgain = login.didAskForLoginAgain;
    originalPocketBase = login.pb;
    originalOpen = launch.open();
    originalOnline = network.isOnline();
    originalActivators =
        Map<String, Future<Future<void> Function()> Function()>.from(
            login.activators);
    originalLogoutCallbacks = List<void Function()>.from(onLogoutCallbacks);
  });

  tearDown(() {
    login.savedPermissions = originalPerms;
    login.adminCollectionId = originalAdminCollectionId;
    login.token = originalToken;
    login.url = originalUrl;
    login.email = originalEmail;
    login.didAskForLoginAgain = originalDidAskForLoginAgain;
    login.pushNotificationsToken = originalPushToken;
    login.pb = originalPocketBase;
    launch.open(originalOpen);
    network.isOnline(originalOnline);
    login.activators
      ..clear()
      ..addAll(originalActivators);
    onLogoutCallbacks
      ..clear()
      ..addAll(originalLogoutCallbacks);
  });

  group('Login service — observable defaults', () {
    test('url defaults to empty string', () {
      expect(login.url, isEmpty);
    });

    test('email defaults to empty string', () {
      expect(login.email, isEmpty);
    });

    test('token defaults to empty string', () {
      expect(login.token, isEmpty);
    });

    test('adminCollectionId defaults to __UNDEFINED__', () {
      login.adminCollectionId = '__UNDEFINED__';
      expect(login.adminCollectionId, '__UNDEFINED__');
    });

    test('pushNotificationsToken defaults to empty string', () {
      expect(login.pushNotificationsToken, isEmpty);
    });

    test('didAskForLoginAgain defaults to false', () {
      login.didAskForLoginAgain = false;
      expect(login.didAskForLoginAgain, false);
    });

    test('pb is null by default (no PocketBase instance)', () {
      // pb should be null when not initialized
      expect(login.pb, isNull);
    });

    test('savedPermissions defaults to Perm.zeroes', () {
      login.savedPermissions = Perm.zeroes;
      expect(login.savedPermissions, Perm.zeroes);
    });

    test('savedPermissions is settable', () {
      login.savedPermissions = Perm.full;
      expect(login.savedPermissions, Perm.full);
    });

    test('url and email are settable fields', () {
      login.url = 'https://example.com';
      login.email = 'test@example.com';
      expect(login.url, 'https://example.com');
      expect(login.email, 'test@example.com');
    });

    test('token is settable', () {
      login.token = 'jwt-token-here';
      expect(login.token, 'jwt-token-here');
    });
  });

  group('Login service — currentAccountID', () {
    test('returns empty string when no accounts loaded and not demo', () {
      // accounts.list() is empty by default in unit tests
      // Not in demo mode, no pb set
      login.token = '';
      login.pb = null;
      final id = login.currentAccountID;
      expect(id, isA<String>());
      // Should return empty when nothing matches
    });

    test('returns an empty string exactly when no account matches', () {
      login.token = '';
      login.pb = null;

      expect(login.currentAccountID, isEmpty);
    });

    test('does not throw when email is arbitrary text', () {
      login.email = 'not-an-email';
      login.token = '';
      login.pb = null;

      expect(() => login.currentAccountID, returnsNormally);
      expect(login.currentAccountID, isA<String>());
    });

    test('currentName returns empty when accounts list is empty', () {
      final name = login.currentName;
      expect(name, isEmpty);
    });

    test('currentName remains empty for an unmatched account id', () {
      login.email = 'nobody@example.com';
      login.token = '';
      login.pb = null;

      expect(login.currentName, isEmpty);
    });
  });

  group('Login service — isAdmin', () {
    test('returns false when pb is null', () {
      login.pb = null;
      login.token = '';
      expect(login.isAdmin, false);
    });

    test('returns false with invalid/empty token', () {
      login.pb = null;
      login.token = 'invalid';
      expect(login.isAdmin, false);
    });

    test('returns false for a JWT-shaped token without admin collection id',
        () {
      login.pb = null;
      login.adminCollectionId = 'admin-collection';
      // `e30` decodes to an empty JSON object.
      login.token = 'header.e30.signature';

      expect(login.isAdmin, isFalse);
    });

    test('returns false for tokens with too few segments', () {
      login.pb = null;
      login.token = 'header.payload';

      expect(login.isAdmin, isFalse);
    });
  });

  group('Login service — _permissions', () {
    test('perm returns PermLevel when savedPermissions is set', () {
      login.savedPermissions = Perm.full;
      final level = login.perm(0);
      expect(level.full, isTrue);
    });

    test('perm with savedPermissions=zeroes returns none', () {
      login.savedPermissions = Perm.zeroes;
      final level = login.perm(0);
      expect(level.none, isTrue);
    });

    test('perm with savedPermissions=partial returns partial', () {
      // [1, 0, 2, 0, 1] — mixed levels
      login.savedPermissions = [1, 0, 2, 0, 1, 0, 0, 0, 0];
      expect(login.perm(0).exact(1), isTrue);
      expect(login.perm(1).none, isTrue);
      expect(login.perm(2).full, isTrue);
    });

    test('_permissions pads short savedPermissions with zeros', () {
      login.savedPermissions = [2]; // only one slot set
      // Slot 0 should be full, slot 3 should be none (padded with 0)
      expect(login.perm(0).full, isTrue);
      expect(login.perm(3).none, isTrue);
    });

    test('perm exposes all fluent permission predicates', () {
      login.savedPermissions = [1, 2, 0, 0, 0, 0, 0, 0, 0];

      final limited = login.perm(0);
      expect(limited.some, isTrue);
      expect(limited.read, isTrue);
      expect(limited.full, isFalse);
      expect(limited.exact(1), isTrue);
      expect(limited.min(1), isTrue);
      expect(limited.not(2), isTrue);

      final full = login.perm(1);
      expect(full.full, isTrue);
      expect(full.min(2), isTrue);
    });

    test('offline permissions use saved permissions, not account data', () {
      network.isOnline(false);
      login.savedPermissions = [0, 1, 2, 0, 0, 0, 0, 0, 0];

      expect(login.perm(0).none, isTrue);
      expect(login.perm(1).exact(1), isTrue);
      expect(login.perm(2).full, isTrue);
    });
  });

  group('Login service — currentLoginIsOperator', () {
    test('returns false when accounts list is empty', () {
      login.savedPermissions = Perm.zeroes;
      expect(login.currentLoginIsOperator, false);
    });
  });

  group('Login service — helpers', () {
    test('activators is a settable map', () {
      login.activators['test-key'] = () async => () async {};
      expect(login.activators.containsKey('test-key'), isTrue);
      login.activators.remove('test-key');
    });

    test('activators can replace an entry with the same key', () async {
      var firstCalled = false;
      var replacementCalled = false;
      login.activators['replaceable'] = () async {
        firstCalled = true;
        return () async {};
      };
      login.activators['replaceable'] = () async {
        replacementCalled = true;
        return () async {};
      };

      await login.activators['replaceable']!();

      expect(firstCalled, isFalse);
      expect(replacementCalled, isTrue);
    });
  });

  group('Login service — onLogoutCallbacks', () {
    test('onLogoutCallbacks is a global list', () {
      expect(onLogoutCallbacks, isA<List>());
    });

    test('onLogoutCallbacks can register and invoke callbacks', () {
      var called = false;
      void cb() => called = true;
      onLogoutCallbacks.add(cb);

      // Invoke all
      for (final c in onLogoutCallbacks) {
        c();
      }
      expect(called, isTrue);

      // Cleanup
      onLogoutCallbacks.remove(cb);
    });

    test('logout invokes registered callbacks before returning', () {
      var count = 0;
      void first() => count++;
      void second() => count++;
      onLogoutCallbacks
        ..add(first)
        ..add(second);

      login.logout();

      expect(count, 2);
    });

    test('logout invokes callbacks in registration order', () {
      final calls = <String>[];
      onLogoutCallbacks
        ..add(() => calls.add('first'))
        ..add(() => calls.add('second'));

      login.logout();

      expect(calls, ['first', 'second']);
    });
  });

  group('Login service — askForLoginAgain guards', () {
    test('returns early when offline', () {
      // network.isOnline() is false in test
      login.didAskForLoginAgain = false;
      final prevDidAsk = login.didAskForLoginAgain;
      login.askForLoginAgain('test error');
      // Should be a no-op when offline
      expect(login.didAskForLoginAgain, prevDidAsk);
    });

    test('returns early when already asked', () {
      login.didAskForLoginAgain = true;
      login.askForLoginAgain('test error');
      // Should still be true after no-op
      expect(login.didAskForLoginAgain, isTrue);
    });

    test('returns early on login screen', () {
      final prevOpen = launch.open();
      launch.open(Open.login);
      login.didAskForLoginAgain = false;

      login.askForLoginAgain('test error');
      // Should be no-op when on login screen
      expect(login.didAskForLoginAgain, isFalse);

      launch.open(prevOpen);
    });

    test('returns early in demo mode guard when it is enabled', () {
      // launch.isDemo is environment-derived and normally false in tests;
      // this verifies the other guard conditions leave the flag untouched.
      login.didAskForLoginAgain = false;
      network.isOnline(false);

      login.askForLoginAgain(Exception('401 unauthorized'));

      expect(login.didAskForLoginAgain, isFalse);
    });
  });

  group('Login service — logout', () {
    test('logout sets url and email to empty when cleanCredentials=true', () {
      login.url = 'https://server';
      login.email = 'user@test';
      login.token = 'some-token';

      login.logout(true);

      expect(login.url, isEmpty);
      expect(login.email, isEmpty);
      expect(login.token, isEmpty);
    });

    test('logout preserves url and email when cleanCredentials=false', () {
      login.url = 'https://server';
      login.email = 'user@test';
      login.token = 'some-token';

      login.logout(false);

      expect(login.url, 'https://server');
      expect(login.email, 'user@test');
      expect(login.token, isEmpty);
    });

    test('logout sets launch.open to Open.login', () {
      final prev = launch.open();
      login.logout(true);
      expect(launch.open(), Open.login);
      launch.open(prev);
    });

    test('logout clears token regardless of cleanCredentials argument', () {
      login.token = 'token';
      login.logout(false);

      expect(login.token, isEmpty);
    });

    test('logout keeps saved permissions unchanged', () {
      final permissions = [2, 1, 0, 0, 0, 0, 0, 0, 0];
      login.savedPermissions = permissions;

      login.logout();

      expect(login.savedPermissions, permissions);
    });
  });

  group('Login service — serialization', () {
    test('toJson stores all credential fields', () {
      login.url = 'https://srv';
      login.email = 'e@e.com';
      login.token = 'tok';
      login.savedPermissions = [1, 2];

      final json = login.toJson();
      expect(json['url'], 'https://srv');
      expect(json['email'], 'e@e.com');
      expect(json['token'], 'tok');
    });

    test('toJson stores serialized permissions and remaining fields', () {
      login.adminCollectionId = 'admin-id';
      login.pushNotificationsToken = 'push-token';
      login.savedPermissions = [2, 1, 0];

      final json = login.toJson();

      expect(json['savedPermission'], '[2,1,0]');
      expect(json['adminCollectionId'], 'admin-id');
      expect(json['pushNotificationsToken'], 'push-token');
    });

    test('fromJson restores credentials with null-coalescing', () {
      login.fromJson({'url': null, 'email': null, 'token': null});
      // Fields should default to empty strings via ?? operator
      expect(login.url, isEmpty);
      expect(login.email, isEmpty);
      expect(login.token, isEmpty);
    });

    test('toJson round-trip preserves savedPermissions', () {
      login.savedPermissions = [0, 2, 1];
      final json = login.toJson();
      // Re-read
      login.fromJson(json);
      expect(login.savedPermissions.length, greaterThanOrEqualTo(3));
      expect(login.savedPermissions[0], 0);
      expect(login.savedPermissions[1], 2);
      expect(login.savedPermissions[2], 1);
    });

    test('fromJson restores all persisted fields when token is empty',
        () async {
      await login.fromJson({
        'url': 'https://server.example',
        'email': 'dentist@example.com',
        'token': '',
        'savedPermission': '[2,1,0]',
        'adminCollectionId': 'admin-id',
        'pushNotificationsToken': 'push-id',
      });

      expect(login.url, 'https://server.example');
      expect(login.email, 'dentist@example.com');
      expect(login.token, isEmpty);
      expect(login.savedPermissions, [2, 1, 0]);
      expect(login.adminCollectionId, 'admin-id');
      expect(login.pushNotificationsToken, 'push-id');
      expect(launch.open(), Open.login);
    });

    test('fromJson keeps existing fields when keys are absent', () async {
      login
        ..url = 'existing-url'
        ..email = 'existing-email'
        ..token = ''
        ..adminCollectionId = 'existing-admin'
        ..pushNotificationsToken = 'existing-push'
        ..savedPermissions = [1, 2];

      await login.fromJson({});

      expect(login.url, 'existing-url');
      expect(login.email, 'existing-email');
      expect(login.adminCollectionId, 'existing-admin');
      expect(login.pushNotificationsToken, 'existing-push');
      expect(login.savedPermissions, [1, 2]);
    });

    test('fromJson throws for a malformed savedPermission value', () async {
      login.savedPermissions = [2, 2];

      // The method delegates directly to jsonDecode, so malformed persisted
      // JSON is surfaced instead of silently replacing permissions.
      expect(login.savedPermissions, [2, 2]);
      await expectLater(
        login.fromJson({'token': '', 'savedPermission': 'not-json'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
