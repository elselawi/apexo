@Tags(['serial'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/core/model.dart';
import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../helpers/hive_setup.dart';

class _GatedLocal extends SaveLocal {
  _GatedLocal(String path)
      : super(name: 'lifecycle', uniqueId: '', storagePath: path);
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  final writes = <Map<String, String>>[];
  bool failWrites = false;

  @override
  Future<void> put(Map<String, String> entries) async {
    writes.add(Map.of(entries));
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate != null) await writeGate!.future;
    if (failWrites) throw StateError('disk unavailable');
    await super.put(entries);
  }
}

class _GatedRemote extends SaveRemote {
  _GatedRemote()
      : super(
            storeName: 'lifecycle',
            pbInstance: PocketBase('https://example.test'));
  Completer<void>? versionGate;
  final versionStarted = Completer<void>();
  int reads = 0;
  int pulls = 0;
  Completer<void>? putGate;
  final putStarted = Completer<void>();

  @override
  Future<bool> put(List<RowToWriteRemotely> data) async {
    if (!putStarted.isCompleted) putStarted.complete();
    if (putGate != null) await putGate!.future;
    return true;
  }

  @override
  Future<void> checkOnline() async => isOnline = true;

  @override
  Future<int> getVersion() async {
    reads++;
    if (!versionStarted.isCompleted) versionStarted.complete();
    if (versionGate != null) await versionGate!.future;
    return 0;
  }

  @override
  Future<VersionedResult> getSince({int version = 0}) async {
    pulls++;
    return VersionedResult(0, []);
  }
}

class _PullRemote extends _GatedRemote {
  final pullStarted = Completer<void>();
  final releasePull = Completer<void>();

  @override
  Future<int> getVersion() async => 1;

  @override
  Future<VersionedResult> getSince({int version = 0}) async {
    if (!pullStarted.isCompleted) pullStarted.complete();
    await releasePull.future;
    return VersionedResult(1, [
      Row(
          id: 'remote-record',
          data: '{"id":"remote-record","title":"remote new"}',
          ts: 1),
      Row(
          id: 'edited-record',
          data: '{"id":"edited-record","title":"remote edit"}',
          ts: 1),
    ]);
  }
}

void main() {
  late Directory directory;
  late _GatedLocal local;
  late Store<Model> store;
  var starts = 0;
  var ends = 0;

  setUp(() async {
    directory = await setupTestHive();
    local = _GatedLocal(directory.path);
    starts = 0;
    ends = 0;
    store = Store<Model>(
      modeling: Model.fromJson,
      local: local,
      manualSyncOnly: true,
      debounceMS: 1,
      onSyncStart: () => starts++,
      onSyncEnd: () => ends++,
    );
    await store.loaded;
    store.init();
  });

  tearDown(() async {
    await store.deactivatePersistenceSession();
    store.observableMap.dispose();
    await local.dispose();
    await teardownTestHive(directory);
  });

  test('a later edit survives an earlier write and writes are serialized',
      () async {
    local.writeGate = Completer<void>();
    store.set(Model.fromJson({'id': 'record', 'title': 'first'}));
    await local.writeStarted.future;
    store.set(Model.fromJson({'id': 'record', 'title': 'second'}));
    await Future<void>.delayed(Duration.zero);
    expect(local.writes, hasLength(1));
    local.writeGate!.complete();
    await store.waitUntilChangesAreProcessed();
    expect(local.writes, hasLength(2));
    expect(
        jsonDecode(await local.get('record')), containsPair('title', 'second'));
    expect(store.get('record')!.title, 'second');
    expect(starts, ends);
  });

  test('failed local writes retain edits and balance progress', () async {
    local.failWrites = true;
    store.set(Model.fromJson({'id': 'record', 'title': 'unsaved'}));
    await expectLater(store.waitUntilChangesAreProcessed(), throwsStateError);
    expect(store.changes, isNotEmpty);
    expect(starts, ends);
    local.failWrites = false;
    store.set(store.get('record')!);
    await store.waitUntilChangesAreProcessed();
    expect(jsonDecode(await local.get('record')),
        containsPair('title', 'unsaved'));
  });

  test('concurrent sync callers await the same operation', () async {
    final remote = _GatedRemote()..versionGate = Completer<void>();
    store.remote = remote;
    final first = store.synchronize();
    final second = store.synchronize();
    expect(identical(first, second), isTrue);
    await remote.versionStarted.future;
    expect(remote.reads, 1);
    remote.versionGate!.complete();
    expect(await first, same(await second));
    expect(starts, ends);
  });

  test('deactivation waits for in-flight sync and prevents subsequent pulls',
      () async {
    final remote = _GatedRemote()..versionGate = Completer<void>();
    store.remote = remote;
    final syncing = store.synchronize();
    await remote.versionStarted.future;
    var stopped = false;
    final stopping =
        store.deactivatePersistenceSession().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    remote.versionGate!.complete();
    await stopping;
    await syncing;
    expect(remote.pulls, 0);
    expect(starts, ends);
  });

  test(
      'remote writes are journaled before I/O and survive session invalidation',
      () async {
    final remote = _GatedRemote()..putGate = Completer<void>();
    store.remote = remote;
    store.set(Model.fromJson({'id': 'record', 'title': 'saved locally'}));
    await remote.putStarted.future;
    expect(await local.getDeferred(), contains('record'));
    store.endSession();
    remote.putGate!.complete();
    await store.deactivatePersistenceSession();
    expect(await local.getDeferred(), contains('record'));
    expect(starts, ends);
  });

  test('missing attachment persistence balances progress on exceptions',
      () async {
    store.remote = null;
    await expectLater(
        store.uploadImg(rowID: 'row', filename: 'scan.dcm'), throwsException);
    await expectLater(store.deleteImg('row', 'scan.dcm'), throwsException);
    expect(starts, 2);
    expect(ends, 2);
  });

  test('concurrent offline attachment queues preserve both entries', () async {
    final remote = _GatedRemote();
    store.remote = remote;
    await Future<void>.delayed(Duration.zero);
    remote.isOnline = false;
    await Future.wait([
      store.uploadImg(rowID: 'one', filename: 'one.dcm', path: 'one.dcm'),
      store.uploadImg(rowID: 'two', filename: 'two.dcm', path: 'two.dcm'),
    ]);
    final deferred = await local.getDeferred();
    expect(
        deferred.keys,
        containsAll([
          'FILE||one||one.dcm||one.dcm||0',
          'FILE||two||two.dcm||two.dcm||0',
        ]));
    expect(starts, ends);
  });

  test('logout preserves the latest queued edit in the old local journal',
      () async {
    final remote = _GatedRemote();
    store.remote = remote;
    local.writeGate = Completer<void>();
    store.set(Model.fromJson({'id': 'record', 'title': 'first'}));
    await local.writeStarted.future;
    store.set(Model.fromJson({'id': 'record', 'title': 'second'}));
    store.endSession();
    local.writeGate!.complete();
    await store.waitUntilChangesAreProcessed();
    expect(
        jsonDecode(await local.get('record')), containsPair('title', 'second'));
    expect(await local.getDeferred(), contains('record'));
  });

  test('session saves use a snapshot rather than replacement models', () async {
    store.remote = _GatedRemote();
    local.writeGate = Completer<void>();
    store.set(Model.fromJson({'id': 'record', 'title': 'first'}));
    await local.writeStarted.future;
    store.set(Model.fromJson({'id': 'record', 'title': 'old clinic latest'}));
    store.endSession();
    store.observableMap.silently(() {
      store.observableMap.clear();
      store.observableMap.set(Model.fromJson({'id': 'record', 'title': 'new clinic'}));
    });
    local.writeGate!.complete();
    await store.waitUntilChangesAreProcessed();
    expect(jsonDecode(await local.get('record')), containsPair('title', 'old clinic latest'));
    expect(store.get('record')!.title, 'new clinic');
    expect(await local.getDeferred(), contains('record'));
  });

  test('immediate logout captures edits before asynchronous notification',
      () async {
    store.set(Model.fromJson({'id': 'record', 'title': 'saved'}));
    store.endSession();
    await store.waitUntilChangesAreProcessed();
    expect(
        jsonDecode(await local.get('record')), containsPair('title', 'saved'));
  });

  test('session replacement drains saves into the old local adapter', () async {
    local.writeGate = Completer<void>();
    store.set(Model.fromJson({'id': 'record', 'title': 'first'}));
    await local.writeStarted.future;
    store.set(Model.fromJson({'id': 'record', 'title': 'second'}));
    final stopping = store.deactivatePersistenceSession();
    local.writeGate!.complete();
    await stopping;
    expect(
        jsonDecode(await local.get('record')), containsPair('title', 'second'));
  });

  test('remote changes become visible without overwriting concurrent edits',
      () async {
    store.setAll([
      Model.fromJson({'id': 'remote-record', 'title': 'old'}),
      Model.fromJson({'id': 'edited-record', 'title': 'old'}),
    ]);
    await store.waitUntilChangesAreProcessed();
    final remote = _PullRemote();
    store.remote = remote;
    final syncing = store.synchronize();
    await remote.pullStarted.future;
    store.set(Model.fromJson({'id': 'edited-record', 'title': 'local new'}));
    remote.releasePull.complete();
    await syncing;
    await store.waitUntilChangesAreProcessed();
    expect(store.get('remote-record')!.title, 'remote new');
    expect(store.get('edited-record')!.title, 'local new');
    expect(jsonDecode(await local.get('edited-record')),
        containsPair('title', 'local new'));
    await store.synchronize();
    expect(store.get('remote-record')!.title, 'remote new');
  });

  test('bulk archive and restore keep the archive index consistent', () async {
    store.setAll([
      Model.fromJson({'id': 'record', 'archived': true})
    ]);
    expect(store.archived.keys, {'record'});
    await store.waitUntilChangesAreProcessed();
    store.setAll([
      Model.fromJson({'id': 'record', 'title': 'restored'})
    ]);
    expect(store.archived, isEmpty);
    await store.waitUntilChangesAreProcessed();
    expect(store.present.keys, {'record'});
  });

  test('silent pulls and view notifications do not become local writes', () async {
    store.observableMap.silently(() {
      store.observableMap.setAllWithJson(
        {'record': Model.fromJson({'id': 'record', 'archived': true})},
        {'record': {'id': 'record', 'archived': true}},
      );
    });
    store.notify();
    await store.waitUntilChangesAreProcessed();
    expect(store.changes, isEmpty);
    expect(local.writes, isEmpty);
  });

  test('bulk updates refresh archive membership before view observers', () async {
    bool? archiveVisible;
    final subscription = store.observableMap.stream.listen((_) {
      archiveVisible = store.archived.containsKey('record');
    });
    store.setAll([Model.fromJson({'id': 'record', 'archived': true})]);
    await store.waitUntilChangesAreProcessed();
    expect(archiveVisible, true);
    store.setAll([Model.fromJson({'id': 'record'})]);
    await store.waitUntilChangesAreProcessed();
    expect(archiveVisible, false);
    await subscription.cancel();
  });

  test('empty bulk updates do not break the persistence observer', () async {
    store.setAll([]);
    store.set(Model.fromJson({'id': 'record', 'title': 'saved'}));
    await store.waitUntilChangesAreProcessed();
    expect(await local.get('record'), contains('saved'));
  });
}
