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
  _GatedLocal(String path) : super(name: 'lifecycle', uniqueId: '', storagePath: path);
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
  _GatedRemote() : super(storeName: 'lifecycle', pbInstance: PocketBase('https://example.test'));
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

  test('a later edit survives an earlier write and writes are serialized', () async {
    local.writeGate = Completer<void>();
    store.set(Model.fromJson({'id': 'record', 'title': 'first'}));
    await local.writeStarted.future;
    store.set(Model.fromJson({'id': 'record', 'title': 'second'}));
    await Future<void>.delayed(Duration.zero);
    expect(local.writes, hasLength(1));
    local.writeGate!.complete();
    await store.waitUntilChangesAreProcessed();
    expect(local.writes, hasLength(2));
    expect(jsonDecode(await local.get('record')), containsPair('title', 'second'));
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
    expect(jsonDecode(await local.get('record')), containsPair('title', 'unsaved'));
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

  test('deactivation waits for in-flight sync and prevents subsequent pulls', () async {
    final remote = _GatedRemote()..versionGate = Completer<void>();
    store.remote = remote;
    final syncing = store.synchronize();
    await remote.versionStarted.future;
    var stopped = false;
    final stopping = store.deactivatePersistenceSession().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    remote.versionGate!.complete();
    await stopping;
    await syncing;
    expect(remote.pulls, 0);
    expect(starts, ends);
  });

  test('remote writes are journaled before I/O and survive session invalidation', () async {
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

  test('missing attachment persistence balances progress on exceptions', () async {
    store.remote = null;
    await expectLater(store.uploadImg(rowID: 'row', filename: 'scan.dcm'), throwsException);
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
    expect(deferred.keys, containsAll([
      'FILE||one||one.dcm||one.dcm||0',
      'FILE||two||two.dcm||two.dcm||0',
    ]));
    expect(starts, ends);
  });

  test('empty bulk updates do not break the persistence observer', () async {
    store.setAll([]);
    store.set(Model.fromJson({'id': 'record', 'title': 'saved'}));
    await store.waitUntilChangesAreProcessed();
    expect(await local.get('record'), contains('saved'));
  });
}
