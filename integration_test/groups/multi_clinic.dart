import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart' show schemaVersion;
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/credentials.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';

const _secondClinicUrl = 'http://127.0.0.1:1/second-clinic';

String _id(String prefix) => simpleHash(
      '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      length: 15,
    );

Patient _patient(String name) => Patient.fromJson({
      'id': _id('clinic-patient'),
      'title': name,
    });

Future<void> _switchToClinic(
  WidgetTester tester, {
  required String server,
  required bool online,
}) async {
  login.logout();
  await E2E.settle(tester, frames: 10);
  await login.activate(
    server,
    online ? [pbEmail, pbPassword] : const [],
    online,
  );
  await E2E.waitForDatabase(tester);
  await E2E.settle(tester, frames: 15);
  expect(launch.open(), Open.staff,
      reason: 'Switching to "$server" did not reach the staff shell.');
}

Future<void> _restorePrimaryClinic(WidgetTester tester) => _switchToClinic(
      tester,
      server: pbServer,
      online: true,
    );

Future<void> _deletePatientEverywhere(String id) async {
  await RemoteRows.delete(id);
  patients.purge(id);
}

void registerMultiClinicTests() {
  group('multi_clinic', () {
    testWidgets('01: switching clinics changes the Hive namespace and starts empty',
        (tester) async {
      await E2E.signIn(tester);
      final primaryNamespace = patients.local?.uniqueId;
      addTearDown(() async => _restorePrimaryClinic(tester));

      expect(primaryNamespace, simpleHash(pbServer),
          reason: 'The primary clinic is not using its URL-derived Hive namespace.');

      await _switchToClinic(tester, server: _secondClinicUrl, online: false);

      expect(login.url, _secondClinicUrl,
          reason: 'The session did not switch to the second clinic URL.');
      expect(patients.local?.uniqueId, simpleHash(_secondClinicUrl),
          reason: 'The second clinic did not get its own Hive namespace.');
      expect(patients.local?.uniqueId, isNot(primaryNamespace),
          reason: 'Both clinics ended up sharing one Hive namespace.');
      expect(await patients.total(), 0,
          reason: 'A brand-new clinic inherited the first clinic\'s patients.');
    });

    testWidgets('02: each clinic keeps its own local rows', (tester) async {
      await E2E.signIn(tester);
      final primary = _patient(Fixtures.stamp('e2e clinic A'));
      final secondary = _patient(Fixtures.stamp('e2e clinic B'));
      addTearDown(() async {
        await _switchToClinic(tester, server: _secondClinicUrl, online: false);
        patients.purge(secondary.id);
        await _restorePrimaryClinic(tester);
        await _deletePatientEverywhere(primary.id);
      });

      patients.set(primary);
      await patients.waitUntilChangesAreProcessed();

      await _switchToClinic(tester, server: _secondClinicUrl, online: false);
      expect(patients.get(primary.id), isNull,
          reason: 'The second clinic inherited a patient from the first clinic.');

      patients.set(secondary);
      await patients.waitUntilChangesAreProcessed();
      expect(patients.get(secondary.id), isNotNull,
          reason: 'The second clinic did not keep its own local patient.');

      await _restorePrimaryClinic(tester);
      expect(patients.get(primary.id), isNotNull,
          reason: 'Switching back lost the first clinic\'s patient.');
      expect(patients.get(secondary.id), isNull,
          reason: 'The first clinic leaked a patient from the second clinic.');
    });

    testWidgets('03: schema markers are stored per clinic URL', (tester) async {
      await E2E.signIn(tester);
      final primaryKey = simpleHash(pbServer);
      final secondKey = simpleHash(_secondClinicUrl);
      final beforePrimary = await appliedSchemaVersion(primaryKey);
      final beforeSecond = await appliedSchemaVersion(secondKey);
      addTearDown(() async {
        await storeAppliedSchemaVersion(primaryKey, beforePrimary);
        await storeAppliedSchemaVersion(secondKey, beforeSecond);
      });

      await storeAppliedSchemaVersion(primaryKey, schemaVersion);
      await storeAppliedSchemaVersion(secondKey, 0);

      expect(await appliedSchemaVersion(primaryKey), schemaVersion,
          reason: 'The primary clinic did not keep its own schema marker.');
      expect(await appliedSchemaVersion(secondKey), 0,
          reason: 'Writing the primary marker also changed the second clinic.');
    });

    testWidgets(
        '04: the login form remembers the last server per clinic (feature absent)',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets(
        '05: schema reconciliation rewrites a drifted shared clinic (unsafe in shared e2e)',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets(
        '06: schema reconciliation skips a current marker (unsafe shared-server mutation)',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('07: a legacy Hive-era clinic migrates without losing rows',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);
  });
}
