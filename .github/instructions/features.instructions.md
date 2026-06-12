---
description: Feature structure pattern for Apexo — how features are organized with Model, Store, Screen, Panel, and Controller. Applies when creating new features, modifying feature screens, or working with the panel-based navigation system.
applyTo: "lib/features/**"
---

# Apexo Feature Architecture

## Feature File Structure

Every feature in `lib/features/<name>/` follows a consistent pattern. The presence of each file depends on whether the feature manages persistent data:

### Features WITH persistent data (has a Store)

| File | Required | Purpose |
|------|----------|---------|
| `<name>_model.dart` | ✅ | Extends `Model` — defines fields, serialization, computed properties |
| `<name>_store.dart` | ✅ | Extends `Store<Model>` — singleton, data management, sync, cached queries |
| `<name>_screen.dart` | ✅ | Full-screen list/datatable view of all items |
| `open_<name>_panel.dart` | ✅ | Detail/edit panel builder — returns `Future<Model>` via `routes.openPanel()` |

### Features WITHOUT persistent data (no Store)

| File | Required | Purpose |
|------|----------|---------|
| `<name>_screen.dart` | ✅ | Main screen widget |
| `<name>_controller.dart` | ✅ | Logic/state (not a Store — simpler reactive state) |

### Examples

```
features/patients/              ← with Store
├── patient_model.dart
├── patients_store.dart
├── patients_screen.dart
└── open_patient_panel.dart

features/dashboard/             ← without Store
├── dashboard_screen.dart
└── dashboard_controller.dart

features/accounts/              ← without Store, but with panel
├── accounts_screen.dart
├── accounts_controller.dart
└── open_account_panel.dart
```

## Store Pattern (`lib/features/<name>/<name>_store.dart`)

Each store is a **singleton** instance exported at module level:

```dart
const _storeName = "patients";

class Patients extends Store<Patient> {
  Patients() : super(
    modeling: Patient.fromJson,
    isDemo: launch.isDemo,
    showArchived: showArchived,
    onSyncStart: () { networkActions.isSyncing(networkActions.isSyncing() + 1); },
    onSyncEnd: () { networkActions.isSyncing(networkActions.isSyncing() - 1); },
  );

  @override
  init() {
    super.init();
    login.activators[_storeName] = () async {
      await loaded;
      local = SaveLocal(name: _storeName, uniqueId: simpleHash(login.url));
      await deleteMemoryAndLoadFromPersistence();

      if (launch.isDemo) {
        if (docs.isEmpty) setAll(demoPatients(100));
      } else {
        remote = SaveRemote(
          pbInstance: login.pb!,
          storeName: _storeName,
          onOnlineStatusChange: (current) {
            if (network.isOnline() != current) network.isOnline(current);
          },
        );
      }

      return () async {
        loginCtrl.loadingIndicator("Synchronizing patients");
        await synchronize();
        networkActions.syncCallbacks[_storeName] = synchronize;
        networkActions.reconnectCallbacks[_storeName] = remote!.checkOnline;
        network.onOnline[_storeName] = synchronize;
        network.onOffline[_storeName] = cancelRealtimeSub;
      };
    };
  }

  // Cached computed queries
  List<String> get allTags { ... }
}

final patients = Patients();
// Don't forget to call patients.init() in initializeStores()
```

### Key Store Patterns

1. **`login.activators`**: Each store registers an activator that sets up local/remote storage after login. This is the lazy-init pattern — stores are created early but only activate after authentication.

2. **Demo data**: Check `launch.isDemo` and seed with generated data if the store is empty.

3. **Sync tracking**: Use `onSyncStart`/`onSyncEnd` to increment/decrement `networkActions.isSyncing`.

4. **Cached queries**: Build derived indexes (e.g., `byPatient`, `todayAppointments`) as lazily-computed getters. Nullify the cache when the observableMap changes.

5. **`networkActions` registration**: After init, register sync callbacks so the network actions widget can trigger sync/reconnect.

6. **`network.onOnline`/`network.onOffline`**: Register for connectivity change events.

## Panel Pattern (`lib/features/<name>/open_<name>_panel.dart`)

Panels are the **detail/edit view** system. They slide in from the right side of the screen.

### Panel Function Signature

```dart
Future<Patient> openPatient([Patient? patient, int? selectedTabIndex]) {
  final editingCopy = Patient.fromJson(patient?.toJson() ?? {});
  final panel = Panel<Patient>(
    singularName: "patient",
    unicodeSymbol: "👤",
    selectedTabIndex: selectedTabIndex,
    item: editingCopy,
    store: patients,
    icon: FluentIcons.medication_admin,
    title: patients.get(editingCopy.id) == null
        ? txt("newPatient")
        : editingCopy.title,
    tabs: [
      PanelTab(
        title: txt("patientDetails"),
        icon: FluentIcons.medication_admin,
        body: _PatientDetails(editingCopy),
      ),
      // ... more tabs ...
    ],
  );
  routes.openPanel(panel);
  return panel.result.future;
}
```

### Panel Constructor Parameters

| Parameter | Purpose |
|-----------|---------|
| `item` | The **editable copy** of the model (use `Model.fromJson(item.toJson() ?? {})`) |
| `store` | The singleton store for persistence |
| `singularName` | Used for logging/identification |
| `unicodeSymbol` | Emoji shown in the panel header |
| `tabs` | List of `PanelTab` — each has title, icon, body widget |
| `icon` | FluentUI icon for the panel header |
| `title` | Panel title (dynamic — shows "New X" for unsaved items) |
| `selectedTabIndex` | Which tab to open initially |
| `showBottomControls` | Whether to show Save/Cancel buttons (default `true`) |
| `inherentlyScrollable` | If `true`, the tab body is not wrapped in `SingleChildScrollView` |
| `canNotBeNew` | If `true`, the panel can only edit existing items |
| `checkUnsavedChanges` | Custom function to detect unsaved changes (for multi-item panels) |
| `onSave` | Custom save handler (for multi-item panels) |

### Panel Lifecycle

1. **Open**: `routes.openPanel(panel)` — adds to the panel stack
2. **Edit**: User modifies the editable copy in the tab bodies
3. **Save**: Panel compares `jsonEncode(item.toJson())` vs `savedJson` every 750ms; Save button calls `store.set(item)`
4. **Close**: If unsaved changes, shows confirm dialog; otherwise removes from stack
5. **Result**: `panel.result.future` completes with the saved item when the panel closes

### Adding a New Feature (Checklist)

1. Create `lib/features/<name>/` directory
2. Create `<name>_model.dart` extending `Model`
3. Create `<name>_store.dart` extending `Store<Model>` with singleton
4. Register the store in `lib/utils/init_stores.dart` (call `.init()`)
5. Create `<name>_screen.dart` — the list/datatable view
6. Create `open_<name>_panel.dart` — the detail/edit panel builder
7. Add a `Route` in `lib/app/routes.dart`
8. Add a "New X" button that calls the panel function
9. Add localization keys for all user-facing strings

## Screen Pattern

Screens use `MStreamBuilder` to react to store changes:

```dart
class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [patients.observableMap.stream, showArchived.stream],
      builder: (context, _) {
        // Build datatable / list from patients.list()
      },
    );
  }
}
```

## Controller Pattern (for non-Store features)

Controllers are plain Dart classes that hold `ObservableState` values and business logic. They're simpler than Stores — no persistence, no sync:

```dart
class DashboardController {
  final selectedView = ObservableState<int>(0);
  // ... computed getters, action methods ...
}

final dashboardCtrl = DashboardController();
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Mutating `item` directly instead of the editing copy | Always use `Model.fromJson(item.toJson() ?? {})` for the panel's editing copy |
| Forgetting to call `.init()` on a new store | Add to `initializeStores()` in `lib/utils/init_stores.dart` |
| Not registering `login.activators` | Store won't have local/remote set up after login |
| Using `Text(txt("key"))` in feature screens | Use `Txt("key")` so text updates on language switch |
| Not adding localization keys | Run `dart run lib/services/localization/verify.dart` to catch missing keys |
