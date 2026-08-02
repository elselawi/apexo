import 'package:apexo/core/model.dart';
import 'package:apexo/core/observable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("observable", () {
    group('ObservableBase', () {
      test('should notify observers', () async {
        final observable = ObservableBase();
        bool notified = false;

        observable.observe((events) {
          notified = true;
        });

        observable.notifyObservers([OEvent.add('test')]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, true);
      });

      test('should notify multiple observers', () async {
        final observable = ObservableBase();
        bool notified1 = false;
        bool notified2 = false;

        observable.observe((events) {
          notified1 = true;
        });

        observable.observe((events) {
          notified2 = true;
        });

        observable.notifyObservers([OEvent.add('test')]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified1, true);
        expect(notified2, true);
      });

      test('should remove observers', () async {
        final observable = ObservableBase();
        bool notified = false;

        observer(List<OEvent> events) {
          notified = true;
        }

        observable.observe(observer);
        observable.unObserve(observer);

        observable.notifyObservers([OEvent.add('test')]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, false);
      });

      test('should not notify observers when silent', () async {
        final observable = ObservableBase();
        bool notified = false;

        observable.observe((events) {
          notified = true;
        });

        observable.silently(() {
          observable.notifyObservers([OEvent.add('test')]);
        });

        await Future.delayed(const Duration(milliseconds: 10));

        expect(notified, false);
      });

      test('should resume notifications after silent', () async {
        final observable = ObservableBase();
        bool notified = false;

        observable.observe((events) {
          notified = true;
        });

        observable.silently(() {
          observable.notifyObservers([OEvent.add('test')]);
        });

        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, false);

        observable.notifyObservers([OEvent.add('test')]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, true);
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
        final state = ObservableState<int>(0);
        expect(state(), 0);
      });

      test('should notify observers on state change', () async {
        final state = ObservableState<int>(0);
        bool notified = false;

        state.observe((events) {
          notified = true;
        });

        state(1);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, true);
        expect(state(), 1);
      });

      test('should not notify observers when silent', () async {
        final state = ObservableState<int>(0);
        bool notified = false;

        state.observe((events) {
          notified = true;
        });

        state.silently(() {
          state(1);
        });

        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, false);
        expect(state(), 1);
      });

      test('should resume notifications after silent', () async {
        final state = ObservableState<int>(0);
        bool notified = false;

        state.observe((events) {
          notified = true;
        });

        state.silently(() {
          state(1);
        });

        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, false);

        state(2);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, true);
        expect(state(), 2);
      });

      test('should notify multiple observers on state change', () async {
        final state = ObservableState<int>(0);
        bool notified1 = false;
        bool notified2 = false;

        state.observe((events) {
          notified1 = true;
        });

        state.observe((events) {
          notified2 = true;
        });

        state(1);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified1, true);
        expect(notified2, true);
        expect(state(), 1);
      });
    });

    group('ObservableObject', () {
      test('should notify observers on notify call', () async {
        final observable = ObservableObject();
        bool notified = false;

        observable.observe((events) {
          notified = true;
        });

        observable.notify();
        await Future.delayed(const Duration(milliseconds: 10));
        expect(notified, true);
      });
    });

    group('ObservableDict', () {
      test('should add and retrieve item', () {
        final dict = ObservableDict<MyClass>();
        final model = MyClass.fromJson({"id": "1"});

        dict.set(model);
        expect(dict.get('1'), model);
      });

      test('should remove item', () {
        final dict = ObservableDict<MyClass>();
        final model = MyClass.fromJson({"id": "1"});

        dict.set(model);
        dict.remove('1');
        expect(dict.get('1'), null);
      });

      test('should clear all items', () {
        final dict = ObservableDict<MyClass>();
        final model1 = MyClass.fromJson({"id": "1"});
        final model2 = MyClass.fromJson({"id": "2"});

        dict.set(model1);
        dict.set(model2);
        dict.clear();
        expect(dict.values.isEmpty, true);
      });

      test('should return null for non-existent item', () {
        final dict = ObservableDict<MyClass>();
        expect(dict.get('non-existent-id'), isNull);
      });

      test('should update item', () {
        final dict = ObservableDict<MyClass>();
        final model = MyClass.fromJson({"id": "1"});
        final updatedModel = MyClass.fromJson({"id": "1", "name": "Updated"});

        dict.set(model);
        dict.set(updatedModel);
        expect(dict.get('1'), updatedModel);
      });
    });
  });
}

class MyClass extends Model {
  String name = '';
  int age = 0;

  MyClass.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
    age = json["age"] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = MyClass.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  get ageInDays => age * 365;
}
