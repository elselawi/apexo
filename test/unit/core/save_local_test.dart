import 'dart:io';
import 'package:apexo/core/save_local.dart';
import 'package:test/test.dart';
import '../../helpers/hive_setup.dart';

void main() {
  late String testId;
  late Directory hiveDirectory;
  var testNumber = 0;
  final instances = <SaveLocal>[];

  SaveLocal newSaveLocal({required String name, required String uniqueId}) {
    final instance = SaveLocal(
      name: name,
      uniqueId: uniqueId,
      storagePath: hiveDirectory.path,
    );
    instances.add(instance);
    return instance;
  }

  setUpAll(() async {
    hiveDirectory = await setupTestHive();
  });

  setUp(() {
    testId = 'save-local-test-${testNumber++}';
  });

  tearDown(() async {
    for (final instance in instances) {
      await instance.dispose();
    }
    instances.clear();
  });

  tearDownAll(() async {
    await teardownTestHive(hiveDirectory);
  });

  group('SaveLocal', () {
    test('put and get', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.put({'key': 'value'});
      expect(await saveLocal.get('key'), 'value');
    });

    test('get returns empty string for missing key', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      expect(await saveLocal.get('nonexistent'), '');
    });

    test('getAll returns all entries', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.put({'key1': 'value1', 'key2': 'value2'});
      final all = await saveLocal.getAll();
      expect(all['key1'], 'value1');
      expect(all['key2'], 'value2');
    });

    test('getAll returns empty map for empty box', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      final all = await saveLocal.getAll();
      expect(all, isEmpty);
    });

    test('delete removes an entry', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.put({'key': 'value'});
      final box = await saveLocal.mainHiveBox;
      await box.delete('key');
      expect(await saveLocal.get('key'), '');
    });

    test('delete is idempotent — no-op on missing key', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      final box = await saveLocal.mainHiveBox;
      // Should not throw
      await box.delete('nonexistent');
      expect(await saveLocal.get('nonexistent'), '');
    });

    test('putVersion and getVersion', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.putVersion(1);
      expect(await saveLocal.getVersion(), 1);
    });

    test('getVersion defaults to 0 when not set', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      expect(await saveLocal.getVersion(), 0);
    });

    test('putVersion overwrites previous version', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.putVersion(1);
      await saveLocal.putVersion(42);
      expect(await saveLocal.getVersion(), 42);
    });

    test('putDeferred and getDeferred', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      final deferredData = {'task1': 1, 'task2': 2};
      await saveLocal.putDeferred(deferredData);
      expect(await saveLocal.getDeferred(), deferredData);
    });

    test('getDeferred returns empty map when not set', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      expect(await saveLocal.getDeferred(), isEmpty);
    });

    test('clear resets everything', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.put({'key': 'value'});
      await saveLocal.putVersion(1);
      await saveLocal.putDeferred({'task1': 1});
      await saveLocal.clear();
      expect(await saveLocal.get('key'), '');
      expect(await saveLocal.getVersion(), 0);
      expect(await saveLocal.getDeferred(), isEmpty);
    });

    test('put with empty map', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.put({});
      expect(await saveLocal.getAll(), isEmpty);
    });

    test('put overwrites existing values', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.put({'key': 'value1'});
      await saveLocal.put({'key': 'value2'});
      expect(await saveLocal.get('key'), 'value2');
    });

    test('put writes every entry in a batch without affecting other entries',
        () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      await saveLocal.put({'existing': 'kept'});
      await saveLocal.put({
        'first': 'one',
        'second': 'two',
        'third': 'three',
      });

      expect(await saveLocal.getAll(), {
        'existing': 'kept',
        'first': 'one',
        'second': 'two',
        'third': 'three',
      });
    });

    test('main and meta boxes remain isolated', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      await saveLocal.put({'meta:version': 'document value'});
      await saveLocal.putVersion(7);
      await saveLocal.putDeferred({'document': 123});

      expect(await saveLocal.get('meta:version'), 'document value');
      expect(await saveLocal.getVersion(), 7);
      expect(await saveLocal.getDeferred(), {'document': 123});
    });

    test('getAll returns a snapshot that cannot mutate persistence', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      await saveLocal.put({'key': 'stored'});

      final snapshot = await saveLocal.getAll();
      snapshot['key'] = 'changed only in memory';
      snapshot['other'] = 'also memory only';

      expect(await saveLocal.get('key'), 'stored');
      expect(await saveLocal.get('other'), '');
    });

    test('clear is idempotent after data has already been removed', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: testId);
      await saveLocal.clear();
      await saveLocal.clear();

      expect(await saveLocal.getAll(), isEmpty);
      expect(await saveLocal.getVersion(), 0);
      expect(await saveLocal.getDeferred(), isEmpty);
    });
  });

  group('SaveLocal — boxes', () {
    test('constructor creates main and meta boxes', () async {
      final saveLocal = newSaveLocal(name: 'test', uniqueId: 'boxes');
      final main = await saveLocal.mainHiveBox;
      final meta = await saveLocal.metaHiveBox;
      expect(main, isNotNull);
      expect(meta, isNotNull);
    });

    test('uniqueId isolates stores with same name', () async {
      final a = newSaveLocal(name: 'test', uniqueId: 'a');
      final b = newSaveLocal(name: 'test', uniqueId: 'b');
      await a.put({'key': 'from-a'});
      await b.put({'key': 'from-b'});
      expect(await a.get('key'), 'from-a');
      expect(await b.get('key'), 'from-b');
    });

    test('name isolates stores with the same uniqueId', () async {
      final a = newSaveLocal(name: 'first-name', uniqueId: 'same-user');
      final b = newSaveLocal(name: 'second-name', uniqueId: 'same-user');
      await a.put({'key': 'from-a'});
      await b.put({'key': 'from-b'});

      expect(await a.get('key'), 'from-a');
      expect(await b.get('key'), 'from-b');
    });

    test('independent instances reopen the same persisted boxes', () async {
      final writer = newSaveLocal(name: 'reopen', uniqueId: 'user');
      await writer.clear();
      await writer.put({'record': 'persisted'});
      await writer.putVersion(15);
      await writer.putDeferred({'record': 99});

      final reader = newSaveLocal(name: 'reopen', uniqueId: 'user');
      expect(await reader.get('record'), 'persisted');
      expect(await reader.getVersion(), 15);
      expect(await reader.getDeferred(), {'record': 99});
    });
  });

  group('StorageException', () {
    test('stores message and stackTrace', () {
      final stack = StackTrace.current;
      final ex = StorageException('test error', stack);
      expect(ex.message, 'test error');
      expect(ex.stackTrace, stack);
    });

    test('toString formats correctly', () {
      final ex = StorageException('something broke', StackTrace.current);
      expect(ex.toString(), 'StorageException: something broke');
    });
  });

  group('removeAllLocalData', () {
    test('each SaveLocal registers a clear callback', () {
      final before = removeAllLocalData.length;
      newSaveLocal(name: 'test', uniqueId: 'regtest');
      expect(removeAllLocalData.length, before + 1);
    });

    test('registered callback clears both main and metadata boxes', () async {
      final saveLocal = newSaveLocal(name: 'callback-clear', uniqueId: 'one');
      await saveLocal.put({'record': 'value'});
      await saveLocal.putVersion(9);
      await saveLocal.putDeferred({'record': 4});

      await removeAllLocalData.last();

      expect(await saveLocal.getAll(), isEmpty);
      expect(await saveLocal.getVersion(), 0);
      expect(await saveLocal.getDeferred(), isEmpty);
    });
  });
}
