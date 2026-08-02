import 'package:apexo/core/save_remote.dart';
import 'package:apexo/utils/uuid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/save_local.dart';
import 'package:pocketbase/pocketbase.dart';
import '../../test_utils.dart';

class Person extends Model {
  String name = 'alex';
  int age = 100;

  Person.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
    age = json["age"] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Person.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  get ageInDays => age * 365;
}

void main() {
  group('Store Tests', () {
    late Store<Person> store;
    final SaveLocal local = TestUtils.local;

    setUp(() async {
      await local.clear();

      store = Store<Person>(
        modeling: Person.fromJson,
        local: local,
        remote: null,
        debounceMS: 100,
      );

      store.observableMap.clear();
      await store.loaded;
      await store.local!.clear();
      await store.deleteMemoryAndLoadFromPersistence();
      // allow for Hive to process the changes
      await Future.delayed(const Duration(milliseconds: 200));
      expect(store.docs.length, equals(0));
      store.init();
    });

    test("store is loaded and modeled", () async {
      await (await local.mainHiveBox).put("id0", '{"id":"id0"}');
      final Store<Person> mStore = Store<Person>(
        modeling: Person.fromJson,
        local: local,
        remote: null,
        debounceMS: 100,
      );
      await mStore.loaded;
      expect(mStore.docs.length, 1);
      expect(mStore.docs.values.first.id, "id0");
      expect(mStore.docs.values.first.age, 100);
      expect(mStore.docs.values.first.name, "alex");
    });

    test("store add method works and calls observers", () async {
      final List<String> observedChangesIds = [];
      store.observableMap.observe((events) {
        observedChangesIds.addAll(events.map((e) => e.id));
      });

      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      expect(store.docs.values.first.id, "id1");
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observedChangesIds.contains("id1"), true);
    });

    test("store setAll method works and calls observers", () async {
      int observerCalled = 0;
      store.observableMap.observe((events) {
        if (events.first.id != "__ignore_view__") observerCalled++;
      });
      expect(store.docs.length, 0);
      store.setAll([
        Person.fromJson({"id": "id1"}),
        Person.fromJson({"id": "id2"})
      ]);
      expect(store.docs.length, 2);
      expect(store.docs.values.first.id, "id1");
      expect(store.docs.values.last.id, "id2");
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 1);
    });

    test("store delete method works and calls observers", () async {
      await store.loaded;
      int observerCalled = 0;
      store.observableMap.observe((events) {
        if (events.first.id != "__ignore_view__") observerCalled++;
      });
      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      store.delete("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, true);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 2);
    });

    test("store archive method works and calls observers", () async {
      int observerCalled = 0;
      store.observableMap.observe((events) {
        observerCalled++;
      });

      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      store.archive("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, true);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 2);
    });

    test("store unarchive method works and calls observers", () async {
      int observerCalled = 0;
      store.observableMap.observe((events) {
        observerCalled++;
      });

      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      store.archive("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, true);
      store.unarchive("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, false);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 3);
    });

    test("store get method works", () async {
      store.setAll([
        Person.fromJson({"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      expect(store.get("id1")!.name, "alex");
      expect(store.get("id2")!.name, "bob");
      expect(store.get("id3")!.name, "charlie");
      expect(store.get("id4"), null);
    });
    test("store has method works", () async {
      store.setAll([
        Person.fromJson({"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      expect(store.has("id1"), true);
      expect(store.has("id2"), true);
      expect(store.has("id3"), true);
      expect(store.has("id4"), false);
    });
    test("store present method works", () async {
      store.setAll([
        Person.fromJson({"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      expect(store.present.length, 2);
      expect(store.present.values.where((e) => e.id == "id1").length, 0);
      expect(store.present.values.where((e) => e.id == "id2").length, 1);
      expect(store.present.values.where((e) => e.id == "id3").length, 1);
    });
    test("store reload method doesn't remove items", () async {
      store.setAll([
        Person.fromJson({"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      await store.reload();
      expect(store.docs.length, 3);
    });

    test("store reload method works", () async {
      store.setAll([
        Person.fromJson({"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      await (await local.mainHiveBox).put("id4", '{"id":"id4"}');
      await store.reload();
      expect(store.docs.length, 4);
    });
    test("store reload doesn't inform observers", () async {
      await (await local.mainHiveBox).put("id4", '{"id":"id4"}');
      int observersCalled = 0;
      store.observableMap.observe((events) {
        if (events.first.id != "__ignore_view__") observersCalled++;
      });
      await store.reload();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observersCalled, 0);
    });
  });

  group('Store synchronization tests', () {
    late Store<Person> store;
    late SaveLocal local = TestUtils.local;
    late SaveRemote remote = TestUtils.remote;
    final PocketBase pb = TestUtils.pb;

    setUpAll(() async {
      await TestUtils.resetServer();
    });

    setUp(() async {
      await local.clear();
      await pb.collections.truncate("data");
      expect((await remote.getSince(version: 0)).rows, isEmpty);

      store = Store<Person>(
        modeling: Person.fromJson,
        local: local,
        remote: remote,
        debounceMS: 100,
        manualSyncOnly: true,
      );

      store.observableMap.clear();
      await store.loaded;
      await store.local!.clear();
      await store.deleteMemoryAndLoadFromPersistence();
      // allow for Hive to process the changes
      await Future.delayed(const Duration(milliseconds: 200));
      expect(store.docs.length, equals(0));
      expect(await store.local!.getVersion(), 0);
      expect((await local.getAll()), isEmpty);
      store.init();
    });

    test("deferredPresent is true when there are deferred updates", () async {
      remote.isOnline = false;
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect(store.deferredPresent, isTrue);
      remote.isOnline = true;
    });

    test("automatic: local additions to remote", () async {
      expect((await remote.getSince(version: 0)).rows.length, equals(0));
      expect((await remote.getSince(version: 0)).version, equals(0));
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(1));
      expect((await remote.getSince(version: 0)).version, greaterThan(0));

      // synchronization check
      // version is only updated through synchronization
      expect(await store.local!.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 1);
      expect(sync[1].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });
    test("automatic: local deletes to remote", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(1));
      store.delete(store.docs.values.first.id);
      await store.waitUntilChangesAreProcessed();
      var remoteRows = await remote.getSince(version: 0);
      expect(remoteRows.rows.length, equals(1));
      expect(remoteRows.rows[0].id, equals(store.docs.values.first.id));
      expect(remoteRows.rows[0].data, contains('"archived":true'));
      // synchronization check
      // version is only updated through synchronization
      expect(await local.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 1);
      expect(sync[1].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });
    test("automatic: local modifications to remote", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(1));
      store.set(store.docs.values.first..age = 18);
      await store.waitUntilChangesAreProcessed();
      var remoteRows = await remote.getSince(version: 0);
      expect(remoteRows.rows.length, equals(1));
      expect(remoteRows.rows[0].id, equals(store.docs.values.first.id));
      expect(remoteRows.rows[0].data, contains('"age":18'));

      // synchronization check
      // version is only updated through synchronization
      expect(await local.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 1);
      expect(sync[1].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });
    test("on sync: send deferred additions", () async {
      remote.isOnline = false;
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(0));
      remote.isOnline = true;

      expect(await remote.getVersion(), equals(0));

      // synchronization check
      expect(await local.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 0);
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });

    test("on sync: send deferred deletions", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.delete(store.docs.values.first.id);
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;

      expect(await remote.getVersion(), equals(remoteVersion));

      // synchronization check
      expect(await local.getVersion(), equals(localVersion));
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 0);
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, equals("nothing to sync"));
      expect(await local.getVersion(), greaterThan(localVersion));
      expect(await remote.getVersion(), equals(await local.getVersion()));
    });

    test("on sync: send deferred modifications", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.set(store.docs.values.first..age = 11);
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;

      expect(await remote.getVersion(), equals(remoteVersion));

      // synchronization check
      expect(await local.getVersion(), equals(localVersion));
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 0);
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, equals("nothing to sync"));
      expect(await local.getVersion(), greaterThan(localVersion));
      expect(await remote.getVersion(), equals(await local.getVersion()));
    });

    test("when there's deferred, all events will be deferred until sync", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.set(store.docs.values.first..age = 11);
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      store.set(Person.fromJson({}));
      store.set(Person.fromJson({}));
      store.set(Person.fromJson({}));

      await store.waitUntilChangesAreProcessed();
      expect((await local.getDeferred()).length, equals(4));
    });

    test("deferred changes must keep only the latest changes", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.set(store.docs.values.first..age = 11);
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      store.set(Person.fromJson({}));
      store.delete(store.docs.values.toList()[0].id);
      store.set(store.docs.values.toList()[1]..age = 12);

      store.set(Person.fromJson({}));
      store.set(Person.fromJson({}));

      await store.waitUntilChangesAreProcessed();
      expect((await local.getDeferred()).length, equals(4));
    });

    test("remote additions to local", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 3);
      expect(sync[1].exception, "nothing to sync");

      final docsList = store.docs.values.toList()..sort((a, b) => a.name.compareTo(b.name));

      expect(docsList.length, equals(3));
      expect(docsList[0].id, equals(id1));
      expect(docsList[0].name, equals("name1"));
      expect(docsList[0].age, equals(11));
      expect(docsList[1].id, equals(id2));
      expect(docsList[1].name, equals("name2"));
      expect(docsList[1].age, equals(12));
      expect(docsList[2].id, equals(id3));
      expect(docsList[2].name, equals("name3"));
      expect(docsList[2].age, equals(13));
    });
    test("remote deletes to local", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      await store.synchronize();

      expect(store.docs.values.toList()[0].archived, equals(null));
      expect(store.docs.values.toList()[1].archived, equals(null));

      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 11, "archived": true}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12, "archived": false}'),
      ]);

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 2);
      expect(sync[1].exception, "nothing to sync");

      expect(store.get(id1)?.archived, equals(true));
      expect(store.get(id2)?.archived, equals(false));
      expect(store.get(id3)?.archived, equals(null));
    });

    test("remote modifications to local", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      await store.synchronize();

      expect(store.get(id1)?.age, equals(11));
      expect(store.get(id2)?.age, equals(12));

      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 112}'),
      ]);

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 2);
      expect(sync[1].exception, "nothing to sync");

      expect(store.get(id1)?.age, equals(111));
      expect(store.get(id2)?.age, equals(112));
    });

    test("bi-directional", () async {
      final id0 = uuid();
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      remote.isOnline = false;
      store.set(Person.fromJson({"id": id0}));
      await Future.delayed(const Duration(seconds: 1));

      await store.waitUntilChangesAreProcessed();

      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 3);
      expect(sync[1].exception, equals(null));
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, "nothing to sync");

      expect(store.get(id0), isNotNull);
      expect(store.get(id1), isNotNull);
      expect(store.get(id2), isNotNull);
      expect(store.get(id3), isNotNull);
    });
    test("bi-directional with conflicts (local winners)", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);
      await Future.delayed(const Duration(seconds: 1));
      await store.waitUntilChangesAreProcessed();
      remote.isOnline = false;
      store.set(Person.fromJson({"id": id2, "name": "modified-name", "age": 0}));
      await store.waitUntilChangesAreProcessed();
      remote.isOnline = true;
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 2);
      expect(sync[0].conflicts, 1);
      expect(sync[1].exception, equals(null));
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, "nothing to sync");

      expect(store.get(id1)?.name, equals("name1"));
      expect(store.get(id2)?.name, equals("modified-name"));
      expect(store.get(id3)?.name, equals("name3"));
    });
    test("bi-directional with conflicts (remote winners)", () async {
      remote.isOnline = false;
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      store.set(Person.fromJson({"id": id1, "age": 11}));
      await store.waitUntilChangesAreProcessed();

      await Future.delayed(const Duration(seconds: 1));
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].conflicts, 1);
      expect(sync[0].pulled, 3);
      expect(sync[1].exception, "nothing to sync");

      expect(store.get(id1)?.age, equals(111));
      expect(store.get(id2)?.age, equals(12));
      expect(store.get(id3)?.age, equals(13));
    });
    test("bi-directional with conflicts (some local and some remote winners)", () async {
      remote.isOnline = false;
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      final id4 = uuid();
      store.set(Person.fromJson({"id": id1, "name": "local-1"}));
      await store.waitUntilChangesAreProcessed();
      await Future.delayed(const Duration(seconds: 1));
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "remote-1", "age": 111}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "remote-2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "remote-3", "age": 13}'),
      ]);

      remote.isOnline = true;
      store.set(Person.fromJson({"id": id3, "name": "local-3"}));
      store.set(Person.fromJson({"id": id4, "name": "local-4-newly-added"}));

      await store.waitUntilChangesAreProcessed();

      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, equals(2));
      expect(sync[0].pulled, equals(2));
      expect(sync[0].conflicts, equals(2));
      expect(sync[1].exception, equals(null));
      expect(sync[1].pushed, equals(0));
      expect(sync[1].pulled, equals(2));
      expect(sync[1].conflicts, equals(0));
      expect(sync[2].exception, equals("nothing to sync"));

      expect(store.get(id1)?.name, equals("remote-1"));
      expect(store.get(id2)?.name, equals("remote-2"));
      expect(store.get(id3)?.name, equals("local-3"));
      expect(store.get(id4)?.name, equals("local-4-newly-added"));
    });

    test("inSync methods correctly tells whether the store is in sync", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);
      await Future.delayed(const Duration(seconds: 1));
      expect(await store.inSync(), equals(false));
      await store.synchronize();
      expect(await store.inSync(), equals(true));
      store.set(Person.fromJson({"id": id1, "name": "modified-name", "age": 0}));
      await store.waitUntilChangesAreProcessed();
      expect(await store.inSync(), equals(false));
      await store.synchronize();
      expect(await store.inSync(), equals(true));
    });

    test("onSyncStart/onSyncEnd functions are called", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      int startCount = 0;
      int endCount = 0;

      store = Store(
        remote: remote,
        local: local,
        modeling: Person.fromJson,
        manualSyncOnly: true,
        onSyncStart: () {
          startCount++;
        },
        onSyncEnd: () {
          endCount++;
        },
      );
      store.init();
      await store.loaded;

      store.set(Person.fromJson({"id": id1, "name": "modified-name", "age": 0}));
      await store.waitUntilChangesAreProcessed();
      await remote.put([
        RowToWriteRemotely(id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);
      await store.synchronize();

      await store.waitUntilChangesAreProcessed();

      expect(startCount, equals(2));
      expect(endCount, equals(2));
    });

    test("Non-manual sync, on modification", () async {
      final store2 = Store(
        remote: remote,
        local: local,
        modeling: Person.fromJson,
        debounceMS: 100,
      );
      store2.init();
      await store2.loaded;

      final id = uuid();

      store2.set(Person.fromJson({"id": id}));
      expect(store2.docs.length, equals(1));
      await store2.waitUntilChangesAreProcessed();
      final remoteRes = (await remote.getSince(version: 0)).rows;
      expect(remoteRes.length, equals(1));
      expect(remoteRes.first.id, equals(id));
    });

    test("Realtime subscription", () async {
      final store2 = Store(
        remote: remote,
        local: local,
        modeling: Person.fromJson,
        debounceMS: 100,
      );
      store2.init();
      await store2.loaded;
      await store2.synchronize(); // setting up realtime requires a sync request

      final id = uuid();
      await remote.put([RowToWriteRemotely(id: id, data: '{"id": "$id"}')]);

      await Future.delayed(const Duration(milliseconds: 6000));

      expect(store2.docs.length, equals(1));
      expect(store2.docs.values.first.id, equals(id));
    });
  });
}
