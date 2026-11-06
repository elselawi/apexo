@Tags(['serial'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/hive_setup.dart';

class _BoundaryRemote extends SaveRemote {
  _BoundaryRemote()
      : super(
          storeName: 'timestamp-boundary',
          pbInstance: PocketBase('https://example.test'),
        );

  final rows = <String, Row>{};
  final pushed = <RowToWriteRemotely>[];

  @override
  Future<void> checkOnline() async => isOnline = true;

  @override
  Future<int> getVersion() async => rows.values.fold<int>(
        0,
        (version, row) => row.ts > version ? row.ts : version,
      );

  @override
  Future<VersionedResult> getSince({int version = 0}) async {
    final updates = rows.values.where((row) => row.ts > version).toList();
    return VersionedResult(await getVersion(), updates);
  }

  @override
  Future<bool> put(List<RowToWriteRemotely> data) async {
    final timestamp = await getVersion() + 1;
    for (final row in data) {
      pushed.add(RowToWriteRemotely(id: row.id, data: row.data));
      rows[row.id] = Row(id: row.id, data: row.data, ts: timestamp);
    }
    return true;
  }
}

void main() {
  late Directory directory;
  late SaveLocal local;
  late _BoundaryRemote remote;
  late Store<Patient> store;

  setUp(() async {
    directory = await setupTestHive();
    local = SaveLocal(
      name: 'timestamp-boundary',
      uniqueId: '',
      storagePath: directory.path,
    );
    remote = _BoundaryRemote();
    store = Store<Patient>(
      modeling: Patient.fromJson,
      local: local,
      remote: remote,
      manualSyncOnly: true,
      debounceMS: 1,
    );
    await store.loaded;
  });

  tearDown(() async {
    await store.deactivatePersistenceSession();
    store.observableMap.dispose();
    await local.dispose();
    await teardownTestHive(directory);
  });

  for (final entry in <String, dynamic>{
    'email': 'old@example.test',
    'address': 'Old address',
    'notes': 'Old notes',
    'gender': 1,
    'portalAccessRevoked': true,
    'followUp': 30000000,
  }.entries) {
    test('boundary replay preserves an offline ${entry.key} clear', () async {
      final original = Patient.fromJson({
        'id': 'record',
        'title': 'Example',
        entry.key: entry.value,
      });
      final edited = Patient.fromJson({'id': 'record', 'title': 'Example'});
      expect(edited.toJson(), isNot(contains(entry.key)));
      remote.rows['record'] = Row(
        id: 'record',
        data: jsonEncode(original.toJson()),
        ts: 100,
      );
      await local.put({'record': jsonEncode(edited.toJson())});
      await local.putVersion(100);
      await local.putDeferred({'record': 101});
      await store.reload();

      final results = await store.synchronize();

      expect(remote.pushed, hasLength(1));
      expect(jsonDecode(remote.pushed.single.data), edited.toJson());
      expect(jsonDecode(await local.get('record')), edited.toJson());
      expect(store.get('record')!.toJson(), edited.toJson());
      expect(results.first.conflicts, 0);
      expect(await local.getDeferred(), isEmpty);
      expect(results.last.exception, 'nothing to sync');
    });
  }

  test('boundary replay still pulls other rows while a local edit is pending',
      () async {
    remote.rows.addAll({
      'record':
          Row(id: 'record', data: '{"id":"record","title":"Old"}', ts: 100),
      'other': Row(id: 'other', data: '{"id":"other","title":"New"}', ts: 100),
    });
    await local.put({'record': '{"id":"record","title":"Edited"}'});
    await local.putVersion(100);
    await local.putDeferred({'record': 101});
    await store.reload();

    final results = await store.synchronize();

    expect(results.first.conflicts, 0);
    expect(results.first.pulled, 1);
    expect(store.get('record')!.title, 'Edited');
    expect(store.get('other')!.title, 'New');
    expect(remote.pushed, hasLength(1));
    expect(remote.pushed.single.id, 'record');
    expect(await local.getDeferred(), isEmpty);
  });

  test('strictly newer rows still use the existing conflict merge', () async {
    remote.rows['record'] = Row(
      id: 'record',
      data: '{"id":"record","title":"Remote","address":"Remote address"}',
      ts: 101,
    );
    await local.put({
      'record': '{"id":"record","title":"Local","email":"local@example.test"}',
    });
    await local.putVersion(100);
    await local.putDeferred({'record': 102});
    await store.reload();

    final results = await store.synchronize();

    expect(results.first.conflicts, 1);
    expect(remote.pushed, hasLength(1));
    expect(store.get('record')!.title, 'Local');
    expect(store.get('record')!.email, 'local@example.test');
    expect(store.get('record')!.address, 'Remote address');
    expect(await local.getDeferred(), isEmpty);
  });
}
