@Tags(['serial'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/hive_setup.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await setupTestHive();
  });

  tearDownAll(() async {
    await teardownTestHive(hiveDir);
  });

  group('schema version marker', () {
    test('defaults to 0 for a clinic that was never reconciled', () async {
      final key = 'never-reconciled-${DateTime.now().millisecondsSinceEpoch}';
      expect(await appliedSchemaVersion(key), 0);
    });

    test('round-trips the applied schema version', () async {
      final key = 'roundtrip-${DateTime.now().millisecondsSinceEpoch}';
      expect(await appliedSchemaVersion(key), 0);

      await storeAppliedSchemaVersion(key, 1);
      expect(await appliedSchemaVersion(key), 1);

      await storeAppliedSchemaVersion(key, schemaVersion);
      expect(await appliedSchemaVersion(key), schemaVersion);
    });

    test('reports a stale stored version so the next admin login re-reconciles',
        () async {
      final key = 'stale-${DateTime.now().millisecondsSinceEpoch}';
      await storeAppliedSchemaVersion(key, 0);
      expect(await appliedSchemaVersion(key), 0);
    });

    test('markSchemaApplied records the current version for that clinic',
        () async {
      final server = 'https://mark-${DateTime.now().microsecondsSinceEpoch}';
      expect(await appliedSchemaVersion(simpleHash(server)), 0);
      await markSchemaApplied(server);
      expect(await appliedSchemaVersion(simpleHash(server)), schemaVersion);
    });
  });

  group('reconcileSchema', () {
    const hardenedRule = '@request.auth.collectionName = "_superusers"';

    /// Unique per test, so a stored marker never leaks into another test.
    String clinicServer(String name) =>
        'https://$name-${DateTime.now().microsecondsSinceEpoch}';

    PocketBase fakeServer(
      List<String> requests, {
      String? usersCreateRule = hardenedRule,
      bool failImport = false,
      bool failUsersUpdate = false,
      List<String>? collectionNames,
    }) {
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        http.Response json(Object body, [int status = 200]) =>
            http.Response(jsonEncode(body), status,
                headers: const {'content-type': 'application/json'});

        final path = request.url.path;
        if (request.method == 'GET' && path.endsWith('/api/collections')) {
          final names = collectionNames ??
              [
                dataCollectionName,
                publicCollectionName,
                profilesCollectionName,
                profilesViewCollectionName,
                'users',
              ];
          final items = [
            for (var i = 0; i < names.length; i++)
              {
                'id': 'collection$i'.padRight(15, 'x'),
                'name': names[i],
                if (names[i] == 'users') 'createRule': usersCreateRule,
              },
          ];
          return json({
            'page': 1,
            'perPage': 200,
            'totalItems': items.length,
            'totalPages': 1,
            'items': items,
          });
        }
        if (request.method == 'PUT' &&
            path.endsWith('/api/collections/import')) {
          if (failImport) return json({'message': 'nope'}, 500);
          return http.Response('', 204);
        }
        if (request.method == 'PATCH' &&
            path.endsWith('/api/collections/users')) {
          if (failUsersUpdate) return json({'message': 'nope'}, 500);
          return json({'id': 'users-collection', 'name': 'users'});
        }
        return json({'message': 'not found'}, 404);
      });
      return PocketBase('https://clinic.test', httpClientFactory: () => client);
    }

    test('does nothing when the caller already knows the applied version',
        () async {
      final requests = <String>[];
      var workAnnounced = 0;

      await reconcileSchema(
        fakeServer(requests),
        clinicServer: clinicServer('known'),
        appliedVersion: schemaVersion,
        onWork: () => workAnnounced++,
      );

      expect(requests, isEmpty);
      expect(workAnnounced, 0);
    });

    test('does nothing when the device marker is current', () async {
      final clinic = clinicServer('stored');
      await storeAppliedSchemaVersion(simpleHash(clinic), schemaVersion);
      final requests = <String>[];
      var workAnnounced = 0;

      await reconcileSchema(
        fakeServer(requests),
        clinicServer: clinic,
        onWork: () => workAnnounced++,
      );

      expect(requests, isEmpty);
      expect(workAnnounced, 0);
    });

    test('imports once, announces the work and records the version', () async {
      final clinic = clinicServer('fresh');
      final requests = <String>[];
      var workAnnounced = 0;

      await reconcileSchema(
        fakeServer(requests),
        clinicServer: clinic,
        onWork: () => workAnnounced++,
      );

      expect(
          requests,
          [
            'GET /api/collections',
            'PUT /api/collections/import',
          ],
          reason: 'a matching users rule must not be re-written');
      expect(workAnnounced, 1);
      expect(await appliedSchemaVersion(simpleHash(clinic)), schemaVersion);

      // A second call is a no-op, which is what keeps the next login fast.
      final second = <String>[];
      await reconcileSchema(fakeServer(second), clinicServer: clinic);
      expect(second, isEmpty);
    });

    test('re-applies the users create rule when it drifted', () async {
      final requests = <String>[];

      await reconcileSchema(
        fakeServer(requests, usersCreateRule: ''),
        clinicServer: clinicServer('rule-drift'),
      );

      expect(requests, contains('PATCH /api/collections/users'));
    });

    test('keeps the version marker when only the users rule fails', () async {
      final clinic = clinicServer('rule-failure');
      final requests = <String>[];

      await reconcileSchema(
        fakeServer(requests, usersCreateRule: '', failUsersUpdate: true),
        clinicServer: clinic,
      );

      expect(requests, contains('PATCH /api/collections/users'));
      expect(await appliedSchemaVersion(simpleHash(clinic)), schemaVersion,
          reason: 'the import already made the schema current');
    });

    test('leaves the marker unset when the import fails', () async {
      final clinic = clinicServer('import-failure');

      await expectLater(
        reconcileSchema(
          fakeServer(<String>[], failImport: true),
          clinicServer: clinic,
        ),
        throwsA(anything),
      );

      expect(await appliedSchemaVersion(simpleHash(clinic)), 0,
          reason: 'a failed import must be retried on the next admin login');
    });

    test('refuses to import when the collection list comes back empty',
        () async {
      final requests = <String>[];

      await expectLater(
        reconcileSchema(
          fakeServer(requests, collectionNames: const []),
          clinicServer: clinicServer('empty-list'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(requests, ['GET /api/collections'],
          reason: 'an import without the server ids could rewrite collections');
    });
  });
}
