# Apexo — Merged Security & Correctness Review

**Date:** 2026-08-09
**Source:** Consolidated from three independent engineer audits (`terry-audit.md`, `lydia-audit.md`, `dylan-audit.md`).
**Method:** Each finding was re-verified against the actual code in `lib/` before being included. False positives and duplications were removed.


## 🔴 Critical

### C1. Backend authorization does not enforce the application permission model
**Files:** `lib/utils/constants.dart` (ACCEPTED RISK, ignore for now)

The `data` collection rules allow any authenticated user to list, view, create, update, and delete almost every store:

```text
listRule/viewRule:   "@request.auth.id != \"\" || store = \"settings_global\""
create/update/delete: "@request.auth.id != \"\" && store != \"settings_global\""
```

The client-side `Perm` checks only gate the UI. A user with every permission disabled can reach PocketBase directly and read or modify all patients, appointments, notes, expenses, and attachments. The `profiles_view` collection also has empty `listRule`/`viewRule`, publicly exposing staff names, emails, and permission arrays. The relay key (`notifications_k`) lives in the same `data` collection.

**Recommendation:** Enforce authorization server-side (per-store/per-permission PB rules or a PB hook). Restrict `profiles_view`/`profiles` and the `data` collection to authorized staff. At minimum, this must be documented as a known, accepted limitation of the self-hosted single-PB model.

### C2. Patient portal data is publicly queryable
**Files:** `lib/utils/constants.dart`, `lib/services/patient_side.dart` (✅ FIXED 2026-08-10)

The `public` view has empty list/view rules and exposes every appointment's patient ID, date, prescriptions, price, paid status, and image names. The client adds a patient filter only *after* querying the public endpoint — the filter is not an authorization boundary.

**Recommendation:** Remove public list/view access; replace with a server-validated, patient-scoped, short-lived, revocable capability token. Never return the full public dataset to the client.

**Applied fix:** the `public` view is now scoped server-side to a required `pid` query param (`rulePublicPatientScoped`: `@request.query.pid != "" && pid = @request.query.pid`) — the patient ID becomes an unguessable, patient-scoped capability; requests without a matching `pid` return nothing. The patient web app sends `&pid=` alongside its existing `filter`, and `patientID` is strictly validated (`[a-zA-Z0-9_-]{1,64}`) before being used, which also caps C4's injection blast radius server-side.

**Rollout notes:** ship the updated web build first, then apply the rule (old web builds send no `pid` → would get empty results against the new rule). Applying the rule to existing clinics requires the schema-reconcile capability (see C1 discussion) or a manual update; new clinics get it at creation. Unit tests updated/passing.

### C3. Patient-side URLs are bearer credentials embedding sensitive data
**Files:** `lib/features/patients/patient_model.dart`, `lib/utils/encode.dart`, `lib/services/patient_side.dart`

`generatePatientLink()` builds:

```dart
"https://web.apexo.app/${encode("$id|$title|${login.url}|${await PushRelay.ensureKey()}")}"
```

This is reversible Base64 (not signed/encrypted) containing the patient ID, patient name, clinic URL, and the **relay key**, then submitted to a URL-shortening service. Browser history, QR photos, referrers, analytics, and logs can all disclose patient identity and a reusable credential.

**Recommendation:** Use a random, single-use, expiring, revocable server-side capability token only; store its hash server-side. Never embed names, clinic URLs, or relay credentials in the link. Rotate the relay key after rollout.

### C4. Patient-side filter input is interpolated into a PocketBase query
**File:** `lib/services/patient_side.dart` (~line 193)

`patientID` is decoded from an untrusted URL and interpolated directly into a PocketBase filter string, allowing filter-syntax injection.

**Recommendation:** Strictly validate identifiers, escape filter values, and preferably move the query behind a server endpoint that validates a capability token.

### C5. Plaintext local storage contains PHI and credentials
**Files:** `lib/core/save_local.dart`, `lib/core/observable.dart`, `lib/services/login.dart`, `lib/features/settings/settings_stores.dart`

Hive boxes are opened without encryption and contain patient/appointment JSON, clinical notes, dental charts, photo/DICOM caches, PocketBase auth tokens, AI bearer tokens, and push state. Local boxes are namespaced only by `simpleHash(login.url)`, so staff sharing a clinic share local caches, and logout retains data.

**Recommendation:** Move auth/AI credentials to OS secure storage; encrypt PHI-bearing boxes; scope data by account *and* clinic; clear or re-authorize caches on account change.

---

## 🟠 High

### H1. Infinite rebuild / setState-during-build for users with notes permission = 0
**Files:** `lib/features/notes/notes_store.dart`, `lib/features/notes/notes_screen.dart`, `lib/app/routes.dart`, `lib/core/observable.dart`

```dart
// notes_store.dart
Map<String, Note> get filtered {
  if (login.perm(Perm.notes).none && !login.isAdmin) {
    filterByAccountId(login.currentAccountID);   // state setter inside a getter
  }
  ...
}
```

`notes.filtered` is read during `build`; it fires `filterByAccountId(...)`, which notifies → `MStreamBuilder` calls `setState` → rebuild → reads `filtered` again → **infinite rebuild loop**. The `notes` route is not permission-gated, so this path is reachable.

**Fix:** Set the account filter once (in `init()` or route activation), not inside the getter, and gate the notes route on `login.perm(Perm.notes).some`.

### H2. `login.ready` completes before login restoration finishes
**Files:** `lib/core/observable.dart`, `lib/services/login.dart`, `lib/services/notifications/listeners.dart`

`ObservablePersistingObject._initialLoad()` calls `fromJson(jsonDecode(value))` **without awaiting it**, while `_LoginService.fromJson()` is `async` and runs the entire `activate()` (auth refresh, store activation, sync). Result: `login.ready` resolves while restoration is still in flight.

- `listeners.dart` does `await login.ready; if (login.token.isEmpty) return;` → **background push notifications are silently dropped on cold start** (intermittent race).
- Exceptions inside the fire-and-forget `fromJson` become unhandled async errors.

**Fix:** Make the base hook `FutureOr<void>` and `await fromJson(...)` during initial restore.

### H3. `_processChangesForSession` is not serialized — lost-update window
**File:** `lib/core/store.dart`

`_processChanges()` launches `_processChangesForSession` without awaiting or locking. Two overlapping runs can:
- both snapshot `changes` (a plain `Set`), and each run's `changes.clear()` can wipe events the other run is still pushing → a local write persists without a remote push *and* without a deferred entry → next sync sees `localVersion == remoteVersion && deferred.isEmpty` → **"nothing to sync" → silent data loss**.
- `putDeferred({}..addAll(lastDeferred)..addAll(toDefer))` is read-modify-write without a lock → concurrent runs overwrite each other's deferred entries.
- early `session != _persistenceSession` returns skip `onSyncEnd` → `networkActions.isSyncing` leaks (stale sync badge) on logout mid-save.

**Fix:** Chain `_processChangesForSession` behind a per-store `Future` mutex (single in-flight persistence pass), and always call `onSyncEnd` on exit.

### H4. `synchronize()` is a 10-second busy-wait over a single job slot
**File:** `lib/core/store.dart`

```dart
_syncJob = () async { res = await _syncRequest(session); lastRes = res; };
while (res == null && sw.elapsed.inSeconds < 10) {
  await Future.delayed(Duration(milliseconds: debounceMS));
}
return res ?? lastRes ?? [];
```

- `_syncJob` is a single slot per store. A second caller replaces the first job; the first caller blocks up to 10s and may return a stale or another store's result.
- `_syncRequest` runs `while (true)` with **no iteration cap** — pathological loop if the server keeps bumping the version.
- Every route `onSelect` fires several of these un-awaited, causing background polling storms.

**Fix:** Replace the poll-with-timeout with a `Completer`/shared-future queue; cap `_syncRequest` iterations; support explicit cancellation.

### H5. Session replacement can cross-contaminate accounts or clinics
**Files:** `lib/core/store.dart`, `lib/services/login.dart`

Synchronization futures created by `_syncRequest()`/`_syncTry()` are not tracked in `_activePersistenceTasks`, so a store can replace `local`/`remote` while an older sync is still awaiting network I/O. `_syncTry()` reads mutable store fields rather than immutable session-local references. A logout or clinic switch mid-sync can cause cross-clinic writes or wrong-account data.

**Fix:** Track all sync futures during teardown; pass immutable session references through sync ops; check the session generation after every awaited operation.

### H6. Sync cursor can permanently skip remote rows
**Files:** `lib/core/save_remote.dart`, `lib/core/store.dart`

`getSince()` filters `updated > cursor` but stores only a millisecond timestamp, without an `(updated, id)` tie-breaker. Two rows updated in the same millisecond can be skipped forever.

**Fix:** Use a server-issued monotonic revision, or a compound `(updated, id)` cursor with deduplication / overlap re-read.

### H7. `synchronize()` deferred cleanup can delete entries created during sync
**File:** `lib/core/store.dart`, `_syncTry()`

The sync reads a deferred snapshot, awaits multiple network/file ops, then rewrites the shared deferred map. Entries added while it awaited can be removed by the final cleanup. `deferredPush.clearByStore()` has similar races. Note: part of this (FILE-key handling) is already mitigated by `succeededFileKeys`; the JSON/deferred-entry path remains vulnerable.

**Fix:** Operate on immutable queue-entry IDs and delete only entries successfully processed from the exact snapshot; never replace the whole current queue from an old snapshot.

### H8. Successful data writes are coupled to push delivery
**File:** `lib/core/store.dart`

`PushRelay.sendPush(toPush)` sits inside the same `try` as `sessionRemote.put()`. If the relay is down but PocketBase is up, the catch treats it as a send failure → already-written rows go into `deferred` + `reload()`, get re-pushed (idempotent) **and** cause a second notification, plus a scary `sendingUpdatesToServer` error dialog for what is only a notification glitch. `sendPush()` also ignores HTTP status codes.

**Fix:** Treat data sync and notification delivery as separate pipelines; a push failure must never re-defer a successful data write; add retry/dead-letter for notifications.

### H9. Push-relay key creation has a race
**File:** `lib/services/notifications/push_relay.dart`

Two devices logging into a fresh clinic both see `key == null` and both `create` the same id (`notifications_k`). The loser's `create` throws with no try/catch/fallback-read → propagates into `generatePatientLink()` / `Messaging.identifyDevice()`.

**Fix:** Deduplicate key creation with an in-flight future; on duplicate, re-read the existing record.

### H10. Remote health-check timers are not disposed
**File:** `lib/core/save_remote.dart`

`SaveRemote` creates a periodic retry `Timer` in `retryConnection()` with no disposal method. `Store.endSession()` sets `remote = null` without cancelling it. Multiple retry timers can also be created in a timing window before `timer` is assigned. Old sessions can keep changing global network state after logout/session change.

**Fix:** Add `SaveRemote.dispose()`, cancel it during teardown, assign timers immediately, and generation-check callbacks.

### H11. Conflict merging cannot represent deletion and relies on client clocks
**Files:** `lib/core/store.dart`, model `toJson()` implementations

Models omit empty/default fields, so clearing maps/fields removes them from JSON rather than recording an explicit deletion. The two-way field merge cannot distinguish "never set" from "explicitly cleared," so deleted tooth notes/drawings can be resurrected. Conflict winners are chosen by comparing local device timestamps against server timestamps, so clock skew can select the wrong winner.

**Fix:** Introduce per-key tombstones / nullable serialization / base revision, or use whole-map LWW for deletion-sensitive fields; prefer server-issued revisions with a deterministic tie-breaker.

### H12. Old `SaveRemote` retry timers survive session changes
**Files:** `lib/core/save_remote.dart`, `lib/core/store.dart`
Same root cause as H10 — call `dispose()` during `endSession`/deactivation.

### H13. Image & DICOM caches are not scoped by clinic/row/session
**Files:** `lib/utils/imgs.dart`, `lib/services/dicom/dicom_lru.dart`, `lib/services/dicom/dicom_file_cache.dart`

The in-memory image cache is keyed only by filename; native disk files use a shared directory; DICOM originals/metadata use app-wide names. The same filename can return a previous patient's or clinic's image. Logout/clinic switches do not clear or namespace them.

**Fix:** Key caches by server/clinic + row ID + filename + thumb state; clear memory and disk caches on clinic switch/logout; namespace DICOM caches by clinic identity.

### H14. Image retrieval is coupled to the appointments store
**File:** `lib/utils/imgs.dart`

`_getImage()` / `downloadFile()` resolve remote files through `appointments.remote!` even when the image belongs to notes or expenses — wrong-store queries or a null crash when appointments is unavailable (e.g. patient-side/offline).

**Fix:** Pass the owning `Store` (or an image repository) into file helpers; remove the global appointments dependency.

### H15. Web WebSocket auth leaks bearer tokens and transcripts into logs
**Files:** `lib/utils/ws_platform/ws_platform_web.dart`, `lib/services/g_audio_transcription.dart`

The browser WebSocket implementation moves the bearer token into a query parameter and logs the full URL and raw transcription messages. Tokens and PHI can surface in browser, network, proxy, and monitoring logs.

**Fix:** Exchange the bearer token for a short-lived single-use WebSocket ticket; never log auth URLs or raw transcript content.

### H16. Sentry and console logging are not redacted
**Files:** `lib/utils/logger.dart`, `lib/main.dart`, `lib/services/patient_side.dart`, DICOM services

`logger()` sends arbitrary exception objects/stack traces to Sentry; URLs, local paths, DICOM details, and raw transcripts are logged; release builds install an unconditional `print()` listener.

**Fix:** Add centralized `beforeSend` scrubbing for URLs, headers, credentials, record data, local paths, and user input; restrict verbose console output to debug builds.

### H17. Push notifications transmit and display clinical identifiers
**Files:** `lib/features/notes/notes_model.dart`, `lib/features/appointments/appointment_model.dart`, `lib/core/store.dart`, `lib/services/notifications/model_push_data.dart`

Push payloads contain readable titles, updated field names, old/new values, comments, and attachment metadata, traveling through the relay/FCM and appearing on lock screens.

**Fix:** Send only an opaque event ID, record ID, and type; fetch authorized details after app unlock.

### H18. Personal-patient permission rule can expose another operator's patients
**File:** `lib/features/patients/patient_model.dart`

`Patient.locked` bases its check on `allAppointments`, which already filters locked appointments. Patients who only have another operator's appointments can appear unlocked.

**Fix:** Compute visibility from the unfiltered appointment index, then apply the same rule at the write boundary/server.

### H19. Password reset fails for normal users and can report failure after superuser success
**File:** `lib/features/login/login_controller.dart`

The first superuser-reset exception aborts the normal-user reset; a successful superuser reset followed by a normal-user failure is shown as failure.

**Fix:** Attempt both independently; return generic success if either succeeds (no account enumeration).

### H20. Receipt scanning has a fixed-delay race
**File:** `lib/features/expenses/scan_receipt_dialog.dart`

Upload waits 500 ms after `expenses.set()` and assumes the remote record exists.

**Fix:** Await an explicit remote-persistence barrier or keep a retryable pending-upload state; never use a timing delay as a sync mechanism.

### H21. `deferredPush.reset()` cannot safely reinitialize
**File:** `lib/services/notifications/push_deferring.dart`

`hiveBox` is `late final`, but `reset()` sets `_initialized = false`; a later `init()` attempts to assign the same `late final` field again → `LateInitializationError` after logout + re-login.

**Fix:** Make the box future replaceable/nullable and await/close the old box before switching sessions.

### H22. `version.init()` runs twice
**File:** `lib/services/version.dart`, `lib/app/app.dart`

`init()` is called in the constructor and again by `showDialogsIfNeeded()` → duplicate metadata requests and possible races.

**Fix:** Expose one idempotent initialization future.

### H23. Web-reachable files import `dart:io` directly
**Files:** `lib/utils/imgs.dart`, `lib/services/ai_services/dental_history.dart`, `lib/services/ai_services/post_op_notes.dart`, `lib/services/notifications/core_notifications_initializer.dart`, `lib/services/notifications/listeners.dart`, `lib/services/notifications/static_notifications.dart`, `lib/services/version.dart`, `lib/app/app.dart`

A runtime `kIsWeb` check does not make an unconditional `dart:io` import portable.

**Fix:** Move native file/platform functionality behind conditional facades.

---

## 🟡 Medium

### M1. Wrong route identifier → notification "View" button is a no-op
**File:** `lib/services/notifications/static_notifications.dart`

`routes.navigate("appointments")` but the route is registered as `"calendar"`. `navigate()` silently no-ops on unknown ids.

**Fix:** Use `routes.navigate("calendar")` (or centralize route identifiers as constants).

### M2. Unknown account IDs display the first admin's name
**File:** `lib/features/accounts/accounts_controller.dart`

When an operator ID no longer exists, `nameOrEmailFromID()` returns the first admin/account's name, so a deleted operator looks like a different (admin) staff member.

**Fix:** Return a localized "Unknown account" plus the raw ID.

### M3. `ObservableState.call()` always notifies, even when the value is unchanged
**File:** `lib/core/observable.dart`

```dart
if (newValue != null) { _value = newValue; notifyObservers(_value); }
```

No equality check → redundant events, rebuild churn, and is the root cause enabling H1. Combined with `MStreamBuilder` (rebuilds on every event, no dedup).

**Fix:** Compare values before notifying, with an explicit opt-in for intentionally repeated events.

### M4. `GlobalSettings` creates a `SaveRemote` even in demo mode
**File:** `lib/features/settings/settings_stores.dart`

Unlike other stores, `globalSettings` doesn't guard `if (launch.isDemo)`, so in demo mode it builds a `SaveRemote` against an empty `login.pb`, starting a 5-second `retryConnection` timer that runs forever.

**Fix:** Keep demo mode entirely local, matching the other stores.

### M5. Model parsing is fragile / one bad row aborts a whole store
**Files:** `lib/features/appointments/appointment_model.dart`, `lib/features/expenses/expense_model.dart`, `lib/features/notes/notes_model.dart`, `lib/services/patient_side.dart`

`double.parse(...)`, `as int?`, direct boolean casts, and unchecked list/map shapes. A corrupted/edited remote row throws during `deleteMemoryAndLoadFromPersistence` and the whole store fails to load.

**Fix:** Centralize tolerant JSON helpers (`readBool`, `readInt`, `readDouble`, `readStringList`) and isolate malformed records instead of failing the store.

### M6. Deferred file operations use delimiter-encoded keys
**File:** `lib/core/store.dart`

Paths/filenames are encoded with `||`; a valid value containing that delimiter becomes malformed and can be discarded. Note: key-shape validation was already added (`isValidDeferredFileKey`) — the encoding scheme itself remains fragile.

**Fix:** Use structured JSON queue records with opaque IDs.

### M7. Conflict timestamps use unrelated clocks
**Files:** `lib/core/store.dart`, `lib/core/save_remote.dart`
Local-deferred timestamps use the device clock; remote timestamps use the PB server clock. (Overlaps H11.)

**Fix:** Server-issued monotonic revision or server time plus a deterministic tie-breaker.

### M8. `Appointment.fromJson` can crash on malformed/corrupt remote data
**File:** `lib/features/appointments/appointment_model.dart`
Fold into M5.

### M9. Network calls generally lack timeouts and response limits
Affected: AI, receipt scanning, image downloads, patient-side activation, QR processing, version checks, relay calls. Requests can hang or consume excessive memory.

**Fix:** Shared HTTP-client policy: timeouts, max response size, status validation, cancellation for UI-bound work.

### M10. Remote/blob file downloads accept HTTP error bodies as images
**Files:** `lib/core/store.dart`, `lib/core/save_remote.dart`

**Fix:** Validate 2xx status, MIME/signature, and bounded size before uploading/accepting.

### M11. AI endpoint contract inconsistent with repository guidance
**Files:** `lib/services/ai_services/receipt_scanner.dart`, `.github/instructions/ai-services.instructions.md`

Implementation calls `/expense` (instructions say `/receipt-scanner`); instructions describe post-op notes as JSON while the implementation sends multipart audio.

**Fix:** Verify the deployed Worker contract and add a versioned integration test; keep instructions in sync.

### M12. Backup download URLs are bearer secrets
**File:** `lib/services/backups.dart`, backup settings UI

`downloadUri()` returns a tokenized URL exposed directly to the user; should not be logged/persisted/shared.

**Fix:** Prefer a direct authenticated download or a short-lived one-time URL with clear handling.

### M13. S3/SMTP credentials persisted as plaintext server settings
**Files:** `lib/features/settings/services_settings/s3_settings.dart`, `smtp_settings.dart`, `lib/features/settings/settings_stores.dart`

Stored in the `settings_global` data record, unencrypted, exposed to anyone who can read that store under current rules.

**Fix:** Store secrets in a protected server-side mechanism; never return secrets to ordinary clients after saving.

### M14. `nameOrEmailFromID` / client-side claims
See M2 (deduplicated).

### M15. Statistics default month range is wrong
**File:** `lib/features/stats/charts_controller.dart`

"End of month" is first-day + 31 days, including next-month data for 30/31-day and February months.

**Fix:** Use an exclusive next-month boundary or the actual last day at `23:59:59.999`.

### M16. Logout discards unsaved panels
**Files:** `lib/services/login.dart`, `lib/app/panel_widget.dart`

Logout clears `routes.panels([])` without checking unsaved changes.

**Fix:** Centralize logout through an unsaved-change confirmation.

### M17. Panel result futures remain pending on cancel
**Files:** `lib/app/routes.dart`, `lib/app/panel_widget.dart`, `lib/features/appointments/open_appointment_panel.dart`

`Panel.result` completes only after save; cancel/close leaves it pending forever, stalling `await`-based flows (e.g. opening a new patient from an appointment).

**Fix:** Make the result nullable and complete it with `null` on cancellation.

### M18. DICOM auto-import toggle does not immediately control the timer
**Files:** `lib/features/dicom/dicom_auto_import_toggle.dart`, `lib/features/dicom/dicom_controller.dart`

Changing the setting only updates it; it doesn't immediately start/stop the periodic scan.

**Fix:** Route all config changes through a controller method that stops then conditionally starts the timer.

### M19. DICOM viewer deletion does not reuse gallery permissions
**File:** `lib/features/dicom/open_dicom_viewer_panel.dart`

**Fix:** Gate deletion with the same `Perm.photos`/admin predicate as the gallery, and enforce server-side.

### M20. Notes permission checks are inconsistent
**Files:** `lib/features/notes/note_card_widget.dart`, `lib/features/notes/kanban_column_widget.dart`

Some controls honor `canEdit`, but drag-and-drop, completion changes, and some bulk mutations remain available. `DragTarget.onAcceptWithDetails` changes `columnID` without checks.

**Fix:** Put all note mutations behind one permission predicate.

### M21. Labwork "not delivered" / completion uses the wrong appointment / permission
**Files:** `lib/features/labwork/labworks_ctrl.dart`, `lib/features/labwork/labworks_screen.dart`

Uses `p.allAppointments.last` (may be a future appointment) instead of `doneAppointments.last`; the "received" checkbox allows any assigned operator while editing needs post-op permission.

**Fix:** Base delivery on the latest completed appointment; use one canonical `canEditLabwork` policy and enforce it server-side.

### M22. Patient age calculation is birthday-insensitive
**File:** `lib/features/patients/patient_model.dart`

`DateTime.now().year - birth` is off by one before the birthday.

**Fix:** Store full birth date or keep year-only semantics consistently for age-sensitive dental logic.

### M23. Dashboard/appointment caches become stale at midnight/month rollover
**Files:** `lib/features/appointments/appointments_store.dart`, `lib/features/dashboard/dashboard_controller.dart`

Today/month caches are invalidated only by mutations, not time boundaries.

**Fix:** Add a date-boundary timer or a clock/today observable used by derived caches.

### M24. Patient derived labels/search/sort cache becomes stale after language/appointment changes
**File:** `lib/features/patients/patient_model.dart`

`tableLabels`/`searchString` are cached and invalidated only on `fromJson` or appointment events — after switching language, the table shows old-language labels until another appointment change.

**Fix:** Invalidate locale-dependent caches on locale change; centralize derived-data invalidation.

### M25. DICOM search listener is not removed correctly
**File:** `lib/features/dicom/dicom_screen.dart`

Listener added with one anonymous closure, removed with a different one → original listener stays registered.

**Fix:** Store the callback in a field and remove that exact instance.

### M26. Backup operation flags can remain stuck
**File:** `lib/services/backups.dart`

`creating`/`deleting`/`uploading`/`restoring` reset only on success; exceptions leave the UI permanently busy. Restore also clears local boxes while stores may still be running.

**Fix:** Use `try/finally`; await store teardown before clearing storage.

### M27. S3 configuration conditional UI may not rebuild
**File:** `lib/features/settings/services_settings/backups_settings.dart`

The toggle is inside a `ValueListenableBuilder` but the S3 section is outside it.

**Fix:** Put the whole conditional section inside the same builder.

### M28. Account/profile operations are not transactional
**File:** `lib/features/accounts/accounts_controller.dart`

Account creation/update modifies the auth collection then the profile collection separately; a second failure leaves an orphan/partial account.

**Fix:** Server-side transaction/custom endpoint or compensating delete on failure.

### M29. Cache reset races active synchronization
**Files:** `lib/features/network_actions/network_actions_controller.dart`, `lib/features/settings/settings_screen.dart`

`resync()` invokes callbacks without awaiting; reset then clears Hive while sync may still be writing.

**Fix:** Type callbacks as `Future<void> Function()`, await them, block concurrent reset/sync, and make reset a serialized store operation.

### M30. `_notifications` and `web-images` Hive box grow unbounded
**Files:** `lib/services/notifications/static_notifications.dart`, `lib/utils/imgs.dart`
Bell badge count inflates all session; web image box never evicts.

**Fix:** Bound/expire entries.

### M31. `locale.list[selectedLocale]` RangeError on out-of-range persisted index
**File:** `lib/services/localization/locale.dart`
Clamp the index.

### M32. Miscellaneous small correctness / hygiene
- `lib/app/panel_widget.dart` (~line 109): `value.logicalKey == controlLeft || value.logicalKey == controlLeft` — **`controlRight` duplicated**, so Ctrl+Tab with the right Ctrl doesn't work.
- `Global bContext` (`lib/app/app.dart`) used by `askForLoginAgain`/`showErrorMessage` without a `mounted` check.
- `lib/services/backups.dart` `newBackup/delete/restore/downloadUri` no try/catch.
- Real-time transcription callbacks not session-scoped (`lib/services/g_audio_transcription.dart`).
- Web FCM `setup()` registers a new `onMessage` listener each run; `registration.active` may be null; background messages dropped when state missing; click only opens `/`.
- `lib/utils/imgs.dart` `handleNewImage` does a synchronous `File.lastModifiedSync()` on the UI thread; filename inputs need path-traversal sanitization (reject separators, `..`, empty, oversized).
- File-path inputs generally need explicit sanitization (M12 in Lydia).

### M33. Localization gaps (Greek/Persian)
- `lib/main.dart` / `lib/services/localization/locale.dart`: locale list includes Greek (`el`) and Persian (`fa`), but `initializeDateFormatting` runs only for `en`/`ar`/`es` → missing date data for Greek/Persian; `locale.s`/`list[selectedLocale]` path has the RangeError above.
- `lib/services/notifications/model_push_data.dart` (`_Langs`) and `web/fcm/push_data.js`: any locale other than en/ar maps to Spanish → **Greek and Farsi users receive Spanish push text**.
- `lib/features/network_actions/network_actions_controller.dart`: `tooltip: "Theme"` hardcoded English.
- `lib/services/notifications/listeners.dart`: `label: 'View'` hardcoded in `_addStaticNotification`.

**Fix:** Register/initialize every locale (or initialize lazily); add `el`/`fa` push translations in both Dart and JS; route all UI strings through `txt()`.

### M34. `Txt` does not localize its input
**File:** `lib/services/localization/locale.dart`

`Txt` renders `data` directly and does not call `txt(data)`, so `const Txt('No data found')` stays untranslated — the cause of the widespread `Txt(txt("key"))` double-translation pattern.

**Fix:** Choose one contract — translate internally, or rename to `ReactiveText` and require pre-translated strings. Don't mix both.

### M35. Several localization calls use display text as dictionary keys
Examples: `txt("Monday")` while keys are lowercase; `Txt(txt("${txt("admins")}: ${admins.length}"))`; chart placeholders like `Txt('No data found')`.

**Fix:** Use stable keys and formatted translation templates with parameters.

### M36. Dead code / cleanup
- `RowToWriteRemotely.store` (`lib/core/save_remote.dart`) is never used.
- `Panel.storeSingularName` (`lib/app/routes.dart`) unused; would null-deref `store.local!` before login.
- `login.authenticateWithToken(token)` parameter unused.
- Store activator boilerplate copy-pasted across 5 stores — a `StoreMixin`/base class would reduce drift (likely how M4 happened).
- `_processChangesForSession`: `if (isDemo == true) notify();` fires a full view-notify on every change batch in demo mode.

### M37. Platform / deployment hardening
- **Mobile backup export:** Hive data is in app-documents storage; `android/app/src/main/AndroidManifest.xml` has no backup exclusion → auto-backup can export unencrypted clinic data. Fix: exclude sensitive stores from Android Auto Backup and iOS iCloud/device backup.
- **iOS push entitlement:** `ios/Runner/Runner.entitlements` uses development APNs — use configuration-specific entitlements so Release/TestFlight get production APNs.
- **macOS release:** `macos/Runner/Release.entitlements` weakens Hardened Runtime (`allow-unsigned-executable-memory`, `disable-library-validation`) — remove unless a verified signed dependency needs them.
- **HTTP endpoints:** arbitrary non-HTTPS PocketBase endpoints accepted (`login_controller.dart`, `login.dart`) and patient-side requests lack HTTPS/timeout/status/MIME/size/schema validation. Reject HTTP by default except explicit localhost/dev exceptions.
- **`web/_headers`:** only COOP/COEP set — add CSP, `Referrer-Policy: no-referrer`, `Permissions-Policy`, HSTS.

---

## ✅ Checked and OK

- Timers (audio recorder, panel, timeline, labwork, slideshow, DICOM periodic scan) are all cancelled in `dispose`.
- `labworks.notDeliveredPatients` guards `allAppointments.isNotEmpty` before `.last`.
- `Appointment.fromJson(super.json) : super.fromJson()` is valid (super-parameter forwarding).
- `getCountryCode()` always returns a 2-char code or `"US"`, so `isoCC()`'s `substring(0,2)` is safe.
- Field-level `mergeConflict` is well-tested; the documented tombstone limitation is the (high) H11 rather than a hidden desync.
- `TaskQueue` handles concurrent `add()` correctly (sync `_isProcessing` guard).
- The `_uploadsInFlight` in-flight guard correctly dedupes concurrent identical uploads.
- DELIMITER-key deferred-file malformed/negative-retry keys are now guarded by `isValidDeferredFileKey`.
- `getCountryCode`/`isoCC` and several other edge paths are safe.
- DICOM import includes cancellation, cache-aware scanning, and stale-file safeguards.

---

## Recommended remediation order

1. **C1, C2, C3, C4** — Lock down PocketBase rules; remove public appointment/profile exposure; replace the patient-link scheme with scoped capability tokens and rotate the relay key. (Highest business/security impact.)
2. **C5** — Encrypt and scope local storage; move auth/AI credentials to secure storage.
3. **H3, H4, H7** — Serialize store persistence/deferred sync; fix the incremental cursor; make `synchronize()` use a proper queue.
4. **H2, H5, H10, H12** — Fix the `login.ready` race and session teardown; dispose `SaveRemote` timers.
5. **H1** — Fix the notes permission=0 rebuild loop.
6. **H8, H9, H17** — Decouple push from data write; fix key-creation race; minimize push payloads.
7. **H13–H16** — Scope image/DICOM caches; fix web WebSocket auth leakage; add telemetry/log redaction.
8. **M-level business-rule defects** — personal patients (H18), password reset (H19), receipts race (H20), stats range (M15), labwork permissions (M21), panel cancel (M17), unsaved-logout (M16), DICOM auto-import (M18).
9. **M33–M35** — Complete localization (Greek/Persian), fix `Txt`, remove double translation.
10. **M5–M12** — Harden model parsing, HTTP timeouts, response validation, backup flags, account transactions.
11. **M37** — Backup exclusions, production APNs entitlement, macOS entitlement cleanup, HTTP hardening, web headers/CSP.

## Suggested regression tests

- Session switching during an active sync (H5).
- Concurrent offline edits / deferred queue cleanup (H3, H7).
- Portal authorization and filter injection (C2, C4).
- Cache isolation across clinics (H13).
- Panel cancellation (M17).
- Permission-zero notes users (H1).
- Greek/Persian localization (M33).
- `deferredPush.reset()` re-login (H21).
- `version.init()` idempotency (H22).
