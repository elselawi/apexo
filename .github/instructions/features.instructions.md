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
| `open_<name>_panel.dart` | ✅ | Detail/edit panel builder — returns `Future<Model>` via `PanelsManager.open()` |

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

Each store is a **singleton** instance exported at module level. Keep models,
queries/caches and screens feature-local; application/session integration belongs
to `lib/app/data/`.

```dart
class Patients extends Store<Patient> {
  Patients() : super(
    modeling: Patient.fromJson,
    effects: applicationStoreEffects,
    loadDocuments: loadApplicationDocuments,
    isDemo: launch.isDemo,
    onSyncStart: () => networkActions.isSyncing(networkActions.isSyncing() + 1),
    onSyncEnd: () => networkActions.isSyncing(networkActions.isSyncing() - 1),
  );

  late final session = StoreSessionBinding<Patient>(
    store: this,
    name: 'patients',
    loadingMessage: 'Synchronizing patients',
    seedDemo: () => demoPatients(100),
  );

  @override
  void init() {
    super.init();
    session.install();
  }
}
```

The binding installs the two-stage login activator, drains before replacing Hive,
constructs remote persistence, and removes all session callbacks on stop.
Do not register network/sync/logout callbacks separately in feature stores.
Optional post-sync behavior stays feature-owned through `afterSynchronize`;
use its `isCurrent` check after awaits before publishing session-bound state.

## Panel pattern

Use `RowPanel<T>` and its independent `RowDraft` for one stored record.
Use `DelegatedPanel` for caller-managed collections with explicit save,
pending-edit and archive callbacks. Both implement the non-generic `Panel`
host contract. `panel.result` is a `Future<void>`; inspect `savedId`/
`savedIds` for records written. Do not share drafts between panels.

### Adding a persistent feature

1. Create the feature model/store/screen/panel opener under `lib/features/<name>/`.
2. Supply explicit application effects/loader and one session binding.
3. Initialize the singleton in `lib/app/data/initialize_stores.dart`.
4. Add the route/screen and localized UI strings.
5. Add deterministic tests with isolated Hive where persistence is involved.

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

### Row actions

A row that has actions also opens them on long press (touch) and right click
(mouse, pen). Wrap the row in `ContextMenuRegion` from
`lib/common_widgets/context_menu_region.dart` and build the same items the row's
"more" button already shows — never a new permission-free shortcut:

```dart
ContextMenuRegion(
  items: (context, controller) => [
    MenuFlyoutItem(
      text: Txt(txt("open")),
      leading: const Icon(WindowsIcons.open_in_new_window),
      onPressed: open,
    ),
  ],
  child: ListTile(...),
)
```

The region plays the platform feedback for the long press, anchors the menu at
the pointer, and flips it in RTL. Reuse `controller` for a follow-up flyout
(a delete confirmation); the menu closes by itself when an item is clicked.

When the row opens a panel, offer **one item per panel tab** instead of a single
"open". Declare the tabs once as an enum in the panel's own file (`PatientTab`,
`AppointmentTab`, `ExpenseTab`), expose the reachable ones (`patientTabs()`,
`appointmentTabs(appointment)`, `expenseTabs(...)`) plus the matching index
helper, and let both the panel and the menu read that list — then a menu item
cannot land on the wrong tab:

```dart
for (final tab in patientTabs())
  MenuFlyoutItem(
    text: Txt(txt(tab.titleKey)),
    leading: Icon(tab.icon),
    onPressed: () => openPatient(patient, patientTabIndex(tab)),
  ),
```

Keep `PanelTab.title` a localization **key**: the host runs it through `txt()`,
so an open panel relabels on a language switch.

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
| Forgetting to call `.init()` on a new store | Add to `initializeStores()` in `lib/app/data/initialize_stores.dart` |
| Not registering `login.activators` | Store won't have local/remote set up after login |
| Using `Text(txt("key"))` in feature screens | Use `Txt(txt("key"))` so text updates on language switch |
| Passing a raw key to `Txt`, e.g. `Txt("myKey")` | `Txt` renders its argument verbatim — the key itself would show; pass `Txt(txt("myKey"))` |
| Not adding localization keys | Run `dart run lib/services/localization/verify.dart` to catch missing keys |
