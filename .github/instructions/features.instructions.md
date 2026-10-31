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

## Layers below the features

The features sit at the top. Two folders below them exist for code more than one
feature uses, and neither may import a feature (a guard test enforces both):

- `lib/ui/workspace/` — the window system: panels, windows, the dock and the
  layer that draws them. It may use `core`, `services`, `common_widgets` and
  itself. A record it needs — a store to relabel a window, a file URL to show —
  is handed in by the app (see `refreshStreams`, `WindowDefaults`,
  `fileLinkResolver`), never imported.
- `lib/shared/` — editors more than one feature opens: `image_viewer/` and
  `dental_chart/`. They know teeth, pages and pens, not patients or visits; the
  feature supplies its model-bound glue (`patient_dental_chart.dart`,
  `appointment_dental_chart.dart`, `patient_owner_line.dart`).

Naming: `open_<record>_panel.dart` opens a panel over a stored record and is
built with `PanelsManager.open`; a window shown on its own with
`WindowsManager.showStandalone` lives in the feature as
`open_<record>_window.dart`. A file that edits one record's field group is
`<thing>_widget.dart`, not a second `open_*` file.

A record that is **carried beside another** (a visit beside its patient) has no
`open_*_panel.dart`: its opener is `open_<record>.dart`, because it opens no
panel of its own. Such a record is a **session**, not a panel:

- The session (`<record>_session.dart`) owns the draft, the chart or other
  editors that belong to the record, and the record's windows. It implements
  `HostedRecordSession` (`lib/ui/workspace/record_session.dart`) — never `Panel`.
- The registry (`<record>_sessions.dart`) is the app's identity map: one id, one
  draft, for the app session, cleared on logout. Two openers of the same record
  get the same session, so two windows cannot disagree.
- The panel that shows it calls `Panel.attach(session, focus:)`; closing the visit
  (the footer's Close, backed by `detach()`) keeps the draft, `disposeSession()`
  drops it. The panel draws a bubble-shaped **band** for it — it implements the
  interface's own label, state and Save, never a copy.
- Moving to another visit is a swap, not a discard: the visit left behind keeps its
  draft — teeth, operative details and the band's fields alike — so nothing asks
  first. The chart-swap guard (`closeOpenDentalChartWindows`) only resets a chart
  that would really be thrown away: a panel's own plan chart, or a chart standing
  on its own. The band says which retained visits still hold work.
- Every local mutation of that record goes through
  `<record>_commands.dart`'s `appointmentCommand(id, mutate)`: it edits the open
  draft when there is one, and the store when there is not. With a draft open it
  **also stores exactly the fields the mutation changed** and acknowledges only
  those (`writeThrough`), because the controls that call it — a list checkbox, a
  calendar drag, a labwork toggle — read the record from the store: a change held
  only in the draft is invisible to them and is lost with the panel. A direct
  `store.set(...)` on a carried record is still the bug that reverts a calendar
  drag.
- A write outside the record's Save (a gallery's files) writes **only its own
  fields** and acknowledges only those (`markFieldsSaved`).
- The band also carries the record's **own form** (`HostedRecordSession.bandContent`):
  a visit's date, time, duration, operators and pre-op notes are compact fields
  inside the band, so they need no window and no row slot. The band content is
  keyed by the record's id: a different visit is a different form, never the old
  fields under a new title.
- The visit band also draws the record's **tool dock** (`AppointmentBandDock`): one
  tool, operative details, whose fields live at the foot of the visit's chart, so
  its button opens that chart. It stays reachable while the chart is away, because
  the band is the visit's permanent surface.
- The band's labwork order and gallery are **not** dock chips: they are
  attachments of the band (`PanelWindow.bandAttachment`), drawn as a
  `WindowAttachments` tray at the band's foot (`WK.visitBandAttachments`) and again
  on the post-op card inside the visit's chart (`WK.visitChartAttachments`), the
  way a patient's photos hang off the patient panel. Both trays switch the same
  windows in the row's `kAttachedSlot`.
- The band's **footer** owns the record's actions: Delete/Restore, Close, the
  retained-draft hint with its "move to that visit" action, and Save when the
  visit is dirty. It uses standard Fluent buttons so themes own the colours. While
  a visit is attached, the panel's inline record is drawn read-only (visible, but
  behind an `AbsorbPointer` and a short notice) because its Save is not the visit's
  Save.
- A window that is an editor *of* a record rather than its workspace is an
  **attachment**: `PanelWindow.attachedTo` names the frame that draws its chip —
  another window (`kDentalChartWindowId`), the record's band
  (`PanelWindow.bandAttachment`), or `PanelWindow.panelAttachment` for the panel
  itself. Attachments are never row windows and never first picks.
  `byDefault: false` makes any other row window a labelled workspace button.
- A panel that presents its windows this way sets `attachmentLayout: true` and
  `workspaceWindows: [...]` (`Panel`): its labelled workspace buttons live inside
  the record's own body instead of under the header. Both workspace buttons are
  always drawn; filled means open, neutral means closed, and the filled one's
  label is painted in the accent's own foreground colour. The pair is drawn
  joined — no gap, and only the outer corners rounded — so it reads as one
  control. `WindowDock` draws it, the same widget a panel with floating windows
  uses for its switches: equal segments filling the panel's width, one flat
  stroke, a filled segment in the record's accent while its window is open, and a
  label too long for its segment ellipsised with the full name in the tooltip.
  Opening the patient's plan closes the attached visit (its draft is retained)
  rather than showing two charts.
  `WindowAttachments` draws the tray; the key is
  `WK.attachmentToggle(id, owner: frameId)` because two records may both offer a
  `gallery`.
- Naming the layout memory: keyed by record **kind + slot**
  (`appointment/attached`), never by record id. Editor state, by contrast, belongs
  to a record: key galleries by visit id and refresh labwork controllers when
  their appointment changes.
- Minimum height controls automatic opening, not an explicit request: a requested
  chart remains reachable on a short screen, with its content scrolling.
- Closing after Save must recheck every owner for pending edits and active writes.
  An edit or a newly attached visit during a save must keep the panel open.
  Gallery progress belongs to its record and must finish even after the gallery
  widget leaves the screen.

Tests mirror `lib/`: `test/widget/features/<feature>/`, `test/widget/app/` for
the shell, `test/widget/shared/<editor>/` for a shared editor, and
`test/widget/common_widgets/` for the atoms.

## Panel pattern

Use `RowPanel<T>` and its independent `RowDraft` for one stored record.
Use `DelegatedPanel` for caller-managed collections with explicit save,
pending-edit and archive callbacks. Both implement the non-generic `Panel`
host contract. `panel.result` is a `Future<void>`; inspect `savedId`/
`savedIds` for records written. Do not share drafts between panels.

### Creating a record

A new record is asked for in a sheet, not in an empty panel: the sheet
(`new_<record>_dialog.dart`) collects the fields the record cannot start
without, the helper beside it (`addPatient`, `addAppointment`) stores the
record, and only then is it opened — so `isNew` is false and nothing the user
does can leave a draft behind. Guess what the sheet can: an appointment's date
and time come from the day the caller came from and the visits already booked
that day (`appointment_start_guess.dart`).

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

When the row opens a panel, offer **one item per panel window** instead of a
single "open". Declare the windows once as an enum in the feature — in
`<feature>_windows.dart` when a menu or another file reads it
(`PatientWindow`, `ExpenseWindow`), or beside the opener when nothing outside
it does (`AppointmentWindow`) — expose the reachable ones (`patientWindows()`,
`appointmentWindows(appointment)`, `expenseWindows(...)`), and let both the
panel and the menu read that list — then a menu item cannot land on the wrong
window:

```dart
for (final window in patientWindows())
  MenuFlyoutItem(
    text: Txt(txt(window.titleKey)),
    leading: Icon(window.icon),
    onPressed: () => openPatient(patient, window),
  ),
```

Keep `PanelWindow.title` a localization **key**: the host runs it through
`txt()`, so an open window relabels on a language switch. The window's `id` is
what the dock button, the opener and the menu all name it by — never its
position in a list.

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
