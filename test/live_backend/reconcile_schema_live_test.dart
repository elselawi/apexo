@Tags(['live_backend', 'serial'])
library;

import 'dart:convert';

import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import '../secret.dart';

/// Live verification of the schema-reconcile upgrade path (C2):
///  - importing with the default `deleteMissing=false` is a pure upsert that
///    never deletes existing collections or records;
///  - `reconcileSchema()` applies the patient-scoped `public` view rule to an
///    existing install and re-applies the users createRule hardening;
///  - the applied rule enforces patient scoping server-side via the `pid`
///    query parameter (unauthenticated).
///
/// Run with:
///   flutter test test/live_backend/reconcile_schema_live_test.dart -j 1
void main() {
  final pb = PocketBase(testPBServer);

  // Explicit record ids (must satisfy the data/profiles id field constraints:
  // 15 chars, [a-zA-Z0-9_]/[a-z0-9]) so tests are idempotent and cleanup is
  // trivial.
  const apptA = 'verify_a_000001';
  const apptB = 'verify_b_000001';
  const profileRow = 'verifyprofile0a';

  Future<void> cleanupRows() async {
    for (final id in [apptA, apptB]) {
      try {
        await pb.collection(dataCollectionName).delete(id);
      } catch (_) {}
    }
    try {
      await pb.collection(profilesCollectionName).delete(profileRow);
    } catch (_) {}
  }

  Future<void> createAppointment(String id, String patientID) async {
    await pb.collection(dataCollectionName).create(body: {
      'id': id,
      'store': 'appointments',
      'data': jsonEncode({
        'patientID': patientID,
        'date': 1000,
        'price': 100,
        'paid': 0,
        'isDone': false,
        'archived': false,
        'prescriptions': <String>[],
      }),
    });
  }

  /// Attaches the server's current collection ids to the given definitions
  /// (imports over existing collections fail when the id is empty — see the
  /// comment in reconcileSchema).
  Future<List<CollectionModel>> withServerIds(
      List<CollectionModel> models) async {
    final existing = await pb.collections.getFullList();
    final idByName = {for (final c in existing) c.name: c.id};
    return models.map((m) {
      final id = idByName[m.name];
      return (id == null || id.isEmpty)
          ? m
          : (CollectionModel.fromJson(m.toJson())..id = id);
    }).toList();
  }

  setUpAll(() async {
    if (pb.authStore.isValid == false) {
      await pb
          .collection('_superusers')
          .authWithPassword(testPBEmail, testPBPassword);
    }
    // Make sure the version marker can't skip the upgrade under test.
    await storeAppliedSchemaVersion(simpleHash(testPBServer), 0);
  });

  tearDownAll(() async {
    await cleanupRows();
  });

  group('Schema reconcile (C2 upgrade path)', () {
    test(
        'reconcileSchema upgrades an existing install without deleting '
        'collections or records', () async {
      // 1) Simulate an "existing install" whose public view predates the
      //    scoped rule (empty rules), with real records already in place.
      final oldPublic =
          CollectionModel.fromJson(publicCollectionImport.toJson())
            ..listRule = ''
            ..viewRule = '';
      await pb.collections.import(await withServerIds([
        dataCollectionImport,
        oldPublic,
        profilesCollectionImport,
        profilesViewCollectionImport,
      ]));

      await createAppointment(apptA, 'verify_a');
      await pb.collection(profilesCollectionName).create(body: {
        'id': profileRow,
        'account_id': apptA,
        'name': 'Verify Row',
        'permissions': '[0, 0, 0, 0, 0, 0, 0, 0, 0]',
        'operate': false,
      });

      final collectionNamesBefore =
          (await pb.collections.getFullList()).map((c) => c.name).toSet();

      // Sanity: the simulated install still has the OLD (empty) public rules.
      expect((await pb.collections.getOne('public')).listRule, '');

      // 2) Upgrade via the app's actual reconcile path.
      await reconcileSchema(pb, clinicServer: testPBServer);

      // 3) Nothing was deleted...
      final collectionNamesAfter =
          (await pb.collections.getFullList()).map((c) => c.name).toSet();
      expect(collectionNamesAfter, containsAll(collectionNamesBefore));

      // ...records are intact...
      expect((await pb.collection(dataCollectionName).getOne(apptA)).id, apptA);
      expect(
          (await pb.collection(profilesCollectionName).getOne(profileRow)).id,
          profileRow);

      // ...and the scoped rule + users hardening were applied.
      expect((await pb.collections.getOne('public')).listRule,
          rulePublicPatientScoped);
      expect((await pb.collections.getOne('public')).viewRule,
          rulePublicPatientScoped);
      expect((await pb.collections.getOne('users')).createRule,
          '@request.auth.collectionName = "_superusers"');

      // The applied marker is now at the current schema version, so a second
      // reconcile is a no-op (idempotency).
      expect(
          await appliedSchemaVersion(simpleHash(testPBServer)), schemaVersion);

      // Cleanup sentinels (kept until after this test's assertions).
      await cleanupRows();
    });

    test('public view enforces patient scoping server-side via pid', () async {
      // Ensure the scoped rule is applied (self-sufficient regardless of the
      // order in which the tests ran).
      await storeAppliedSchemaVersion(simpleHash(testPBServer), 0);
      await reconcileSchema(pb, clinicServer: testPBServer);

      // Two appointments belonging to two different patients.
      await createAppointment(apptA, 'verify_a');
      await createAppointment(apptB, 'verify_b');

      // Unauthenticated clients (exactly how the patient web app talks to PB).
      final anon = PocketBase(testPBServer);

      // No pid at all → the rule denies everything.
      final noPid = await anon.collection('public').getList(perPage: 200);
      expect(noPid.items, isEmpty);

      // pid=verify_a → only that patient's rows are visible.
      final onlyA = await anon.collection('public').getList(
          perPage: 200, filter: 'pid="verify_a"', query: {'pid': 'verify_a'});
      expect(onlyA.items.map((r) => r.getStringValue('pid')).toSet(),
          {'verify_a'});
      expect(onlyA.items.map((r) => r.getStringValue('pid')),
          isNot(contains('verify_b')));

      // pid=verify_b → only that patient's rows are visible.
      final onlyB = await anon.collection('public').getList(
          perPage: 200, filter: 'pid="verify_b"', query: {'pid': 'verify_b'});
      expect(onlyB.items.map((r) => r.getStringValue('pid')).toSet(),
          {'verify_b'});
      expect(onlyB.items.map((r) => r.getStringValue('pid')),
          isNot(contains('verify_a')));

      // A bogus pid returns nothing.
      final bogus = await anon
          .collection('public')
          .getList(perPage: 200, query: {'pid': 'does_not_exist'});
      expect(bogus.items, isEmpty);

      await cleanupRows();
    });
  });
}
