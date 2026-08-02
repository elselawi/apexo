import "package:apexo/core/save_local.dart";
import "package:test/test.dart";

void main() {
  group("SaveLocal", () {
    test("put and get", () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      await saveLocal.put({"key": "value"});
      expect(await saveLocal.get("key"), "value");
    });

    test("getAll", () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      await saveLocal.put({"key1": "value1", "key2": "value2"});
      final values = await saveLocal.getAll();
      expect(values, containsAll(["value1", "value2"]));
    });

    test("putVersion and getVersion", () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      await saveLocal.putVersion(1);
      expect(await saveLocal.getVersion(), 1);
    });

    test("putDeferred and getDeferred", () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      final deferredData = {"task1": 1, "task2": 2};
      await saveLocal.putDeferred(deferredData);
      expect(await saveLocal.getDeferred(), deferredData);
    });

    test("clear", () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      await saveLocal.put({"key": "value"});
      await saveLocal.putVersion(1);
      await saveLocal.putDeferred({"task1": 1});
      await saveLocal.clear();
      expect(await saveLocal.get("key"), "");
      expect(await saveLocal.getVersion(), 0);
      expect(await saveLocal.getDeferred(), {});
    });

    test('getDeferred returns empty map when not set', () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      expect(await saveLocal.getDeferred(), equals({}));
    });

    test('put with empty map', () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      await saveLocal.put({});
      expect(await saveLocal.getAll(), isEmpty);
    });

    test('put overwrites existing values', () async {
      final saveLocal = SaveLocal(name: "test", uniqueId: "test");
      await saveLocal.put({'key': 'value1'});
      await saveLocal.put({'key': 'value2'});
      expect(await saveLocal.get('key'), equals('value2'));
    });
  });
}
