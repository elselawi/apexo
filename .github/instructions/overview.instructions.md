---
description: Apexo app map — layers and import rules, where code lives, startup/session flow, and the cross-cutting APIs (routing, permissions, dates, errors, keys) every feature uses.
applyTo: "lib/**"
---

# Apexo — App Map

Flutter + `fluent_ui`, offline-first. A custom reactive layer, Hive for local storage, PocketBase for sync. No state-management, routing or DI package.

## Layers

Import direction is enforced by `test/unit/core/architecture_*_test.dart`:

- `core/` imports nothing from `app/`, `features/` or `services/`.
- `services/` may use `core/` and `utils/` — never `app/`, a feature, or `ui/workspace/`.
- `ui/workspace/` and `shared/` may use `core/`, `services/`, `common_widgets/` — never a feature; the app hands their records in.
- `features/` and `app/` may use all of the above; `app/` is the composition root.

| Folder | Holds |
|---|---|
| `lib/core/` | `Model`, reactive primitives, `Store`, Hive/PocketBase adapters, sync policy |
| `lib/app/` | composition root: shell + routes, store effects/loader, session binding, store init |
| `lib/features/<f>/` | one feature: model, store, controllers, screen, panel/window openers |
| `lib/ui/workspace/` | panels and floating windows — `Panel`, `RowPanel`, `PanelsManager`, `WindowsManager` |
| `lib/shared/` | editors used by more than one feature (dental chart, image viewer) |
| `lib/common_widgets/`, `lib/utils/` | atoms; platform and formatting helpers |
| `lib/services/` | login, permissions, launch, network, notifications, AI, localization, DICOM |

## Startup and session

`main.dart`: `initializeDateFormatting` → `initDicomToolkit` → `Messaging.initializeReceiving` (native) → `initializeStores()` → `initializeBooking()` → `runApp`.

- `launch.open` picks the first surface: `Open.login | staff | patient`. `launch.isDemo` is true on `demo.apexo.app` — demo seeds data, has no auth, no remote, no push.
- Login runs every `login.activators[<store name>]` (installed by `StoreSessionBinding`) — each opens its local storage, then the returned remote stages sync concurrently — then `SessionEvents.started()`. An admin login reconciles the server schema at most once per app version: the applied version is remembered in the login state (`schemaServer`/`schemaVersionApplied`) and in a Hive box, so later starts touch neither the network nor local storage. An online login then reads the server's status message in the background; it never delays the login. Logout invalidates the notification session, stops each store (`onLogoutCallbacks`), then runs `SessionEvents.onEnded` callbacks (routes, panels, windows, visit drafts).
- `network.onOnline` / `onOffline` maps and `networkActions.isSyncing` drive reconnection and the progress UI.
- Three integrations sit outside PocketBase: the booking Worker (`bookingOrigin`, default `https://book.apexo.app`, gated by `bookingAvailable`), the DICOM toolkit (`lib/services/dicom/`, Windows only — `DicomController.isSupported`; its auto-scan timer needs `initializeDicomScan()` in `main.dart` before any login), and the status endpoint (`lib/services/server_status.dart`, `https://servers.apexo.app/hosted/<host>`, which may raise a message dialog after login).

## Cross-cutting APIs

| Need | Use |
|---|---|
| Stored UI text | `Txt(txt("key"))` — not `Text(txt(...))`, never `Txt("key")` |
| Combo boxes | `AppComboBox` (`lib/common_widgets/app_combo_box.dart`) — not fluent's `ComboBox`; it keeps the control as tall as the app's text fields |
| Dates and times | `DF.commonDate/full/time/dayOfWeek/...` — honours the Persian/Hijri calendar setting; never raw `DateFormat` for UI |
| Money | `MoneyDisplay` / `formatMoneyInText`; currency is `globalSettings.currency` |
| Permissions | `login.perm(Perm.patients)` → `PermLevel` (`.none/.read/.full/.some/.exact(n)`). Slots 0–8 are `patients, appointments, postOp, stats, expenses, setting, photos, notes, revenue`; values are 0 none / 1 limited / 2 full. Admins and demo get `Perm.full` |
| Errors | `showErrorMessage(error, when)` for the user, `logger(message, stack, importance)` to Sentry |
| Widget keys | `WK.*` in `lib/widget_keys.dart` — widget tests find widgets by them |
| Reactive UI | `observable.stream` (cached) inside `MStreamBuilder(streams:, builder:)` |
| Routes | `AppRoute` enum (`lib/app/routing/app_route.dart`) — declaration order is navbar order; add a route → `buildScreen()` and a `_syncStores` case in `lib/app/routing/routes.dart` |
| Panels / windows | `PanelsManager.open`, `WindowsManager.showStandalone` |
| Files | `filesDir()`; `resolveFileLink(rowId, name)` (bound in `main.dart` to appointments) |
| Global settings | `globalSettings.get("<id>").value` — ids are exactly 15 chars; register a default in `GlobalSettings.defaults` |
| Device settings | `localSettings` — persisted singleton: locale, calendar system, time/date format, AI token |
| Feature gating | `globalSettings.aiServicesEnabled`, `globalSettings.followUpsEnabled`, `bookingAvailable`, `DicomController.isSupported` |

Topic guides in this folder: `core`, `features`, `localization`, `platform`, `notifications`, `ai-services`, `testing`. `README.md` § Architecture and ownership has the resource-owner detail.
