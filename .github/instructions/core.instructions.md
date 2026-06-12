---
description: Core architecture patterns for Apexo — Model base class, Store with local/remote sync, Observable reactive system, Hive persistence, and PocketBase sync. Applies when creating or modifying data models, stores, or core infrastructure.
applyTo: "lib/core/**"
---

# Apexo Core Architecture

## Overview

Apexo uses a **custom reactive data layer** built on three pillars:

| Layer | Class | Purpose |
|-------|-------|---------|
| **Data** | `Model` | Base class for all domain objects — defines serialization, identity, and computed properties |
| **Reactivity** | `ObservableBase` / `ObservableState` / `ObservableDict` / `ObservablePersistingObject` | Custom observable system — no external state management library |
| **Persistence + Sync** | `Store<G extends Model>` | Combines local storage (Hive) + remote sync (PocketBase) with debounced change processing |

## Model (`lib/core/model.dart`)

Every domain object extends `Model`. Key conventions:

```dart
class MyModel extends Model {
  String name = '';

  MyModel.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = MyModel.fromJson({});  // default instance for diffing
    if (name != d.name) json['name'] = name;  // only serialize if different from default
    return json;
  }
}
```

### Important Model Properties

| Property | Purpose |
|----------|---------|
| `id` | Unique identifier (auto-generated UUID via `uuid()`) |
| `archived` | Soft-delete flag — set to `true` to hide from normal views |
| `title` | Human-readable label (shown in lists, search) |
| `locked` | Override to return `true` when the current user shouldn't edit this item |
| `color` | Deterministic color derived from `id` — used for visual identity in the UI |
| `avatar` | Optional image URL for the item |
| `labels` | Map of label → value for display in data tables |
| `pushIfChanged` | List of field names that trigger a push notification when modified |
| `targetsToPushTo` | List of user IDs to send push notifications to |
| `pushOnCreation` | Whether to send a push when this item is first created |
| `jsonCopyForPush` | Subset of JSON data included in push notifications |

### The `copy(blank)` Pattern

Every model must implement `copy(bool blank)` — used by the panel system to create editable copies:

```dart
@override
MyModel copy(bool blank) {
  return MyModel.fromJson(blank ? {} : toJson());
}
```

## Observable System (`lib/core/observable.dart`)

### ObservableState\<T\>

A single reactive value. **Call it to read, pass a value to write:**

```dart
final counter = ObservableState<int>(0);
print(counter());     // read → 0
counter(5);           // write → notifies all observers
```

Use `.stream` to listen, `.observe(callback)` to subscribe, `.silently(fn)` to mutate without notifying.

### ObservableDict\<G\>

A reactive key-value map used internally by `Store`. Tracks add/remove/modify events with the specific keys that changed.

### ObservablePersistingObject

For singletons that need Hive persistence (e.g., `_LoginService`, `localSettings`). Extend it, define `toJson()`/`fromJson()`, and pass a unique `identifier` string.

## Store (`lib/core/store.dart`)

The `Store<G extends Model>` is the central data management class. Every feature with persistent data gets one.

### Lifecycle

1. **Construction**: Takes `modeling` (JSON→Model factory), optional `local` (Hive), and `remote` (PocketBase)
2. **`loaded` future**: Loads all data from local Hive storage into memory
3. **`init()`**: Sets up the sync timer and observers
4. **Changes**: When the `observableMap` changes, changes are buffered, debounced, then persisted locally and pushed remotely

### Key Methods

| Method | Purpose |
|--------|---------|
| `get(id)` | Retrieve a document by ID |
| `set(item)` | Insert or update a document |
| `delete(id)` | Remove a document |
| `archive(id)` | Set `archived = true` |
| `restore(id)` | Set `archived = false` |
| `synchronize()` | Force a full pull from remote |
| `docs` | All loaded documents (Map<String, G>) |
| `list()` | All non-archived documents as a list |
| `search(query)` | Full-text search across titles |

### Sync Behavior

- Changes are **debounced** (`debounceMS`, default 100ms)
- Local writes happen immediately
- Remote writes only when `remote.isOnline` is true
- Offline changes are **deferred** and synced when connectivity returns
- `manualSyncOnly: true` disables automatic sync (used for settings stores)

### Example: Creating a Store

```dart
final myStore = Store<MyModel>(
  modeling: MyModel.fromJson,
  local: SaveLocal(name: "my_models", uniqueId: login.uniqueID),
  remote: SaveRemote(storeName: "my_models", pbInstance: pb!),
  showArchived: showArchived,  // optional
  isDemo: launch.isDemo,       // optional
);
myStore.init();
```

## SaveLocal (`lib/core/save_local.dart`)

Hive-based persistence. Each store gets two Hive boxes:
- **`{name}-main`**: Stores document JSON keyed by ID
- **`{name}-meta`**: Stores version number and deferred sync timestamps

## SaveRemote (`lib/core/save_remote.dart`)

PocketBase-based sync. Key behaviors:
- Uses a single `data` collection in PocketBase with a `store` column to namespace rows
- **Version-based sync**: each write increments a version; pulls only rows with version > local version
- **Online detection**: periodic health checks, auto-retry on failure
- Timestamps formatted as `yyyy-MM-dd HH:mm:ss.SSS` (SQLite-compatible, no `T` separator)

## MultiStreamBuilder (`lib/core/multi_stream_builder.dart`)

Combines multiple streams into a single builder — used throughout the app to react to multiple observable changes simultaneously:

```dart
MStreamBuilder(
  streams: [store.stream, settings.stream],
  builder: (context, _) { ... },
)
```
