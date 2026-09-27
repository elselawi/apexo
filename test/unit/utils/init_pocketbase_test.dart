@Tags(['serial'])
library;

import 'dart:io';

import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
