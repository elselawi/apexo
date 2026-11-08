---
description: Apexo core patterns — Model contract, reactive observables, Store lifecycle and sync, Hive + PocketBase persistence, and the app-wiring boundary. Applies when creating or modifying models, stores, or core infrastructure.
applyTo: "lib/core/**"
---

# Apexo Core

Three layers: `Model` (data), observables (reactivity), `Store<G extends Model>` (memory + Hive + PocketBase).

## Model (`lib/core/model.dart`)

Every stored object extends `Model`: `id` (uuid), `archived` (soft delete), `title`, plus `locked`, `color` (deterministic from `id`), `avatar`, `imageRowId`, `labels`.

```dart
class MyModel extends Model {
  String name = "";

  MyModel.fromJson(super.json) : super.fromJson();

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
    if (json["name"] != null) name = json["name"] as String;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = MyModel.fromJson({});           // default instance
    if (name != d.name) json["name"] = name;  // write only non-defaults
    return json;
  }

  @override
  MyModel copy(bool blank) => MyModel.fromJson(blank ? {} : toJson());
}
```

- A field reset to its default is **absent** from `toJson`, so merge code must delete the key rather than write the default.
- `copy(blank)` is how panels and windows take an editable copy: edit the copy, `store.set` it.
- Push hooks (`pushOnCreation`, `pushIfChanged`, `targetsToPushTo`, `jsonCopyForPush`) are read by `ObservableDict.set`; delivery is described in `notifications.instructions.md`. `synchronization/push_data.dart` is mirrored by `web/fcm/push_data.js` — change both.

## Reactivity (`lib/core/reactive/`)

- `ObservableState<T>`: call with no argument to read, with a value to write and notify — `counter()`, `counter(5)`.
- `ObservableBase`: `stream` (cached broadcast — pass this field, never a recreated stream), `observe`/`unObserve`, `silently(fn)` (mutate without notifying), `dispose()`.
- `ObservableDict<G>`: the store's map. Emits `DictEvent`s (add/modify/remove with changed keys and old/new values). `notifyView()` redraws without persisting.
- `ObservablePersistingObject`: a Hive-persisted singleton (`login`, `localSettings`, `patientSide`). Subclass it, implement `toJson`/`fromJson`, pass a unique `identifier`; call `notifyAndPersist()` to save.

## Store (`lib/core/store.dart`)

```dart
class Patients extends Store<Patient> {
  Patients() : super(
          effects: applicationStoreEffects,
          loadDocuments: loadApplicationDocuments,
          modeling: Patient.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: ..., onSyncEnd: ...);

  late final _session = StoreSessionBinding<Patient>(
    store: this, name: "patients", loadingMessage: "Synchronizing patients");

  @override
  void init() {
    super.init();
    _session.install();
  }
}

final patients = Patients();
```

| Member | Meaning |
|---|---|
| `docs` | every document, archived included |
| `present` | non-archived, non-locked — what lists and pickers show |
| `archived` | separate map of archived documents |
| `get(id)`, `has(id)` | one document |
| `set(item)`, `setAll(items)` | add or replace; memory first, persistence async |
| `archive(id)`, `unarchive(id)` | soft delete and restore. `delete(id)` is `archive(id)` — **there is no hard delete** |
| `synchronize()`, `inSync()` | sync pass; whether local and remote versions match |
| `loaded`, `reload()`, `waitUntilChangesAreProcessed()` | first local load; reload; drain pending writes |
| `uploadImg`, `deleteImg` | file attachments on the store's records |

There is no `list()` or `search()`: read `present.values` and filter in the feature.

**Sync:** a mutation is debounced (`debounceMS`, 100 ms) into `_processChanges`, persisted locally as soon as that queued pass runs (no network needed), and pushed remotely only while `remote.isOnline`; offline rows and files are deferred and replayed later. One `SerialOperationQueue` owns writes, sync passes and attachments. Pulls use a fixed upper timestamp with `(updated, id)` keyset paging. Conflicts resolve by timestamp winner (no three-way baseline) and pending local edits win; realtime rows arrive through `RealtimeSubscription`.

**Persistence:** each store gets Hive boxes `<name>-main` (document JSON by id) and `<name>-meta` (version, deferred timestamps). PocketBase keeps every store's rows in one `data` collection namespaced by its `store` column. Remote timestamps are `yyyy-MM-dd HH:mm:ss.SSSZ` (no `T`).

## App-wiring boundary

Core stores default to inert `StoreEffects` and an application-independent loader. Production stores pass `applicationStoreEffects` and `loadApplicationDocuments` from `lib/app/data/`; tests inject recording stand-ins. Core must not import login, settings, notification delivery, dialogs or app logging.

`StoreSessionBinding` owns the session: registers `login.activators[name]`, drains pending work before replacing the Hive adapter, builds `SaveRemote`, installs sync/reconnect/online/offline callbacks, and removes them on stop. Do not register those callbacks in a feature store; post-sync work goes in `afterSynchronize` and checks its `isCurrent` after every await.

## MultiStreamBuilder (`lib/core/multi_stream_builder.dart`)

`MStreamBuilder(streams: [...], builder: (context, data) {})` rebuilds when any listed observable stream emits.
