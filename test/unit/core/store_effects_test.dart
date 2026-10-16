import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/core/model.dart';
import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/core/synchronization/document_loading.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/core/synchronization/store_effects.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/hive_setup.dart';

class _Notifiable extends Model {
  _Notifiable.fromJson(super.json) : super.fromJson();
  @override
  bool get pushOnCreation => true;
  @override
  List<String> get targetsToPushTo => ['operator'];
  @override
  _Notifiable copy(bool blank) => _Notifiable.fromJson(blank ? {} : toJson());
}

class _Remote extends SaveRemote {
  _Remote() : super(storeName: 'effects', pbInstance: PocketBase('https://example.test'));
  Future<void> Function()? onPut;
  @override
  Future<void> checkOnline() async => isOnline = true;
  @override
  Future<bool> put(List<RowToWriteRemotely> rows) async { await onPut?.call(); return true; }
}

class _Effects extends StoreEffects {
  final enqueued = <PushData>[];
  final sent = <PushData>[];
  final errors = <Object>[];
  final operations = <String>[];
  @override
  Future<void> enqueuePushes(List<PushData> pushes) async => enqueued.addAll(pushes);
  @override
  Future<void> sendPushes(List<PushData> pushes) async => sent.addAll(pushes);
  @override
  void authenticationFailed(Object error) => errors.add(error);
  @override
  void reportError(Object error, String operation) => operations.add(operation);
}

void main() {
  late Directory directory;
  late SaveLocal local;
  late _Remote remote;
  late _Effects effects;
  late Store<_Notifiable> store;

  setUp(() async {
    directory = await setupTestHive();
    local = SaveLocal(name: 'effects', uniqueId: '', storagePath: directory.path);
    remote = _Remote();
    effects = _Effects();
    store = Store(modeling: _Notifiable.fromJson, local: local, remote: remote,
      effects: effects, manualSyncOnly: true);
    await store.loaded;
    store.init();
  });

  tearDown(() async {
    await store.deactivatePersistenceSession();
    store.observableMap.dispose();
    await local.dispose();
    await teardownTestHive(directory);
  });

  test('injected effects preserve push payload and journal-before-network order', () async {
    remote.onPut = () async {
      expect(await local.getDeferred(), contains('row'));
      expect(effects.enqueued, hasLength(1));
      expect(effects.sent, isEmpty);
    };
    store.set(_Notifiable.fromJson({'id': 'row', 'title': 'record'}));
    await store.waitUntilChangesAreProcessed();
    expect(effects.sent.single.toJson(), {
      'store': 'effects', 'id': 'row', 'readableIdentifier': 'record',
      'isCreation': true, 'isUpdate': false, 'updatedFields': <String>[],
      'oldVals': <dynamic>[], 'newVals': <dynamic>[], 'targetIDs': ['operator'],
    });
    expect(await local.getDeferred(), isEmpty);
  });

  test('network failure reports through injected effects and preserves deferred write', () async {
    remote.onPut = () async => throw StateError('offline');
    store.set(_Notifiable.fromJson({'id': 'row', 'title': 'record'}));
    await store.waitUntilChangesAreProcessed();
    expect(effects.errors, hasLength(1));
    expect(effects.operations, ['sendingUpdatesToServer']);
    expect(effects.sent, isEmpty);
    expect(await local.getDeferred(), contains('row'));
    expect(jsonDecode(await local.get('row')), containsPair('title', 'record'));
  });

  test('an injected loader cannot publish a stale batch after session invalidation', () async {
    final loading = Completer<void>();
    final gate = Completer<void>();
    await local.put({'stale': '{"id":"stale"}'});
    final isolated = Store<Model>(modeling: Model.fromJson, local: local,
      loadDocuments: (modeling, decoded) async {
        loading.complete();
        await gate.future;
        return modelStoreDocuments(DocumentBatch(modeling, decoded));
      });
    await loading.future;
    isolated.endSession();
    gate.complete();
    await isolated.loaded;
    expect(isolated.docs, isEmpty);
    isolated.observableMap.dispose();
  });

  test('push relay failure does not re-queue remote row write', () async {
    var remoteWrites = 0;
    remote.onPut = () async => remoteWrites++;
    final failingPushEffects = _FailingPushEffects();
    final pushStore = Store<_Notifiable>(
      modeling: _Notifiable.fromJson,
      local: local,
      remote: remote,
      effects: failingPushEffects,
      manualSyncOnly: true,
    );
    await pushStore.loaded;
    pushStore.init();

    pushStore.set(_Notifiable.fromJson({'id': 'row-push', 'title': 'record'}));
    await pushStore.waitUntilChangesAreProcessed();

    expect(remoteWrites, 1);
    expect(await local.getDeferred(), isEmpty,
        reason: 'Remote row write succeeded; only push stays deferred');
    expect(failingPushEffects.errors, isEmpty,
        reason: 'Push relay failure must not show row sync error dialog');
    await pushStore.deactivatePersistenceSession();
    pushStore.observableMap.dispose();
  });
}

class _FailingPushEffects extends _Effects {
  @override
  Future<void> sendPushes(List<PushData> pushes) async {
    throw StateError('relay down');
  }
}
