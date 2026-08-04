import 'dart:io';

import 'package:apexo/services/notifications/model_push_data.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/hive_setup.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await setupTestHive();
    deferredPush.init('test-server');
  });

  tearDownAll(() async {
    deferredPush.reset();
    await teardownTestHive(hiveDir);
  });

  group('deferredPush', () {
    test('init does not throw when already initialized', () {
      // Second init call is guarded by _initialized flag
      expect(() => deferredPush.init('test-server'), returnsNormally);
    });

    test('putBulk and getByID round-trip', () async {
      final push = PushData(
        store: 'appointments',
        id: 'push-1',
        readableIdentifier: 'Test Patient',
        isCreation: true,
        isUpdate: false,
        updatedFields: [],
        oldVals: [],
        newVals: [],
        targetIDs: ['user1'],
      );

      await deferredPush.putBulk([push]);

      final retrieved = await deferredPush.getByID('push-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'push-1');
      expect(retrieved.store, 'appointments');
      expect(retrieved.readableIdentifier, 'Test Patient');
    });

    test('getByID returns null for unknown key', () async {
      final result = await deferredPush.getByID('non-existent-id');
      expect(result, isNull);
    });

    test('putBulk overwrites existing entries', () async {
      final push1 = PushData(
        store: 'notes',
        id: 'note-push',
        readableIdentifier: 'Original',
        isCreation: true,
        isUpdate: false,
        updatedFields: [],
        oldVals: [],
        newVals: [],
        targetIDs: [],
      );

      await deferredPush.putBulk([push1]);

      final push2 = PushData(
        store: 'notes',
        id: 'note-push',
        readableIdentifier: 'Updated',
        isCreation: false,
        isUpdate: true,
        updatedFields: ['done'],
        oldVals: [false],
        newVals: [true],
        targetIDs: [],
      );

      await deferredPush.putBulk([push2]);

      final retrieved = await deferredPush.getByID('note-push');
      expect(retrieved, isNotNull);
      expect(retrieved!.readableIdentifier, 'Updated');
      expect(retrieved.isUpdate, isTrue);
    });

    test('putBulk stores multiple entries at once', () async {
      final pushes = List.generate(
          5,
          (i) => PushData(
                store: 'appointments',
                id: 'push-bulk-$i',
                readableIdentifier: 'Patient $i',
                isCreation: true,
                isUpdate: false,
                updatedFields: [],
                oldVals: [],
                newVals: [],
                targetIDs: ['user$i'],
              ));

      await deferredPush.putBulk(pushes);

      for (var i = 0; i < 5; i++) {
        final retrieved = await deferredPush.getByID('push-bulk-$i');
        expect(retrieved, isNotNull);
        expect(retrieved!.readableIdentifier, 'Patient $i');
      }
    });

    test('clearByStore removes all entries for a store', () async {
      // Add appointments pushes
      await deferredPush.putBulk([
        PushData(
          store: 'appointments',
          id: 'appt-1',
          readableIdentifier: 'Appt 1',
          isCreation: true,
          isUpdate: false,
          updatedFields: [],
          oldVals: [],
          newVals: [],
          targetIDs: [],
        ),
        PushData(
          store: 'appointments',
          id: 'appt-2',
          readableIdentifier: 'Appt 2',
          isCreation: true,
          isUpdate: false,
          updatedFields: [],
          oldVals: [],
          newVals: [],
          targetIDs: [],
        ),
      ]);

      // Add a notes push
      await deferredPush.putBulk([
        PushData(
          store: 'notes',
          id: 'note-1',
          readableIdentifier: 'Note 1',
          isCreation: true,
          isUpdate: false,
          updatedFields: [],
          oldVals: [],
          newVals: [],
          targetIDs: [],
        ),
      ]);

      // Clear only appointments
      await deferredPush.clearByStore('appointments');

      // Appointments should be gone
      expect(await deferredPush.getByID('appt-1'), isNull);
      expect(await deferredPush.getByID('appt-2'), isNull);

      // Notes should still exist
      expect(await deferredPush.getByID('note-1'), isNotNull);
    });

    test('clearByStore does not affect other stores', () async {
      await deferredPush.putBulk([
        PushData(
          store: 'expenses',
          id: 'exp-1',
          readableIdentifier: 'Exp 1',
          isCreation: true,
          isUpdate: false,
          updatedFields: [],
          oldVals: [],
          newVals: [],
          targetIDs: [],
        ),
      ]);

      await deferredPush.clearByStore('appointments');

      // Expenses should still be there
      expect(await deferredPush.getByID('exp-1'), isNotNull);
    });
  });
}
