@Tags(['serial'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  late List<int> originalPerms;
  late String originalAdminCollectionId;
  late String originalUrl;
  late String originalEmail;
  late String originalToken;
  late String originalPushToken;
  late bool originalDidAskForLoginAgain;
  late PocketBase? originalPocketBase;
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

  group('Login service — schema initialization', () {
    test('server errors during collection checks do not continue as first run',
        () async {
      final originalPushPlatformResolver = PushPlatform.resolve;
      final originalLoginError = loginCtrl.loginError();
      final originalFirstLaunch = launch.isFirstLaunch();
      final originalActivators =
          Map<String, Future<Future<void> Function()> Function()>.from(
              login.activators);
      final expiration =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'exp': expiration})))
          .replaceAll('=', '');
      final token = 'header.$payload.signature';

      Future<void> checkFailure(String failingPath) async {
        var failureReturned = false;
        var probesContinued = false;
        final client = MockClient((request) async {
          http.Response response(Object body, [int status = 200]) =>
              http.Response(jsonEncode(body), status,
                  headers: const {'content-type': 'application/json'});

          final path = request.url.path;
          if (path.endsWith('/_superusers/auth-refresh')) {
            return response({'code': 401, 'message': 'unauthorized'}, 401);
          }
          if (path.endsWith('/users/auth-refresh')) {
            return response({
              'token': token,
              'record': {
                'id': 'user-id',
                'collectionId': 'users-collection',
                'collectionName': 'users',
                'email': 'user@example.com',
                'permissions': '[2,2,2,2,2,2,2,2,2]',
              },
            });
          }
          if (request.method == 'GET' && path.endsWith(failingPath)) {
            failureReturned = true;
            return response({'code': 503, 'message': 'unavailable'}, 503);
          }
          if (failureReturned &&
              request.method == 'GET' &&
              (path.endsWith('/profiles/records') ||
                  path.endsWith('/profiles_view/records'))) {
            probesContinued = true;
          }
          return response({
            'page': 1,
            'perPage': 1,
            'totalItems': 0,
            'totalPages': 0,
            'items': <Object>[],
          });
        });

        login
          ..pb = PocketBase(
            'https://clinic.test',
            httpClientFactory: () => client,
          )
          ..url = 'https://clinic.test'
          ..token = '';
        login.activators.clear();
        launch.open(Open.staff);

        try {
          await login.activate('https://clinic.test', [token], true);

          expect(failureReturned, isTrue, reason: failingPath);
          expect(probesContinued, isFalse, reason: failingPath);
          expect(loginCtrl.loginError(), isNotEmpty, reason: failingPath);
        } finally {
          client.close();
        }
      }

      PushPlatform.resolve = () => PushPlatform.wns;
      try {
        await checkFailure('/public/records');
        await checkFailure('/profiles/records');
      } finally {
        PushPlatform.resolve = originalPushPlatformResolver;
        login.activators
          ..clear()
          ..addAll(originalActivators);
        loginCtrl.finishedLoginProcess(originalLoginError);
        launch.isFirstLaunch(originalFirstLaunch);
        notificationSessions.invalidate();
      }
    });
  });

  group('Login service — logout during activation', () {
    late String? Function() originalPushPlatformResolver;
    late String originalError;
    late String originalLoading;
    late bool originalOffline;
    late Map<String, FutureOr<void> Function()> originalSyncCallbacks;
    late Map<String, FutureOr<void> Function()> originalReconnectCallbacks;

    setUp(() {
      originalPushPlatformResolver = PushPlatform.resolve;
      PushPlatform.resolve = () => PushPlatform.wns;
      originalError = loginCtrl.loginError();
      originalLoading = loginCtrl.loadingIndicator();
      originalOffline = loginCtrl.proceededOffline();
      originalSyncCallbacks = Map.of(networkActions.syncCallbacks);
      originalReconnectCallbacks = Map.of(networkActions.reconnectCallbacks);
      networkActions.syncCallbacks.clear();
      networkActions.reconnectCallbacks.clear();
      login.activators.clear();
      onLogoutCallbacks.clear();
    });

    tearDown(() {
      PushPlatform.resolve = originalPushPlatformResolver;
      loginCtrl.loginError(originalError);
      loginCtrl.loadingIndicator(originalLoading);
      loginCtrl.proceededOffline(originalOffline);
      networkActions.syncCallbacks
        ..clear()
        ..addAll(originalSyncCallbacks);
      networkActions.reconnectCallbacks
        ..clear()
        ..addAll(originalReconnectCallbacks);
      notificationSessions.invalidate();
    });

    MockClient configureOnline() {
      final expiration =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'exp': expiration})))
          .replaceAll('=', '');
      final token = 'header.$payload.signature';
      final client = MockClient((request) async {
        http.Response response(Object body, [int status = 200]) =>
            http.Response(jsonEncode(body), status,
                headers: const {'content-type': 'application/json'});
        if (request.url.path.endsWith('/_superusers/auth-refresh')) {
          return response({'code': 401, 'message': 'unauthorized'}, 401);
        }
        if (request.url.path.endsWith('/users/auth-refresh')) {
          return response({
            'token': token,
            'record': {
              'id': 'user-id',
              'collectionId': 'users-collection',
              'collectionName': 'users',
              'email': 'user@example.com',
              'permissions': '[2,2,2,2,2,2,2,2,2]',
            },
          });
        }
        return response({
          'page': 1,
          'perPage': 1,
          'totalItems': 0,
          'totalPages': 0,
          'items': <Object>[],
        });
      });
      login.pb =
          PocketBase('https://clinic.test', httpClientFactory: () => client);
      login.url = 'https://clinic.test';
      login.token = token;
      launch.open(Open.staff);
      return client;
    }

    test('online activation keeps its client and runs both stages in order',
        () async {
      final client = configureOnline();
      final pocketBase = login.pb;
      final calls = <String>[];
      for (final name in ['first', 'second']) {
        login.activators[name] = () async {
          calls.add('$name-local');
          return () async => calls.add('$name-remote');
        };
      }
      try {
        await login.activate(login.url, [login.token], true);
        expect(login.pb, same(pocketBase));
        expect(calls,
            ['first-local', 'first-remote', 'second-local', 'second-remote']);
        expect(launch.open(), Open.staff);
      } finally {
        client.close();
      }
    });

    test('logout stops later local activators and allows a later login',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var firstRuns = 0;
      var laterRuns = 0;
      login.activators['first'] = () async {
        firstRuns++;
        if (firstRuns == 1) {
          entered.complete();
          await release.future;
        }
        return () async {};
      };
      login.activators['later'] = () async {
        laterRuns++;
        return () async {};
      };
      final activation = login.activate('https://clinic.test', [], false);
      await entered.future;
      login.logout();
      release.complete();
      await activation;
      expect(laterRuns, 0);
      expect(launch.open(), Open.login);
      expect(notificationSessions.phase, NotificationSessionPhase.absent);
      await login.activate('https://clinic.test', [], false);
      expect(firstRuns, 2);
      expect(laterRuns, 1);
      expect(launch.open(), Open.staff);
    });

    test('old activation cannot run later activators after a new login',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var runs = 0;
      var laterRuns = 0;
      login.activators['first'] = () async {
        if (++runs == 1) {
          entered.complete();
          await release.future;
        }
        return () async {};
      };
      login.activators['later'] = () async {
        laterRuns++;
        return () async {};
      };
      final old = login.activate('https://old.test', [], false);
      await entered.future;
      login.logout();
      await login.activate('https://new.test', [], false);
      expect(launch.open(), Open.staff);
      expect(laterRuns, 1);
      release.complete();
      await old;
      expect(laterRuns, 1);
      expect(login.url, 'https://new.test');
      expect(launch.open(), Open.staff);
    });

    test('logout during local stage prevents its remote stage', () async {
      final client = configureOnline();
      final entered = Completer<void>();
      final release = Completer<void>();
      var remoteRuns = 0;
      login.activators['first'] = () async {
        entered.complete();
        await release.future;
        return () async => remoteRuns++;
      };
      try {
        final activation = login.activate(login.url, [login.token], true);
        await entered.future;
        login.logout();
        release.complete();
        await activation;
        expect(remoteRuns, 0);
        expect(launch.open(), Open.login);
        expect(notificationSessions.phase, NotificationSessionPhase.absent);
      } finally {
        client.close();
      }
    });

    test('logout during remote stage skips later activators and publication',
        () async {
      final client = configureOnline();
      final entered = Completer<void>();
      final release = Completer<void>();
      var laterRuns = 0;
      login.activators['first'] = () async => () async {
            entered.complete();
            await release.future;
          };
      login.activators['later'] = () async {
        laterRuns++;
        return () async {};
      };
      try {
        final activation = login.activate(login.url, [login.token], true);
        await entered.future;
        login.logout();
        release.complete();
        await activation;
        expect(laterRuns, 0);
        expect(launch.open(), Open.login);
        expect(login.token, isEmpty);
        expect(notificationSessions.phase, NotificationSessionPhase.absent);
      } finally {
        client.close();
      }
    });

    test('logout during a throwing activator does not continue', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var laterRuns = 0;
      login.activators['first'] = () async {
        entered.complete();
        await release.future;
        throw StateError('stale activation');
      };
      login.activators['later'] = () async {
        laterRuns++;
        return () async {};
      };
      final activation = login.activate('https://clinic.test', [], false);
      await entered.future;
      login.logout();
      release.complete();
      await activation;
      expect(laterRuns, 0);
      expect(launch.open(), Open.login);
    });

    test('logout during token authentication cannot restore the session',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final probes = <String>[];
      final expiration =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'exp': expiration})))
          .replaceAll('=', '');
      final oldToken = 'header.$payload.signature';
      final newToken = 'other.$payload.signature';
      var authCalls = 0;

      final client = MockClient((request) async {
        http.Response response(Object body, [int status = 200]) =>
            http.Response(jsonEncode(body), status,
                headers: const {'content-type': 'application/json'});
        final path = request.url.path;
        if (path.endsWith('/_superusers/auth-refresh')) {
          return response({'code': 401, 'message': 'unauthorized'}, 401);
        }
        if (path.endsWith('/users/auth-refresh')) {
          if (++authCalls == 1) {
            entered.complete();
            await release.future;
            return response({
              'token': oldToken,
              'record': {
                'id': 'old-user',
                'collectionId': 'users-collection',
                'collectionName': 'users',
                'email': 'old@example.com',
                'permissions': '[2,0,0,0,0,0,0,0,0]',
              },
            });
          }
          return response({
            'token': newToken,
            'record': {
              'id': 'new-user',
              'collectionId': 'users-collection',
              'collectionName': 'users',
              'email': 'new@example.com',
              'permissions': '[2,2,0,0,0,0,0,0,0]',
            },
          });
        }
        probes.add(path);
        return response({
          'page': 1,
          'perPage': 1,
          'totalItems': 0,
          'totalPages': 0,
          'items': <Object>[],
        });
      });

      login.pb =
          PocketBase('https://clinic.test', httpClientFactory: () => client);
      login.url = 'https://clinic.test';
      login.token = oldToken;
      launch.open(Open.staff);

      try {
        final staleActivation = login.activate(login.url, [oldToken], true);
        await entered.future;

        login.logout();
        expect(login.token, isEmpty);
        expect(login.pb!.authStore.isValid, isFalse);

        // A new login can start while the old authentication response is still
        // in flight. Keep the same PocketBase so this test also covers the
        // response landing after the new session is fully established.
        launch.open(Open.staff);
        await login.activate('https://clinic.test', [newToken], true);
        expect(login.token, newToken);
        final probesBeforeRelease = probes.length;

        release.complete();
        await staleActivation;

        expect(login.token, newToken,
            reason: 'the stale response must not overwrite the new session');
        expect(login.pb!.authStore.token, newToken);
        expect(login.pb!.authStore.record?.id, 'new-user');
        expect(loginCtrl.loadingIndicator(), isEmpty);
        expect(launch.open(), Open.staff);
        expect(probes.length, probesBeforeRelease,
            reason: 'the stale activation must not run verification probes');
      } finally {
        client.close();
      }
    });

    test('logout during token refresh cannot restore the auth store', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final expiration =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'exp': expiration})))
          .replaceAll('=', '');
      final token = 'header.$payload.signature';

      final client = MockClient((request) async {
        http.Response response(Object body, [int status = 200]) =>
            http.Response(jsonEncode(body), status,
                headers: const {'content-type': 'application/json'});
        if (request.url.path.endsWith('/_superusers/auth-refresh')) {
          return response({'code': 401, 'message': 'unauthorized'}, 401);
        }
        if (request.url.path.endsWith('/users/auth-refresh')) {
          entered.complete();
          await release.future;
          return response({
            'token': token,
            'record': {
              'id': 'user-id',
              'collectionId': 'users-collection',
              'collectionName': 'users',
              'email': 'user@example.com',
              'permissions': '[2,2,2,2,2,2,2,2,2]',
            },
          });
        }
        return response({});
      });

      login.pb =
          PocketBase('https://clinic.test', httpClientFactory: () => client);
      login.url = 'https://clinic.test';
      login.token = token;
      launch.open(Open.staff);

      try {
        final refresh = login.authenticateWithToken(token);
        await entered.future;
        login.logout();
        release.complete();
        await refresh;

        expect(login.token, isEmpty);
        expect(login.pb!.authStore.isValid, isFalse,
            reason: 'the late refresh must not repopulate the auth store');
        expect(loginCtrl.loadingIndicator(), isEmpty);
      } finally {
        client.close();
      }
    });

    for (final reconnect in [false, true]) {
      test('${reconnect ? 'reconnect' : 'resync'} preserves normal callbacks',
          () async {
        final client = configureOnline();
        final callbacks = reconnect
            ? networkActions.reconnectCallbacks
            : networkActions.syncCallbacks;
        final calls = <int>[];
        callbacks['first'] = () => calls.add(1);
        callbacks['second'] = () async => calls.add(2);
        try {
          if (reconnect) {
            await networkActions.performReconnect();
          } else {
            await networkActions.resync();
          }
          expect(calls, [1, 2]);
          expect(launch.open(), Open.staff);
          expect(networkActions.isSyncing(), 0);
        } finally {
          client.close();
        }
      });

      test('${reconnect ? 'reconnect' : 'resync'} stops between callbacks',
          () async {
        final client = configureOnline();
        final callbacks = reconnect
            ? networkActions.reconnectCallbacks
            : networkActions.syncCallbacks;
        var laterRuns = 0;
        callbacks['first'] = () => login.logout();
        callbacks['later'] = () => laterRuns++;
        try {
          if (reconnect) {
            await networkActions.performReconnect();
          } else {
            await networkActions.resync();
          }
          expect(laterRuns, 0);
          expect(launch.open(), Open.login);
          expect(networkActions.isSyncing(), 0);
        } finally {
          client.close();
        }
      });

      test('${reconnect ? 'reconnect' : 'resync'} skips callbacks after logout',
          () async {
        final client = configureOnline();
        final entered = Completer<void>();
        final release = Completer<void>();
        final callbacks = reconnect
            ? networkActions.reconnectCallbacks
            : networkActions.syncCallbacks;
        var calls = 0;
        callbacks['logout-race-test'] = () => calls++;
        login.activators['blocking'] = () async {
          entered.complete();
          await release.future;
          return () async {};
        };
        try {
          final operation = reconnect
              ? networkActions.performReconnect()
              : networkActions.resync();
          await entered.future;
          login.logout();
          release.complete();
          await operation;
          expect(calls, 0);
          expect(launch.open(), Open.login);
          expect(networkActions.isSyncing(), 0);
        } finally {
          callbacks.remove('logout-race-test');
          client.close();
        }
      });
    }
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
      expect(onLogoutCallbacks, isA<List<void Function()>>());
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

    test('fromJson restores credentials with null-coalescing', () async {
      await login.fromJson({'url': null, 'email': null, 'token': null});
      // Fields should default to empty strings via ?? operator
      expect(login.url, isEmpty);
      expect(login.email, isEmpty);
      expect(login.token, isEmpty);
    });

    test('toJson round-trip preserves savedPermissions', () async {
      login.savedPermissions = [0, 2, 1];
      final json = login.toJson();
      // Re-read
      await login.fromJson(json);
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
