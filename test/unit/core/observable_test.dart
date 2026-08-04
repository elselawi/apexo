import 'package:apexo/core/model.dart';
import 'package:apexo/core/observable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/adapters.dart';
import 'dart:io';
import '../../helpers/hive_setup.dart';

void main() {
  Future<void> flushNotifications() => Future<void>.delayed(Duration.zero);

  group('ObservableBase', () {
    test('should notify observers', () async {
      final observable = ObservableBase<String>();
      bool notified = false;

      observable.observe((event) {
        notified = true;
      });

      observable.notifyObservers('test');
      await flushNotifications();
      expect(notified, true);
    });

    test('should notify multiple observers', () async {
      final observable = ObservableBase<String>();
      bool notified1 = false;
      bool notified2 = false;

      observable.observe((event) {
        notified1 = true;
      });
      observable.observe((event) {
        notified2 = true;
      });

      observable.notifyObservers('test');
      await flushNotifications();
      expect(notified1, true);
      expect(notified2, true);
    });

    test('should remove observers', () async {
      final observable = ObservableBase<String>();
      bool notified = false;

      void observer(String event) {
        notified = true;
      }

      observable.observe(observer);
      observable.unObserve(observer);

      observable.notifyObservers('test');
      await flushNotifications();
      expect(notified, false);
    });

    test('should not notify observers when silent', () async {
      final observable = ObservableBase<String>();
      bool notified = false;

      observable.observe((event) {
        notified = true;
      });

      observable.silently(() {
        observable.notifyObservers('test');
      });

      await flushNotifications();
      expect(notified, false);
    });

    test('should resume notifications after silent', () async {
      final observable = ObservableBase<String>();
      bool notified = false;

      observable.observe((event) {
        notified = true;
      });

      observable.silently(() {
        observable.notifyObservers('test');
      });

      await flushNotifications();
      expect(notified, false);

      observable.notifyObservers('test');
      await flushNotifications();
      expect(notified, true);
    });

    test('supports nested silently calls', () async {
      final observable = ObservableBase<String>();
      bool notified = false;

      observable.observe((event) {
        notified = true;
      });

      observable.silently(() {
        observable.silently(() {
          observable.notifyObservers('test');
        });
      });

      await flushNotifications();
      expect(notified, false);
    });

    test('observer that throws does not block other observers', () async {
      final observable = ObservableBase<String>();
      bool secondCalled = false;

      observable.observe((event) {
        throw Exception('observer error');
      });
      observable.observe((event) {
        secondCalled = true;
      });

      observable.notifyObservers('test');
      await flushNotifications();
      expect(secondCalled, true);
    });

    test('duplicate observer returns same index', () {
      final observable = ObservableBase<String>();
      void cb(String e) {}
      final i1 = observable.observe(cb);
      final i2 = observable.observe(cb);
      expect(i1, i2);
    });

    test('dispose prevents further notifications', () async {
      final observable = ObservableBase<String>();
      bool notified = false;
      observable.observe((e) => notified = true);
      observable.dispose();

      observable.notifyObservers('test');
      await flushNotifications();
      expect(notified, false);
    });

    test('dispose called twice does not throw', () {
      final observable = ObservableBase<String>();
      observable.dispose();
      expect(() => observable.dispose(), returnsNormally);
    });

    test('silently decrements _silent even when fn throws', () async {
      final observable = ObservableBase<String>();
      bool notifiedAfter = false;
      observable.observe((e) => notifiedAfter = true);

      // silently catches exceptions (does NOT rethrow)
      expect(
        () => observable.silently(() {
          throw Exception('intentional');
        }),
        returnsNormally, // exception is caught inside silently
      );

      // After silently catches the error, _silent should be decremented.
      observable.notifyObservers('after');
      await flushNotifications();
      expect(notifiedAfter, true);
    });
  });

  group('ObservableState', () {
    test('should get and set value', () {
      final state = ObservableState<int>(0);
      expect(state(), 0);
      state(1);
      expect(state(), 1);
    });

    test('should have correct initial state', () {
      final state = ObservableState<String>('hello');
      expect(state(), 'hello');
    });

    test('should notify observers on state change', () async {
      final state = ObservableState<int>(0);
      bool notified = false;

      state.observe((event) {
        notified = true;
      });

      state(1);
      await flushNotifications();
      expect(notified, true);
      expect(state(), 1);
    });

    test('should not notify when silent', () async {
      final state = ObservableState<int>(0);
      bool notified = false;

      state.observe((event) {
        notified = true;
      });

      state.silently(() {
        state(1);
      });

      await flushNotifications();
      expect(notified, false);
      expect(state(), 1);
    });

    test('should resume notifications after silent', () async {
      final state = ObservableState<int>(0);
      bool notified = false;

      state.observe((event) {
        notified = true;
      });

      state.silently(() {
        state(1);
      });

      await flushNotifications();
      expect(notified, false);

      state(2);
      await flushNotifications();
      expect(notified, true);
      expect(state(), 2);
    });

    test('should notify multiple observers', () async {
      final state = ObservableState<int>(0);
      bool n1 = false, n2 = false;

      state.observe((e) => n1 = true);
      state.observe((e) => n2 = true);

      state(1);
      await flushNotifications();
      expect(n1, true);
      expect(n2, true);
    });

    test('passing null does not notify', () async {
      final state = ObservableState<String?>('initial');
      bool notified = false;

      state.observe((e) => notified = true);
      state(null);
      await flushNotifications();
      expect(notified, false);
      expect(state(), 'initial');
    });
  });

  group('ObservableDict', () {
    test('should add and retrieve item', () {
      final dict = ObservableDict<MyClass>();
      final model = MyClass.fromJson({'id': '1'});
      dict.set(model);
      expect(dict.get('1'), model);
    });

    test('should remove item', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));
      dict.remove('1');
      expect(dict.get('1'), null);
    });

    test('should clear all items', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));
      dict.set(MyClass.fromJson({'id': '2'}));
      dict.clear();
      expect(dict.values.isEmpty, true);
    });

    test('should return null for non-existent item', () {
      final dict = ObservableDict<MyClass>();
      expect(dict.get('nonexistent'), isNull);
    });

    test('should update existing item', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1', 'name': 'old'}));
      dict.set(MyClass.fromJson({'id': '1', 'name': 'new'}));
      expect(dict.get('1')!.name, 'new');
    });

    test('set notifies DictEvent.add for new item', () async {
      final dict = ObservableDict<MyClass>();
      List<DictEvent>? received;

      dict.observe((events) {
        received = events;
      });

      dict.set(MyClass.fromJson({'id': '1'}));
      await flushNotifications();

      expect(received, isNotNull);
      expect(received!.first.type, DictEventType.add);
      expect(received!.first.id, '1');
    });

    test('set notifies DictEvent.modify for existing item', () async {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1', 'name': 'old'}));

      List<DictEvent>? received;
      dict.observe((e) => received = e);

      dict.set(MyClass.fromJson({'id': '1', 'name': 'new'}));
      await flushNotifications();

      expect(received!.first.type, DictEventType.modify);
    });

    test('remove notifies DictEvent.remove', () async {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));

      List<DictEvent>? received;
      dict.observe((e) => received = e);

      dict.remove('1');
      await flushNotifications();

      expect(received!.first.type, DictEventType.remove);
      expect(received!.first.id, '1');
    });

    test('setAll adds multiple items', () {
      final dict = ObservableDict<MyClass>();
      dict.setAll([
        MyClass.fromJson({'id': '1'}),
        MyClass.fromJson({'id': '2'}),
        MyClass.fromJson({'id': '3'}),
      ]);
      expect(dict.values.length, 3);
      expect(dict.get('1'), isNotNull);
      expect(dict.get('2'), isNotNull);
      expect(dict.get('3'), isNotNull);
    });

    test('notifyView emits __ignore_view__ event', () async {
      final dict = ObservableDict<MyClass>();
      List<DictEvent>? received;
      dict.observe((e) => received = e);

      dict.notifyView();
      await flushNotifications();

      expect(received!.first.id, '__ignore_view__');
      expect(received!.first.type, DictEventType.modify);
    });

    test('remove is a no-op for non-existent ID', () {
      final dict = ObservableDict<MyClass>();
      // Should not throw
      expect(() => dict.remove('nonexistent'), returnsNormally);
    });

    test('DictEvent.remove has null document', () async {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));
      List<DictEvent>? received;
      dict.observe((e) => received = e);

      dict.remove('1');
      await flushNotifications();

      expect(received!.first.type, DictEventType.remove);
      expect(received!.first.document, isNull);
    });

    test('keys returns list copy of all keys', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': 'a'}));
      dict.set(MyClass.fromJson({'id': 'b'}));

      final keys = dict.keys;
      expect(keys, containsAll(['a', 'b']));
      expect(keys.length, 2);
    });

    test('docs returns unmodifiable map', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));

      final docs = dict.docs;
      expect(docs, contains('1'));
      // Should be unmodifiable
      expect(() => (docs as dynamic)['new'] = MyClass.fromJson({'id': 'x'}),
          throwsA(anything));
    });

    test('setAllWithJson populates docs without re-serializing each item', () {
      final dict = ObservableDict<MyClass>();
      final items = {
        'a': MyClass.fromJson({'id': 'a', 'name': 'alpha'}),
        'b': MyClass.fromJson({'id': 'b', 'name': 'beta'}),
      };
      final jsonMaps = {
        'a': {'id': 'a', 'name': 'alpha'},
        'b': {'id': 'b', 'name': 'beta'},
      };
      dict.setAllWithJson(items, jsonMaps);
      expect(dict.values.length, 2);
      expect(dict.get('a')?.name, 'alpha');
      expect(dict.get('b')?.name, 'beta');
    });

    test('set on item without targetsToPushTo still emits add', () async {
      final dict = ObservableDict<MyClass>();
      List<DictEvent>? received;
      dict.observe((e) => received = e);

      // MyClass has empty targetsToPushTo by default → falls into the
      // else branch (modify event with empty modifiedKeys).
      dict.set(MyClass.fromJson({'id': 'no-push-targets'}));
      await flushNotifications();

      expect(received, isNotNull);
      expect(received!.first.type, DictEventType.add);
      expect(received!.first.id, 'no-push-targets');
    });

    test('modify on item without targetsToPushTo emits empty modifiedKeys',
        () async {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1', 'name': 'old'}));
      List<DictEvent>? received;
      dict.observe((e) => received = e);

      // MyClass has empty targetsToPushTo → diffJson is NOT invoked.
      dict.set(MyClass.fromJson({'id': '1', 'name': 'new'}));
      await flushNotifications();

      expect(received!.first.type, DictEventType.modify);
      expect(received!.first.modifiedKeys, isEmpty);
    });

    test('clear emits a __removed_all__ remove event', () async {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));
      List<DictEvent>? received;
      dict.observe((e) => received = e);

      dict.clear();
      await flushNotifications();
      expect(received!.first.type, DictEventType.remove);
      expect(received!.first.id, '__removed_all__');
      expect(dict.values, isEmpty);
    });

    test('values returns a new list each call (not a live reference)', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));
      final a = dict.values;
      final b = dict.values;
      expect(identical(a, b), isFalse);
      expect(a.length, b.length);
    });

    test('keys returns a new list each call', () {
      final dict = ObservableDict<MyClass>();
      dict.set(MyClass.fromJson({'id': '1'}));
      final a = dict.keys;
      final b = dict.keys;
      expect(identical(a, b), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // diffJson — top-level helper used by ObservableDict and Store.mergeConflict
  // ---------------------------------------------------------------------------
  group('diffJson', () {
    test('empty on both sides → empty set', () {
      expect(diffJson({}, {}), isEmpty);
    });

    test('added keys', () {
      final diff = diffJson({}, {'a': 1, 'b': 2});
      expect(diff, {'a', 'b'});
    });

    test('removed keys', () {
      final diff = diffJson({'a': 1, 'b': 2}, {});
      expect(diff, {'a', 'b'});
    });

    test('modified scalar values', () {
      final diff = diffJson({'a': 1}, {'a': 2});
      expect(diff, {'a'});
    });

    test('unchanged scalar values → not in diff', () {
      final diff = diffJson({'a': 1, 'b': 2}, {'a': 1, 'b': 2});
      expect(diff, isEmpty);
    });

    test('list value changes detected', () {
      final diff = diffJson({
        'l': [1, 2]
      }, {
        'l': [1, 2, 3]
      });
      expect(diff, {'l'});
    });

    test('list value unchanged (deep equal) → not in diff', () {
      final diff = diffJson({
        'l': [1, 2]
      }, {
        'l': [1, 2]
      });
      expect(diff, isEmpty);
    });

    test('map value changes detected (deep equal)', () {
      final diff = diffJson({
        'm': {'x': 1}
      }, {
        'm': {'x': 2}
      });
      expect(diff, {'m'});
    });

    test('nested map unchanged (deep equal) → not in diff', () {
      final diff = diffJson({
        'm': {'x': 1}
      }, {
        'm': {'x': 1}
      });
      expect(diff, isEmpty);
    });

    test('mixed add/modify/remove', () {
      final diff = diffJson(
        {'a': 1, 'b': 2, 'c': 3},
        {'a': 1, 'b': 99, 'd': 4},
      );
      expect(diff, {'b', 'c', 'd'});
    });
  });

  // ---------------------------------------------------------------------------
  // ObservablePersistingObject — persists to a Hive box and notifies observers
  // ---------------------------------------------------------------------------
  group('ObservablePersistingObject', () {
    late Directory hiveDirectory;

    setUpAll(() async {
      hiveDirectory = await setupTestHive();
    });

    setUp(() async {
      final box = await Hive.openBox<String>('persist-test-obj',
          path: hiveDirectory.path);
      await box.clear();
    });

    tearDown(() async {
      final box = await Hive.openBox<String>('persist-test-obj',
          path: hiveDirectory.path);
      await box.deleteFromDisk();
    });

    tearDownAll(() async {
      await teardownTestHive(hiveDirectory);
    });

    test('persists changes to Hive and notifies observers', () async {
      final obj = _PersistingTestObj('persist-test-obj', hiveDirectory.path);
      await obj.ready;

      bool notified = false;
      obj.observe((_) => notified = true);

      obj.value = 'hello';
      obj.notifyAndPersist();
      await flushNotifications();

      expect(notified, isTrue);
      // The Hive box should now contain the serialised value.
      final box = await Hive.openBox<String>('persist-test-obj',
          path: hiveDirectory.path);
      final stored = box.get('persist-test-obj');
      expect(stored, isNotNull);
      expect(stored, contains('hello'));
    });

    test('reloads persisted value on construction', () async {
      // Pre-populate the box.
      final box = await Hive.openBox<String>('persist-test-obj',
          path: hiveDirectory.path);
      await box.put('persist-test-obj', '{"value":"reloaded"}');

      final obj = _PersistingTestObj('persist-test-obj', hiveDirectory.path);
      await obj.ready;
      expect(obj.value, 'reloaded');
    });

    test('notifyAndPersist is shorthand for notifyObservers(this)', () async {
      final obj = _PersistingTestObj('persist-test-obj', hiveDirectory.path);
      await obj.ready;

      int calls = 0;
      obj.observe((_) => calls++);
      obj.value = 'one';
      obj.notifyAndPersist();
      await flushNotifications();
      expect(calls, 1);
    });
  });
}

class _PersistingTestObj extends ObservablePersistingObject {
  String value = '';

  _PersistingTestObj(super.id, String storagePath)
      : super(storagePath: storagePath);

  @override
  void fromJson(Map<String, dynamic> json) {
    value = json['value'] ?? '';
  }

  @override
  Map<String, dynamic> toJson() => {'value': value};
}

class MyClass extends Model {
  String name = '';
  int age = 0;

  MyClass.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json['name'] ?? name;
    age = json['age'] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = MyClass.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  int get ageInDays => age * 365;
}
