---
description: Apexo feature patterns — file layout, store + session wiring, carried records (visits), follow-ups, panels, windows, screens, and creating records.
applyTo: "lib/features/**"
---

# Apexo Features

## Layout

| Files | When |
|---|---|
| `<name>_model.dart`, `<name>_store.dart`, `<name>_screen.dart`, `open_<name>_panel.dart` | the feature stores data |
| `<name>_screen.dart`, `<name>_controller.dart` (`ObservableState` + logic, no persistence), optional `open_<name>_panel.dart` | the feature stores nothing |

A feature's model, queries and caches stay inside `lib/features/<f>/`; application/session wiring belongs to `lib/app/data/`. A controller is a plain class holding `ObservableState` values and logic, exported as a module-level singleton (`dashboardCtrl`) — no persistence, no sync. A large panel may split into `part '<name>_panel_widgets.dart';`. A file editing one field group is `<thing>_widget.dart`, never a second `open_*` file.

## Store + session

One `StoreSessionBinding` per store, installed from `init()`; it owns login/logout, the Hive adapter swap and all sync/reconnect/online callbacks. Never register those callbacks in a feature store. Derived data belongs in getters over `present.values` (e.g. `allTags`). Register the singleton in `lib/app/data/initialize_stores.dart`.

## Layers below the features

- `lib/ui/workspace/` — panels, windows, dock, layout. It may not import a feature; the app hands records in (`refreshStreams`, `WindowDefaults`, `fileLinkResolver`).
- `lib/shared/` — editors more than one feature opens (`image_viewer/`, `dental_chart/`). They know teeth and pens, not patients; the feature supplies the model-bound glue (`patient_dental_chart.dart`).

## Carried records (a visit beside its patient)

A record carried beside another has no `open_*_panel.dart`: its opener is `open_<record>.dart`, and it is a **session**, not a panel.

- `<record>_session.dart` implements `HostedRecordSession` (never `Panel`) and owns the draft, the chart and the record's windows.
- `<record>_sessions.dart` is the identity map: one id → one draft, cleared on logout. Two openers of the same record get the same session, so two windows cannot disagree.
- The panel calls `Panel.attach(session, focus:)`; the footer's Close calls `detach()` (keeps the draft) and `disposeSession()` drops it. The panel draws the bubble-shaped **band** from the interface's own label, state and Save — never a copy.
- Moving to another visit is a swap, not a discard: the visit left behind keeps its draft (teeth, operative details, band fields). `closeOpenDentalChartWindows` resets only a chart that would really be thrown away — a panel's own plan chart, or a standalone chart.
- Every local mutation goes through `<record>_commands.dart`'s `appointmentCommand(id, mutate)`: it edits the open draft, or the store when none is open. With a draft open it also stores exactly the changed fields and acknowledges only those (`writeThrough`) — list checkboxes, calendar drags and toggles read the **store**, so a draft-only change is invisible and lost with the panel. A direct `store.set` on a carried record is the bug that reverts a calendar drag.
- A write outside the record's Save (a gallery's files) writes only its own fields (`markFieldsSaved`).
- The band carries the record's own form (`HostedRecordSession.bandContent`), keyed by record id so a different record is a different form.
- The band's tool dock (`AppointmentBandDock`) opens the chart; it stays reachable while the chart is away.
- Labwork and gallery are band **attachments** (`PanelWindow.bandAttachment`), drawn by `WindowAttachments` at the band's foot (`WK.visitBandAttachments`) and again on the post-op card in the chart (`WK.visitChartAttachments`); both trays switch the same windows in `kAttachedSlot`.
- The band footer owns Delete/Restore, Close, the retained-draft hint and Save-when-dirty: standard `Button`s per act, `FilledButton` for the one that keeps the work. While a visit is attached, the panel's inline record is drawn read-only behind `AbsorbPointer` and a notice.
- A window that is an editor *of* a record is an attachment: `PanelWindow.attachedTo` names the frame drawing its chip (`kDentalChartWindowId`, `bandAttachment`, `panelAttachment`); `WindowAttachments` draws the tray and keys chips `WK.attachmentToggle(id, owner: frameId)`.
- Layout memory is keyed by record **kind + slot** (`appointment/attached`), never by id. Editor state belongs to the record (galleries keyed by visit id).
- `minHeight` governs automatic opening only: an explicitly requested chart stays reachable on a short screen, scrolling.
- Closing after Save rechecks every owner for pending edits and active writes; an edit or new attachment during a save keeps the panel open. Gallery progress outlives the gallery widget.
- `canArchive` gates band and feature actions; `setArchived` enforces it again before writing.
- A standalone editor backed by a draft passes `recordSession` to `WindowsManager.showStandalone`; close confirmation counts and saves the owner once across all its windows.

## Follow-ups (optional)

- Off by default: `follow_ups_enab` ("1"/"0"). Every surface checks `followUpsEnabled`; `followUpsOn` and `applyFollowUpsForNewVisit` are inert while it is off.
- `setFollowUp(patientID, date, {note})` writes the store and the open patient draft, acknowledging both fields, and bumps `followUpRevision` so both editing surfaces redraw.
- A note follows its day: passing no note keeps the stored one; clearing the day clears the note.
- `FollowUpField` edits a draft — Save writes day, note and removal together; Cancel drops; Delete takes the promise back at once. Never write per keystroke.
- Presets write themselves out ("2 weeks") when they fit — decide by measuring (`_longPresetsFit`), not guessing — and fall back to `FollowUpPreset.label` ("10d").
- Opening a row chooses no day; `onCollapse` folds a row opened by mistake.
- `applyFollowUpsForNewVisit` is the recall rule, called from `addAppointment` — the one path every new visit takes.
- `followUpsOn(day)` is the day's inbox: promises falling that day for patients not already booked.
- Every follow-up surface uses `kFollowUpAccent`; the patient's row is drawn through `Panel.carriedBandFooter`, directly under the band.

## Panels

`RowPanel<T>` edits one stored record and owns its draft:

```dart
RowPanel(item: Patient.fromJson(patient.toJson()), store: patients, title: ...,
  windows: ..., icon: ..., singularName: "patient", unicodeSymbol: "👤");
```

- Required: `item` (an editable **copy**), `store`, `title`, `windows`, `icon`, `singularName`, `unicodeSymbol`. Optional: `canNotBeNew`, `checkUnsavedChanges`, `onSave`, `validate`, `savedBaseline`, `carriedBandFooter`, `accent`, `initialWindow`.
- Its windows edit the same draft through `draftJson` / `adoptDraft`. `hasPendingEdits` compares current JSON with the last saved baseline; `persist()` validates, writes (`store.set` or `onSave`) and re-baselines via `markSaved()`.
- `markFieldsSaved(fields)` acknowledges an immediate write without clearing the rest of the draft.

`DelegatedPanel` is for caller-managed collections with explicit save, pending-edit and archive callbacks. Both implement the non-generic `Panel`; `panel.result` is `Future<void>`, and `savedId` / `savedIds` name the records written. Never share a draft between panels.

## Windows

`PanelWindow` fields that matter: `id` (a stable name, used by menus, dock and chips — never a list position), `title` (a localization **key**, translated on draw), `icon`, `body`, `subtitle` (read on build), `footer`, `headerActions`, `footerActions`, `editsRecord`, `onlyIfSaved`, `byDefault`, `attachedTo`, `replacementGroup`, `chipPreview`.

Declare the windows once as an enum — `<feature>_windows.dart` (`PatientWindow`, `ExpenseWindow`) when a menu or other file reads it, else beside the opener (`AppointmentWindow`) — and expose the reachable ones (`patientWindows()`); let both the panel and its menu items read that list.

## Screens

Screens react through `MStreamBuilder` on `store.observableMap.stream` plus any settings stream:

```dart
MStreamBuilder(
  streams: [
    patients.observableMap.stream,
    appointments.observableMap.stream,
    PanelsManager.active.stream,
  ],
  builder: (context, snapshot) { /* patients.present.values */ },
)
```

A row with actions opens them on long press (touch) and right click (mouse, pen): wrap it in `ContextMenuRegion` (`lib/common_widgets/context_menu_region.dart`) and reuse the exact items of the row's "more" button. Offer **one item per panel window**, not a single "open":

```dart
for (final window in patientWindows())
  MenuFlyoutItem(
    text: Txt(txt(window.titleKey)),
    leading: Icon(window.icon),
    onPressed: () => openPatient(patient, window),
  ),
```

## Creating a record

A new record is asked for in a sheet (`new_<record>_dialog.dart`) that collects the fields it cannot start without; the helper beside it (`addPatient`, `addAppointment`) stores the record, and only then is it opened — so `isNew` is false and nothing the user does can leave a draft behind. A sheet does not invent a date: it starts on the day or moment the caller came from, and a bare day takes the current time of day.

## Adding a persistent feature

1. Create the model, store, screen and panel opener under `lib/features/<name>/`.
2. Pass explicit `applicationStoreEffects` + `loadApplicationDocuments`, and own one `StoreSessionBinding`.
3. Register the singleton in `lib/app/data/initialize_stores.dart`.
4. Add the `AppRoute`, its `_syncStores` case, and localized strings for every locale.
5. Add deterministic tests with isolated Hive where persistence is involved.

## Common mistakes

| Mistake | Fix |
|---|---|
| Mutating the stored record instead of the panel's copy | `Model.fromJson(stored.toJson())` for the draft |
| Forgetting `.init()` or the `initializeStores()` registration | The store never loads or activates |
| Not installing a `StoreSessionBinding` | No local or remote persistence after login |
| `Text(txt("key"))` | `Txt(txt("key"))` so a language switch redraws |
| `Txt("key")` | `Txt` renders verbatim — pass `txt(...)` |
| Adding a key to `en.dart` only | Add it to every locale, then run `dart run lib/services/localization/verify.dart` |
| `store.set` on a carried record | `appointmentCommand(id, mutate)` |
| Two `open_*` files for one record's field groups | One opener; other editors are `<thing>_widget.dart` |
