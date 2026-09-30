# End-to-end test backlog

Every test we still owe this app, as a checklist. Written 2026-09-21, updated for the
standard test shape.

> ## ⚠️ Read this first: the suite is older than the tree (2026-09-28)
>
> Most of the "**Verified green**" lines below were measured against the
> **localpocket-migration branch**, not against this tree. Commit `af8e771`
> (2026-09-27) rolled that migration back and its message lists what it did *not*
> keep — `lib/core/db/**`, the per-feature `store/**`, `lib/app/panels/**` **and the
> integration_test suite** ("both written against the new panel UI"). `ef3a3fd`
> brought the suite back "minus the parts that test the migration itself" and said
> so itself: *"its finders were written against widgets the migration re-keyed in
> places … this is a restoration of the code, not a claim that every group passes."*
>
> So the tick marks and pass counts below describe a shape of the app that is not in
> this working tree. Read them as "this test exists and was green somewhere", never
> as "this test passes here". Measured 2026-09-28: **52 widget keys the suite waits
> for were declared in `lib/widget_keys.dart` and attached to nothing in `lib/`**,
> which is what made `Fixtures.openRoute` time out after a nav tap that had landed
> (it was never the routing refactor, and never fluent — see §6.1). **All 52 are
> attached now**: `pwsh -File tools/key_audit.ps1` reports zero keys the suite waits
> for that the app does not attach (28 handles remain declared and unused, §0.2) —
> and the rollback had also dropped the migration branch's *bug fixes*, so the
> restored suite keeps re-finding bugs §6.1 says were fixed: re-applied and
> re-measured below.
>
> What is true *here*, measured 2026-09-28 unless the row says otherwise (the 2026-09-30 re-measures
> are the rows whose result line ends in `All tests passed!` or that say "re-measured"):
>
> | Group | Command (all `pwsh -File tools/run_e2e.ps1 -Group <name>`) | Result |
> | --- | --- | --- |
> | `login` | `-Group login` | **`+12 ~3: All tests passed!`** (2026-09-28) — **RED on 2026-09-30 on
>   this tree: `+8 ~3` and the run ended abnormally, with `09` (`proceeding offline reaches the
>   shell`), `10` (`the password reset email is sent`), `12` (`the first-launch dialog is shown on
>   an empty server`), `13` (`the changelog dialog is shown on a fresh install`) all reported as
>   *did not complete* plus `(tearDownAll) - did not complete`.** The four unaffected tests are
>   `01`–`08`, so the run died at `09` and never reached `10`/`12`/`13`; `- did not complete` means
>   the test never reported, usually because the app or the test process died under it. It also
>   left its children holding `build/` (see the readme's four load-failure signatures).
>   Being re-measured after the build was repaired; the row below is updated from the log of that
>   run, not from this one.
> | `lifecycle_platform` | | **`+8 ~1`** |
> | `accounts` | | **`+8 ~2`** |
> | `patients` | | **`+13 ~2`** (measured 2026-09-28, before the §6.1 fixes) |
> | `dashboard` | | **`+5 ~2`** (measured 2026-09-28, before the §6.1 fixes) |
> | `calendar` | | **`+7 ~1`** (measured 2026-09-28, before the §6.1 fixes) |
> | `appointments` | | **`+14 ~1: All tests passed!`** — was `+11 ~1 -3`; §6.1's archive-panel,
>   flyout-header and multiline-tag-field fixes are what `11`, `12` and `14` were |
> | `patient_panel` | | **`+7 ~2`** (re-measured with the §6.1 fixes; was `+6 ~2 -1`) |
> | `notes` | | **`+7 ~1`** |
> | `expenses` | | **`+7 ~1`** |
> | `insights` | | **`+3 ~2`** |
> | `deleted_items` | | **`+2`** |
> | `accessibility` | | **`+4`** |
> | `upgrade` | | **`+4`** (re-measured) |
> | `tooth_chart` | | **`+3 ~2`** (re-measured; was `+1 ~2 -2`) |
> | `settings_general` | | **`+4 ~4: All tests passed!`** (was `+0 ~4 -4`) |
> | `sync_offline` | | **`+6 ~1: All tests passed!`** (was `+4 ~1 -2`: both failures were the
>   harness's — §1.6 and §6.3) |
> | `localization_rtl` | | **`+5 ~1: All tests passed!`** (first measurement on this tree) |
> | `settings_services` | | **`+5 ~1: All tests passed!`** (first measurement on this tree — it
>   was key-blocked until §0.2 was finished) |
> | `backups` | | **`+3 ~4: All tests passed!`** (first measurement here; `04` needed the cron
>   key moved onto the preset `ComboBox` — §2.11) |
> | `labworks` | | `~8` (every test skipped by design, §2.2) |
> | `errors_and_recovery` | | **`+1 ~3: All tests passed!`** (re-measured; `02` is the real test) |
> | `patient_portal` | | **`+6 ~1: All tests passed!`** (re-measured) |
>
> Two traps when reading rows in this file. **A stale log**: `pwsh -File tools/run_e2e.ps1 -Group x`
> and `pwsh -File tools/run_e2e_groups.ps1 -Groups x` both write `tmp/run_x.log`, so a log that
> looks like a fresh result can be days old — check `LastWriteTime` before believing a number (a
> stale `run_patients.log` reading `+13 ~2: All tests passed!` is what produced the bad
> "re-measured 2026-09-30" marks below, now corrected). **A batch**: once a stray process has
> broken the build, *every* group in the batch reports `+0 -1: Some tests failed`, which is one
> infrastructure problem, not twenty-five broken groups.
>
> **Why twelve groups are still unmeasured (2026-09-30).** Not the tests: the Windows build.
> `login 09` left a `cmake` holding `build/`, every later group failed to build, `flutter clean` was
> run, and the rebuild then had to re-fetch the Firebase C++ SDK — **957,230,645 bytes**, which this
> connection cannot hold: it truncated at 423,796,736 bytes (44%) the first time and, on retry, reset
> mid-transfer (`curl: (56) Recv failure: Connection was reset`, then `Could not resolve host:
> dl.google.com`), at throughput between 19 and 600 kB/s. **No e2e group can run until that archive
> is complete**, because `firebase_core`'s CMake needs it for every Windows build of this app, and no
> copy of it — complete archive or extracted SDK — exists anywhere on this machine (searched).
> Ten parallel range requests *made it worse*: each connection reset makes `curl --retry` restart its
> part from zero, so four hours of trying left ten 0-byte parts and nothing else, while a single
> resumable connection (`curl -C -`) can only ever move forward. That is what is running now.
> **If you are reading this with a working connection, the unblock is one command:** fetch
> `https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_windows_13.5.0.zip` (957,230,645 bytes)
> to `build/windows/x64/firebase_cpp_sdk_windows_13.5.0.zip`, delete
> `build/windows/x64/extracted` if it exists, and run the groups. Nothing about the twelve rows above
> is a claim that those groups fail — they are simply not measured on this tree since the §6.1
> fixes, and must not be read as green either.
>
> Everything else is **unmeasured** on this tree as of 2026-09-30 (`perf_budgets`, `dicom` —
> the DICOM group needs a clean process table, see the readme's "All of them"). The groups that were red when this part of the
> work started (`lifecycle_platform` `+3 ~1 -5`, `login` `+8 ~3 -4`, `accounts` `+2 ~2 -6`,
> and the ones blocked by the unattached keys of §0.2) got there for one of two reasons: a
> widget key the rollback left attached to nothing, or a real app bug (§6.1) — **including
> the migration branch's own fixes, which the rollback dropped with the UI**. Two minutes
> with `pwsh -File tools/key_audit.ps1` tells the difference: it now reports **zero** keys
> the suite waits for that the app does not attach (28 declared-and-unused handles remain,
> listed in §0.2), so a timeout from here on is about the screen, not about a handle.
>
> The rows above are *individual* runs, and this suite is order-dependent by design (a
> group's tests are written to run in registration order after the ones before them). A
> green single group is "this group passes alone on this tree", never "the whole suite is
> green" — only `pwsh -File tools/run_e2e.ps1` with no `-Group` says that. The rows measured on
> 2026-09-30 (`appointments`, `patient_panel`, `upgrade`, `tooth_chart`, `settings_general`,
> `sync_offline`, `localization_rtl`, `settings_services`, `backups`, `labworks`,
> `errors_and_recovery`, `patient_portal`) are current; the rest (`lifecycle_platform`, `accounts`,
> `patients`, `dashboard`, `calendar`, `notes`, `expenses`, `insights`, `deleted_items`,
> `accessibility`) were measured on 2026-09-28, **before** the §6.1 fixes landed, so read them as a
> floor — a fix can only turn a failure into a pass, and none of them has been re-run since.

Run them with `pwsh -File tools/run_e2e.ps1`, one group at a time with
`-Group patients`, or one test with `-Group "04:"`.

How to read an entry: the quoted name is the `testWidgets` name to use **without** any
trailing marker, inside that group's `group('…')`. A `/` in a name means one test per
platform or per variant.

The two old harness markers still appear as **authoring hints only**:

| marker | used to mean | now means |
| --- | --- | --- |
| `++` | "later tests need this one to have run" | nothing at runtime — a hint that this test is the one to write first. Order-dependence is no longer expressed anywhere: every test boots the app itself and says `E2E.signIn` when it needs a session. |
| `--` | "skipped unless the run asked for `all`" | write it with the standard `skip:` argument (a reason string, so the report says why). |

Order of work: **§0 first** (without fixtures nothing below can be written honestly),
then the P0 groups, then P1, then P2.

---

## §0. Foundations to build before the groups

Not tests — the things the tests need. Each one is a prerequisite for a whole block.

### 0.1 Fixtures and cleanup (`integration_test/support/fixtures.dart`)

- [x] `Fixtures` exists: `stamp()`, `openRoute/openPatients/openCalendar`,
      `openNewPatientPanel`, `createPatient`, `openPatient`, `save/waitForSaveState/canSave`,
      `closePanel`, `confirmFlyout`, `pickTag`, `fieldText`.
- [ ] `Fixtures.seedAppointment(...)` — needs the appointment panel's patient picker solved
      first (§6); then `seedLabwork`, `seedExpense`, `seedNote`.
- [ ] `Fixtures.seedBaseline()` — the 3 patients / 5 appointments / 1 labwork / 1 expense /
      1 note set the read-only groups (dashboard, insights, calendar counts) assert on.
- [ ] `Fixtures.deleteEverything()` — before a run that needs a known starting point.
- [x] Storage agreed: the UI for the record under test, `Backend` for anything bulk.
      `Backend.resetState()` already gives every run an empty server **and** an empty local
      database (see §6 — it used to leave the local database behind).

### 0.2 Widget keys to add

Many screens have no keys at all, so their tests would be written against text or types
and would break on every copy change. Needed before the matching group:

**Audited 2026-09-28** (`pwsh -File tools/key_audit.ps1`, 127 keys declared): **52 keys the
suite waits for were declared in `lib/widget_keys.dart` and attached to nothing in
`lib/`** — the rollback note at the top of this file is why. **All 52 are attached again**
(measured the same day: the audit reports **0** keys the suite waits for and the app does
not attach; 28 handles remain declared and unused, which are dead weight, not blockers).

- [x] Shared panel chrome: `WK.panelSave`, `WK.panelClose`, `WK.panelArchive`.
- [x] Lists: `WK.listSearch` (`TopSearch`'s `CupertinoTextField`), `WK.showMore`
      (`ShowMoreBar`'s button); patients: `WK.btnNewPatient`.
- [x] The `open*` helpers' ready-finders, which gate whole groups:
      `WK.btnNewPatient`, `WK.btnNewAppointment`, `WK.btnNewAccount` / `WK.btnNewAdmin`,
      `WK.btnNewSupplier`, `WK.btnNewLabwork`, `WK.btnNewNote` (these six screens' command
      bars), and the shell's `WK.globalAction(id)` (`NetworkAction.identifier`:
      `notifications` / `theme` / `sync` / `errors`).
- [x] The account panel's own handles: `WK.fieldAccountName`, `WK.fieldAccountEmail`,
      `WK.fieldAccountPassword`, `WK.accountOperates` (the `Checkbox`, not a switch in this
      tree) and `WK.permissionSelector(titleKey)` per permission row.
- [x] The settings screen: `WK.settingsList` (its `ListView`), `WK.settingsItem(identifier)`
      (the card's `Expander` — the box whose *height* says whether the card is open, which
      is how `revealSettingsCard` decides), and the six services sections with their fields
      (`WK.serviceSection(id)`, `WK.serviceField(id)`, `WK.backupRow(key)`).
- [x] The calendar's day cells (`WK.calendarDay`, `WK.calendarSelected`, `WK.calendarToday`,
      `WK.calendarDayCount`), the dashboard's squares and counts, the notes board
      (`WK.notesBoard`, `WK.columnRoot`, `WK.columnHeader`, its add buttons and the card's
      inline saves), the expenses order row, the DICOM screen's six handles, and the labwork
      editor's three fields.
- [ ] A row key per record for the lists that lack one — appointments, labworks, expenses,
      notes, accounts, archived (patients uses `ValueKey(patient.id)` already).
- [ ] Toasts/InfoBars the tests wait for (success *and* failure variants).
- [ ] Teeth chart: one key per tooth (the semantics offset bug below needs this anyway) —
      `WK.tooth` is attached; the *other* half, a key per condition, is not.
- [ ] The 28 declared-but-unused handles (`acDate`, `calendarDayButton`, `loginScreen`,
      `settingsScreen`, …): either attach them where a test will want them, or delete them —
      a declared key that nothing draws is how this whole section started.

### 0.3 Helpers still missing in `support/e2e.dart`

- [x] `boot`, `signIn`, `waitFor`, `waitForGone`, `tap`, `tapFirst`, `settle`,
      `dismissStartupDialogs`, `enterCredentials`, `resetState`.
- [x] `Fixtures.waitForSaveState` (the panel publishes its dirty state from a 750ms timer,
      so reading it straight after a keystroke is a race — this was the flakiest thing here).
- [ ] `E2E.readText(finder)` — read a widget's current text (for asserting counts like
      "Showing 10/14").
- [ ] `E2E.expectEventually(tester, finder, matcher)` — assert that a value becomes right
      within N seconds.
- [ ] `E2E.setLocale(...)` / `E2E.setTheme(...)` — drive the settings the flows depend on.
- [ ] `E2E.screenshot(name)` — capture on failure (web + Android only; native desktop has
      no integration_test screenshot support).
- [ ] `E2E.acceptUnsavedChanges()` / `E2E.discardDraft()` — the panel-close dialog, so the
      panel tests do not each re-implement it.

### 0.4 Web logins — **done**

The app's local database (localpocket: worker + `sqlite3.wasm` + OPFS) does not open without
cross-origin isolation, and the dev server `flutter drive` starts does not send the headers:
the login screen reported `localDatabaseFailed`.

- [x] **Headers.** `flutter drive` *does* accept `--web-header` (it forwards `flutter run`
      options), so no proxy is needed. `tools/run_e2e.ps1` now passes
      `-WebHeaders` → `--web-header=Cross-Origin-Opener-Policy=same-origin` and
      `--web-header=Cross-Origin-Embedder-Policy=require-corp`. With them the worker spawns,
      the OPFS database opens and reads/writes round-trip in headless Chrome.
- [x] **Verification.** `integration_test/web_open_test.dart` opens the database with the
      `login.dart` store list and round-trips a record — the smallest test that covers the
      handshake:
      `pwsh -File tools/run_e2e.ps1 -Target web -Entry integration_test/web_open_test.dart -WebHeaders`.
      Green in headless Chrome.
      `test/unit/core/db/schema_wire_manifest_test.dart` guards the same handshake without a
      browser: the wire form plus the store-policy envelope must fingerprint identically to
      the page's full definition.
      The `login` group runs on web too (4 tests, real backend, the DB opened by the login
      itself): `pwsh -File tools/run_e2e.ps1 -Target web -Group login -WebHeaders -Headless` →
      `All tests passed.` It is selected through `--dart-define=E2E_GROUP=login` (see
      `e2e_test.dart`), because `flutter drive` cannot filter by test name.
- [x] Re-ran on web against the **stock** worker (no patched build): `web_open_test.dart` and the
      `login` group both `All tests passed.` The login group is the one that also covers the
      single-instance claim, since it claims before opening.
- [ ] Run the **whole** `e2e_test.dart` on web with `-WebHeaders` (possible now; not done
      yet — the group define covers the flows that need a browser today), and keep
      `E2E.resetState()` failing loudly when it cannot reach the backend, so a web run never
      reports a pass it did not earn.

---

## §1. P0 — the money paths

### 1.1 `login` — **done** (`groups/login.dart`, 12 pass / 3 skip)

**Verified green: `+12 ~3: All tests passed!`** — re-measured 2026-09-28 on this tree, in 1m48s
(`pwsh -File tools/run_e2e.ps1 -Group login`). It read `+8 ~3 -4` here before that date
(`08`, `09`, `12`, `13` red), and each of the four was a real app bug the rollback restored —
the clear button not emptying the form (`08`), an offline login never setting
`proceededOffline` (`09`), the first-launch dialog being unreachable because nothing
re-checked `isFirstLaunch` after the login that sets it (`12`, a 180s wait), and `13` as a
consequence of `12`'s leaked dialog. All three fixes are in §6.1. The header here used to
say "10 pass / 3 skip", which was the count before `05`–`13` were written.

- [x] `01: the login screen is shown`
- [x] `02: a server that is not there is reported`
- [x] `03: signing in reaches the dashboard`
- [x] `04: logging out returns to the login screen`
- [x] `05: a wrong password is reported` — real server, bad password → the app's own words for
      PocketBase's `400`, and no session started.
- [x] `06: the server URL is normalised` — `$server///` + `  SHOUTY@EMAIL  ` → the login succeeds and
      the app holds the trimmed pair. (`loginButton` strips the slashes, trims + lowercases the email.)
- [x] `07: the language can be switched from the login screen` — en → ar → en through the screen's own
      picker, with the labels following it (`login` *and* `resetPassword` are translated).
- [x] `08: clearing credentials empties the form` — the clear button appears only when url/email are
      set, and it now empties the **fields** too (§6.1).
- [x] `09: proceeding offline reaches the shell` — a failed login offers `WK.btnProceedOffline`; the
      offline session reaches the shell, knows it is offline (the shell's sync action is disabled, §6.1)
      and reads the clinic's local rows. §6.2 has the permission question this uncovered.
- [x] `10: the password reset email is sent` — `WK.btnResetPassword` → `WK.msgSentReset`, against an
      address with no account: PocketBase answers `204` either way (measured), so nothing is mailed and
      the app's success path is what runs.
- [ ] `11: the session survives a restart` — **skipped**: a restart is a new process, and re-pumping
      the tree keeps every singleton (including `login`) in memory, so it would prove nothing. The
      restore is exercised by every boot (`E2E.boot` waits on `login.ready`).
- [x] `12: the first-launch dialog is shown on an empty server` — the collections are dropped
      (`Backend.dropCollections`), the admin login creates them and the welcome dialog appears. It
      **could not appear before**: nothing re-checked the flag after the login that set it (§6.1).
- [x] `13: the changelog dialog is shown on a fresh install` — the first boot of the run shows it (the
      harness records what it closed: `E2E.firstBootDialogTitles`), `lastSeenVersion` is updated, and it
      does not come back on a later boot.
- [ ] `14: a second tab is refused` — **skipped**: web-only, and the harness drives one document.
      `alreadyRunningInAnotherTab` comes from `LocalPocket.claimSingleInstance`; a second *browser tab*
      is what fails it. Belongs to the web run (§4.1).
- [ ] `15: a clinic whose database is missing is told so` — **skipped** for the reason
      `errors_and_recovery 03`/`04` carry: the local database is opened once per process, so handing the
      app one it cannot read breaks every test after it (and the next run's reset).

### 1.2 `patients_crud`

- [x] `01: the patients screen renders`
- [x] `02: a patient can be created` — name, birth year, email, phone, address. Notes and
      tags are still open (see `07`/`15`).
- [x] `03: a new patient cannot be saved untouched`
- [x] `04: a phone number is stored in the E.164 form` — asserts the stored value, not the
      field: the field holds what was typed.
- [ ] `05: an invalid email is rejected` — **cannot be written**: the app has no email
      validation at all (§6.2), so there is no rule to assert.
- [x] `06: a patient can be edited and saves`
- [x] `07: closing a dirty panel asks before discarding` — the panel's `closeOrConfirmCancel`
      flyout is asserted, then dismissed.
- [x] `08: search filters the list`
- [x] `09: sort by column and toggle direction` — the direction is asserted by *row position*
      (`Fixtures.rowY`), and against the state it started in: the list already opens sorted by
      name, so the first press on the checked toggle is a direction flip, not a sort.
- [ ] `10: list and grid views both render` — **cannot be written**: there is no grid view and
      no view toggle in the screen (§6.2).
- [x] `11: show more pages through the list` — 26 patients seeded through the store (eleven
      panel round-trips is not a test), and the evidence is the page bar's own `showing N/M`
      label rather than a row that may sit on any page. No search: the screen filters the rows
      it has *loaded*, so a filter can never reach a row that is not on the page yet.
- [x] `12: archiving takes a patient out of the list` — and `13` now covers the two halves this
      item left open.
- [x] `13: an archived patient is in Deleted Items, and restorable` — the row is in Deleted
      Items, restoring it from the command bar puts it back, and it opens again. Asserted by
      *row*: `find.text(name)` also matches the copy the list's search box holds.
- [x] `14: deleting a patient that has appointments is refused or cascades` — pinned down:
      there is no delete and no cascade. Archiving leaves every appointment on its day (the
      rule is asserted through the store — see §6.2 on why the panel path is not drivable),
      and Deleted Items has no permanent-delete action.
- [ ] `15: a tag can be added from the tag input` — **skipped**, with `08: a tag is committed
      with Enter`: the tag field is not drivable (§6.2).

Result: **`patients` = 13 pass / 2 skip.**

### 1.3 `patient_panel`

- [x] `01: every tab renders` — patientDetails, dentalNotes, appointments, patientPage:
      each tab is opened by its icon (`Fixtures.tabIcons` now covers the patient panel) and
      asserted by something only that tab has.
- [x] `02: the appointments tab lists that patient's appointments only` — one card per
      visit (`WK.acSideIcons`), and the other patient's name is nowhere inside the panel
      (scoped to `PanelScreen`).
- [x] `03: the cost and paid totals match the appointments` — and the rule behind them:
      **only completed visits are billed** (`PatientAppointmentBundle.done` = not in the
      future), so a visit booked for tomorrow is priced but not counted, while today's
      (drawn at 00:00) is. Asserted through the summary's own pills, because every card in
      the history shows the same figures.
- [x] `04: dental notes save and reload` — the patient's notes field round-trips.
- [x] `05: extra notes from appointments are shown read-only` — a treatment recorded on the
      appointment's own chart comes back on the patient's chart as *history* (the tooth
      keeps `not-selected`, and `extraNotesFromAppointments` appears).
- [x] `06: the teeth chart stores a condition per tooth` — set, save, reopen, still there.
      `WK.tooth(iso, selected:)` is the key the chart draws each tooth with; `Fixtures
      .setToothCondition` taps the tooth and the condition in the state wheel.
- [x] `07: the patient page link is generated and can be copied` — the generate button
      reaches the server, and the print/QR block only appears once the patient has a link.
- [ ] `08: revoking patient-page access takes the link down`
- [ ] `09: voice autofill fills the dental notes` — skipped by default (AI, see §3.1).
- [ ] `10: the panel can be minimised and restored` — the minimise button only exists below a
      710px layout width. The pane header used to overflow there and red the test before it
      could assert anything; that is fixed (§6.1, 2026-09-28), so what is left is the button
      itself, which is not written yet.

### 1.4 `appointments_crud` (calendar)

- [x] `01: the calendar renders its day cells` — and today starts selected.
- [x] `02: per-day counts match the seeded appointments` —
      `Fixtures.dayCount(tester, day)` reads the day's badge
      (`WK.calendarDayCount(date)`); the group asserts the count *rises* by one rather
      than starting at zero, because the tests share one database. That is the property
      that matters for a user too; a seeded baseline would still make it exact.
- [x] `03: an appointment can be created from a day cell` — `Fixtures.createAppointment`
      books through the panel (pick the patient, optional price and pre-op notes, save).
      This is the test that unblocks the rest of the calendar group.
- [x] `04: the new appointment appears on its day` — the tile is on the booked day and
      not on the next one, and the day's count goes up. The dashboard square is still
      open (`dashboard` group).
- [x] `05: an appointment card opens its panel` — a tap opens it (the press-and-hold
      fallback stays in `openAppointmentTile`).
- [x] `06: an appointment can be rescheduled to another day` — through the panel's date field,
      which is material's `showDatePicker`. The day tap has to be scoped to `DatePickerDialog`
      (the panel and the calendar behind it render day numbers, and tapping one of those
      hit-tests the barrier); the confirm is the dialog's last `TextButton`. The visit is on
      the new day and gone from the old one.
- [x] `07: the duration can be picked from the pill` — the pill's flyout presets, asserted
      after a reopen because the pill draws the *stored* row, not the draft. The **time** field
      is a material *dial* picker and is not driven.
- [ ] `08: two doctors' appointments are both visible and filterable` — **skipped**: the
      operator filter is the tag input (§6.2).
- [x] `09: a day with no appointments shows the empty state` — the day is found by having *no
      count badge* in the visible fortnight, so "no appointments" is proven, not assumed.
- [x] `10: the today button comes back from another month`
- [x] `11: selecting a day highlights it` — asserts the selection moved off today; and
      `selectDay` is idempotent, since the *selected* cell carries no date key.
- [x] `12: the timeline view renders the same day` — the agenda/timeline switch is the date
      button, and the same visit is on screen in both views.
- [ ] `13: paging to another month keeps the appointment data` — **kept skipped as a documented
      failure**: after paging away and back the day's count badge is *gone* while the
      appointments are still in the store, so the calendar loses the day's marker across month
      pages (§6.2 — a real bug; the test is the regression to un-skip).
- [ ] Not covered: `14: a month with many events` (needs bulk seeding), and the operator filter
      above.

Result: **`calendar` = 8 pass / 2 skip.**

### 1.5 `appointment_panel`

**The panel's tests live in `groups/appointments.dart`** (they were never split into a group of
their own), together with the booking flow: 15 written, of which the ones below are the panel's.

**Measured on this tree: `+14 ~1: All tests passed!`** (2026-09-28) — 14 pass, 1 skip (`13`), which
is the whole group. Three of them were red on this tree and are the §6.1 re-applications:
`11` (archiving from an edited panel left it asking to save), `12` (the history flyout's header
overflowed by 18px) and `14` (a multiline tag field was 4px short of its own contents). `11` is
also the one that cost the most: `Fixtures.closePanel(allowPrompt: false)` waits out its full 60s
when the app asks a question the test has said must not be asked.

- [x] `01: all three tabs render` — asserted as `appointments 06` ("the panel shows the
      appointment on its tabs"): panel tabs draw **icons only** (`showTitles` is off), so
      `Fixtures.openPanelTab` taps the tab's icon inside the `TabView`.
- [x] `02: operative details save` / `05: post-operative notes save` — asserted as
      `appointments 08`.
- [x] `03: prescriptions can be added and removed` — asserted as `appointments 14`. The
      prescriptions field offers the clinic's **existing** prescriptions as suggestions and a
      value that does not exist yet has nothing to click (§6.2), so the test seeds one on a
      patient of its own first, picks it, saves, reopens (the chip is read back out of the
      store) and removes it through the chip's own `Key('<label>_clear')` button.
- [x] `04: price and paid update the patient's totals` — asserted as `appointments 07`. The
      price lives on the **operative-details** tab, not on the tab the panel opens on.
- [x] `06: the other-appointments list shows this patient's history, read-only` — asserted as
      `appointments 12` (the flyout titles itself with the number of *other* visits).
- [ ] `07: previous notes can be copied into this appointment` — **cannot be written**: the panel
      *shows* the earlier dental notes (`AppointmentExtraNotes`, read-only) but has no action that
      copies them into the draft (§6.2). Kept as a skip with that reason (`appointments 13`).
- [ ] `08: the gallery uploads a photo and the record gets the server filename`, `09: an uploaded
      attachment can be opened and downloaded`, `10: deleting an attachment removes it from the
      record and from the file list` — **covered by `attachments.dart`** (`04`, `07`, `08`, `10`,
      `12`) through the same calls the gallery's own buttons make
      (`uploadAppointmentFile`/`deleteAppointmentFile` + the record's column). What that group
      skips — and this one cannot add — is the *picker* (an OS dialog) and the *save target*.
- [x] `11: printing produces the prescription` — asserted as `appointments 15`. The **print
      platform** is faked rather than the printer: `Printing.layoutPdf` calls
      `PrintingPlatform.instance.layoutPdf`, and `MockPlatformInterfaceMixin` is what lets a test
      double be installed there (the seam is in `printing`'s `src`, hence the one
      `implementation_imports` ignore in the suite + `plugin_platform_interface` as a dev
      dependency). The whole path really runs — the clinic's footer/phone settings, the QR code,
      the PDF, the call — and the test asserts a PDF reached the platform.
- [x] `12: archiving the appointment hides it from the calendar` — asserted as `appointments 10`.
- [x] `13: a panel that persisted work itself does not claim unsaved changes` — asserted as
      `appointments 16` for the **upload** half: `uploadAppointmentFile` is the call the picker
      path ends up making, and the panel must not turn that into a pending edit. The gallery's
      *column* write goes through the panel's private draft
      (`GalleryUploadConfig.modelPersistence` → `draft.set` + `_persist`), which a test cannot
      reach — and the gallery's own button is not offered in an admin session at all
      (`canUpload` is `login.perm(Perm.photos).exact(1)`, §6.2).
- [x] `14: deleting from the panel and then closing does not warn` — asserted as
      `appointments 11` (regression, fixed 2026-09-19).
- [x] `15: the patient's history lists the visit` — asserted as `appointments 05` (the patient
      panel's appointments tab renders the appointment card, `WK.acSideIcons`).

### 1.6 `sync_offline` — **done** (`groups/sync_offline.dart`, 6 pass / 1 skip)

**Verified green: `+6 ~1: All tests passed!`** (2026-09-25).

**Measured on this tree: `+4 ~1 -2`** (2026-09-28) — then **`+6 ~1: All tests passed!`** after
the two harness fixes below. `01` and `03` — the two "a row written elsewhere arrives here"
tests — both failed at the same assertion to begin with:

```
Expected: 't9957897h08y3ij'
  Actual: 'r5c4lpbul0y24bk'
the pulled row is not readable by name
```

That is `sync_offline.dart:130` (and `:213`), `expect(await Fixtures.patientIdOf(name), id)`,
*after* `_waitForLocalRow` has already found the row in the store **by the server's id** — so
the store has the row, and then `patients.docs.values` answers the name with a *different*
id. Read (not guessed) and fixed on the **harness** side — see §6.3 "a store row can have two
ids": `RemoteRows.insert` wrote a row whose value carried no `id`, which is a shape the app's
own writes never produce, and `Fixtures.patientIdOf` reads the model's id. **`01` passes with
that fix** (`+1` in the re-run) — and with it out of the way, `03` showed a second, unrelated
failure of its own, five seconds in:

```
Expected: false
  Actual: <true>
the shell would not let this test sync
```

`sync_offline.dart:207` asserts the shell's sync action is **not disabled** the moment the test
wants to press it. That assertion used to be vacuous: the app bar ignored
`NetworkAction.disabled` and always passed `onPressed` through, so the reading was `false` no
matter what (§6.1 — and honouring it is a fix of ours). A sync *is* running at that point — the
login's and the navigation sync that opening the patients list fires — so the action is
honestly disabled for a moment, and `Fixtures.tapGlobalAction` (which waits for it to become
pressable and says so when it never does) is the assertion that belongs here. **`01` and `03`
both pass with these two harness fixes** — the group is **`+6 ~1: All tests passed!`**, which
is the number it claims above. (Nothing here was an app bug: the fixture wrote a row shape the
app never produces, and the test read a flag the app bar had been ignoring.)
Two directions, one app: a row written **here** reaches the server, a row written **elsewhere**
reaches here, and neither disturbs what the user is doing. "Elsewhere" is a second writer on the same
PocketBase (`integration_test/support/remote_rows.dart` — the `data` collection the engine reads,
written by hand rather than by a second engine, which would only test the engine against itself), and
the syncs are the app's own: the shell's sync action, the reconnect, and the navigation sync
(`lib/app/routing/routes.dart` calls `synchronize()` on route changes, which is how a fresh login pulls the clinic).

- [x] `01: the login pulls the rows another device already wrote` — the row is written after the
      run's first boot (which resets the server) and before the login; the login lands on the
      dashboard, whose navigation syncs, and the row arrives — readable by name, found by the list,
      and openable as a patient. **Passes again** with the §6.3 fixture fix (the row's value has to
      carry its id).
- [ ] `02: a change made offline lands on the server after a reconnect` — **skipped, kept as the
      regression**: the harness cannot put this app genuinely offline. A clinic's local database is
      keyed by its URL (`AppDatabase.pathFor`), so a login to an unreachable server is a *different
      clinic*; and the in-process levers do not hold — all three measured, in the test's own body:
      `network.isOnline(false)` is republished `true` from the engine's status within a frame;
      `network.onOffline['localpocket']()` pauses the engine, and a write made while it is paused
      **never reached the server** on resume + sync (three runs); `sync.setConnectivity(false)`
      emits no offline status either. It needs a server the run can stop (`-BadServer`, or a local
      PocketBase).
- [x] `03: a change made on another device arrives on the app's next sync` — written after the
      login, asserted absent locally, then the shell's sync action brings it in **and the list shows
      it without a reload** (that screen was already open). **Red on this tree** at the same
      assertion as `01`, for the same fixture reason.
- [x] `04: a remote update does not take an open draft with it` — the user is midway through a rename
      when another device renames the same patient: the panel stays open and the draft is still in
      the field.
- [x] `05: a row deleted on the server is not deleted here` — PocketBase has no delete feed and the
      incremental pull is keyed on `updated`, so a server-side delete is invisible; what happens is
      that the local record survives, and the sync does **not** push it back either (the test prints
      `the server has the row again: false` — `missingRemote: recreate` did not fire for a row that
      had already been pushed). The settings screen's own "clear local data" is the path that drops
      local rows (it resyncs first, then wipes and re-pulls).
- [x] `06: the sync indicator reports busy, then idle` — read off
      `networkActions.isSyncing.stream`, with a bounded wait for the idle end: a `resync()` behind
      that button outlasts a fixed number of frames.
- [x] `07: the lists stay populated while offline` — in the app's working-offline state the sync
      action is disabled and the local records still open (§3.4 `02` covers the shell half of it).

Open, both recorded in §6.2: **`network.isOnline` never goes false for a paused engine** (all three
offline levers), which is what makes `02` unwritable; and **a write made while the engine is paused
is never pushed**.

Not covered here: conflicts between two writers (the policy is unit-tested in
`test/unit/core/db/conflict_policy_test.dart`, and `test/live_backend/row_round_trip_live_test.dart`
covers archive-vs-edit), and a *failing* sync surfacing in the Errors panel (`errors_and_recovery 01`
is skipped for the boot wedge; the tools are `networkActions.addError` and the badge).

---

## §2. P1 — the rest of the product surface

### 2.1 `dashboard` — **done** (`groups/dashboard.dart`, 6 pass / 2 skip)

The squares come in two shapes, which is what the fixtures mirror: the top ones
show a single number (`appointmentsToday`, `newPatientsToday`, `paymentsToday`) and
the rest are titled lists with their own action button (`patientsToday`,
`newPatientsTodayList`, `labworksDue`, `labworksUndelivered`, `expensesDue`). Each
square now carries a stable id (`WK.dashboardSquare`/`WK.dashboardCount`), because
its labels are localized and its widgets are anonymous.

Every count assertion is a **delta** — the tests share one database — and money
finders are scoped to the row or square under test: `expenses 07` failed a full run
by asserting `textContaining('40')` over the whole screen, where another test's
amount matched it.

- [x] `01: the dashboard renders its squares`
- [x] `02: today's appointment count follows a booking`
- [x] `03: the new-patients square follows a first visit` — a patient's first
      visit booked for today.
- [x] `04: the expenses square lists what a supplier owes` — the supplier's name
      is inside that square.
- [x] `05: a square opens the screen it counts` — the expenses square to the
      expenses screen, the labworks square to the labworks screen. Its action has
      to be scrolled into view: the squares live in a horizontally scrolling row,
      and a bare tap misses (`warnIfMissed`) without failing the tap itself.
- [ ] `06 (skipped): money totals use the clinic currency` — changing the currency
      is §2.9's surface; the square already renders `MoneyDisplay` with the
      currency the screen read once.
- [ ] `07 (skipped): an empty clinic shows zeros, not spinners` — needs a *fresh*
      database, and the run resets once, on its first boot (§4.3). That is a
      separate run, not a test in this group.

### 2.2 `labworks` — **written, all 8 skipped on a fluent_ui defect**

Lab work is not a store of its own: it lives on the appointment
(`hasLabwork`/`labworkReceived`/`labName`/`labworkNotes`), and the screen derives
three states (`Appointment.labworkStatus`). There is **no lab price or paid flag**
any more — not in the schema and not in any widget (five `WK.fieldLabwork*` keys
were left behind by the legacy panel and were deleted) — so the old `04: marking
it paid updates the totals` cannot be written; the state machine replaced it.

**On this tree (2026-09-28) the group has been run**: `~8: All tests skipped` — which is what
it is designed to report (the docstring below says why each one is skipped, and the runner's
`All tests passed!` line is replaced by `All tests skipped.` when nothing ran). Before the key
work, `WK.fieldLabworkAppointment`, `WK.fieldLabworkOrderNotes` and `WK.fieldLabworkReceived`
were declared and attached to nothing (attached now, §0.2), and `WK.fieldLabworkLabName` was
attached to **two** widgets at once — so the fixtures' waits could not have resolved.

**The skips still stand, and lifting them is not a matter of the key work.** Three of them are
fluent's own `AutoSuggestBox` posting a post-frame `setState` from its text listener after the
panel is disposed — the app cannot reach that call; §6.1's fix guarded the *app's* callback in
`TagInputWidget` (`if (!mounted || !context.mounted) return;`), which is a different path. The
rest need the lab-name suggestion overlay to stop swallowing the panel's Save tap
(`Fixtures.attachLabwork` types into it and `Fixtures.save` then waits out "the panel never
settled to nothing to save"). Each of the eight carries its own reason in the file.

`groups/labworks.dart` holds all eight tests, and each asserts a real behaviour —
but **every one of them is skipped**, because each ends by closing a panel built
from fluent's `AutoSuggestBox` (the patient picker, the lab-name field) and that
widget posts a `setState` after its element is defunct. The framework attributes
that error to whichever test owns the frame, and which test that is moves from run
to run: fourteen runs of the group failed a different subset each time (4 passed
and 4 failed in most, never the same four). See §6.2 and §6.3. The tests are kept
so they can be enabled the moment fluent stops doing that.

- [x] `01: the labworks screen renders its command bar and search`
- [x] `02: a labwork is attached from the appointment panel` — reads as
      `waitingForLab` in the table.
- [x] `03: the new-labwork panel links a patient's visit`
- [x] `04: the lab name autocompletes from earlier labworks`
- [x] `05: marking a labwork received moves it out of the due view` — the row's
      own checkbox; it reappears under "show done".
- [x] `06: the search filters the table by lab name`
- [x] `07: the patient's latest completed visit with received lab work reads as
      undelivered`
- [x] `08: deleting the lab work takes it off the screen`
- [ ] Not covered: the dashboard's `due`/`notDelivered` squares (§2.1 needs keys
      for the squares first), and the notification entries that read those lists
      (`static_notifications.dart`).

### 2.3 `notes` — **done** (`groups/notes.dart`, 7 pass / 1 skip)

The board is addressable now: `WK.notesBoard` (the columns are a `Row` inside a
horizontal scroll view, so `Fixtures.revealInBoard` scrolls a column into the
viewport before tapping it — a built-but-offscreen tap silently does nothing),
`WK.columnRoot(id)` / `WK.columnHeader(id)` per column, `WK.btnAddNote`,
`WK.btnNoteDelete`, `WK.btnNoteTitleSave`, `WK.btnNoteTextSave`, and the note
dialog's `WK.fieldNoteTitle` / `WK.fieldNoteText` / `WK.fieldColumnTitle`.

- [x] `01: the board renders its columns` — plus a column created through the UI.
- [x] `02: a column can be added, renamed and archived` — archiving *is* the
      board's delete (restorable), so it goes through the confirm flyout.
      **Reordering is not in the current UI** (a column header has no reorder
      affordance), so it is neither tested nor claimed.
- [x] `03: a note can be created in a column` — the header's add-note button
      presets the column; asserted on the board *and* in the store (`columnID`,
      body).
- [x] `04: a note can be created from the command bar` — it lands in the
      uncategorized column, the one column that is not a stored row (its id is
      `''`, `Notes.uncategorizedColumnId`).
- [x] `05: a note can be renamed and commented inline` — a card expands in place
      and swaps its title *label* for a field with its own save button, so once
      expanded the card is addressed by note id (`Fixtures.noteCardById`).
- [x] `06: a note can be dragged between columns` — `LongPressDraggable` onto the
      column's `DragTarget`; asserts the board *and* the stored `columnID`.
- [x] `07: a note can be deleted` — archived: gone from the board and from the read
      the board uses.
- [ ] `08: a staff account without the notes permission still sees its own` —
      **skipped**: it needs a second, restricted session (§2.7 accounts), and the
      regression it guards (the filtered getter mutating state and rebuilding
      forever) cannot be reproduced without one.
- [ ] Not covered: **notes survive a restart** (the suite's stores survive between
      tests, so the honest version is a real relaunch — the web
      `web_open_test.dart` pattern), and the recurring-note instance logic
      (`ghostInstancesInColumn`, `nextExpectedDate`), which is unit-testable (§4).

### 2.4 `attachments` — **the group file does not exist** (`groups/attachments.dart`)

The group attaches to a **note** — the one attachment owner a test can create and
look up through the UI without a second store — and drives the same call the
picker path ends up making: `uploadAppointmentFile(rowID:, filename:, file:
XFile.fromData(...))`. Everything after the pick is real: the upload, the
record's filename column, the suffix rules, the read-back and the delete. The
skipped items each say what blocks them, and `04`/`08`/`12` cover the code they
would have reached.

- [x] `04: viewing an uploaded image renders it` — the record names the file, the
      bytes read back byte-for-byte, and the card that shows it draws without an
      exception.
- [x] `07: a malformed image does not crash the gallery` — a `.png` whose bytes
      are not an image: the gallery logs (`Could not draw … Invalid image data`)
      and keeps the good attachment beside it.
- [x] `08: the stored filename suffix is handled both ways` — the file resolves
      under PocketBase's name *and* under the un-suffixed spelling of it.
- [x] `10: an attachment can be deleted from the record` — after
      `deleteAppointmentFile` (plus the column write the gallery's delete button
      also does) nothing reads back and the record no longer names it.
- [x] `12: two attachments with the same name do not overwrite each other` —
      **this caught a real bug** (§6.1). It asserts the column names two entries:
      a name-addressed column cannot separate two same-named files until
      PocketBase renames one (§6.2).
- [ ] `01: a file can be picked`, `03: a photo can be picked` — **skipped**: the
      picker is a platform dialog a widget test cannot answer.
- [ ] `02: upload failure is reported and the retry succeeds` — **skipped**: needs
      an upload that fails *after* the bytes are durable; §1.6 `sync_offline` is
      where the backend can be taken away.
- [ ] `05: downloading works on native`, `06: on web` — **skipped**: the last step
      is `saveFileUtility`, a platform save target (and a dialog on desktop). The
      web `Unsupported operation: _Namespace` crash these items were written for
      is guarded in `downloadFile` itself (`!kIsWeb`).
- [ ] `09: the DICOM preview name is normalised` — **skipped**: needs an
      appointment's `dcmImgs` plus the DICOM viewer; the naming rule itself is
      covered by `test/unit/features/dicom/dicom_helpers_test.dart` and
      `test/unit/utils/strip_id_from_file_test.dart`.
- [ ] `11: web caches blobs in OPFS after a successful attach` — **web only**
      (`skip: !kIsWeb`): it runs when the suite is run with
      `-Target web -WebHeaders`.

### 2.5 `expenses` — **done** (`groups/expenses.dart`, 7 pass / 1 skip)

A receipt is not its own record either: an `Expense` row is a **supplier**
(`isSupplier`, a name) or one of its **orders** (`supplierId`, date, items, cost,
paidAmount, processed), and the panel's two tabs are the ledger's two sides. The
receipt dialog the original list described is gone — the whole `WK.fieldReceipt*`
key set was dead — so those items were replaced by what the screens do.

- [x] `01: the expenses screen renders its command bar and list`
- [x] `02: a supplier can be created` — through the screen's own dialog.
- [x] `03: an order can be added to a supplier` — and it is counted against the
      supplier on the list.
- [x] `04: an order splits into cost and paid` — the outstanding amount is
      cost − paid.
- [x] `05: a new order is due and not paid` — it is listed on the due tab and
      absent from the paid one.
- [x] `06: archiving an order takes it off both tabs`
- [x] `07: the search filters the supplier list`
- [ ] `06 (skipped): marking an order paid moves it to the paid tab` — the flip
      lives in the order row's overflow menu, and that flyout never opens from the
      harness: the button takes the tap (no `warnIfMissed`) but no `MenuFlyoutItem`
      is ever built, so there is nothing to tap. Everything else about the tabs is
      asserted by `05`.
- [ ] Not covered: the totals row (`Total: <due>`), the receipt-photo lane and
      the AI receipt scan (`scanReceiptDialog`, an external service).

### 2.7 `accounts` + `permissions` — **done** (`groups/accounts.dart`, 8 pass / 2 skip)

**Verified green: `+8 ~2: All tests passed!`** — re-measured 2026-09-28 on this tree, in 3m36s
(`pwsh -File tools/run_e2e.ps1 -Group accounts`). It read `+2 ~2 -6` here before that date,
for two reasons that were both real: `Fixtures.createAccount` / `setAccountEnabled` /
`grantPermission` wait on keys the rollback left attached to nothing
(`WK.fieldAccountName` / `fieldAccountEmail` / `fieldAccountPassword` /
`WK.accountOperates` / `WK.permissionSelector(id)` — §0.2 / §6.1), and `08` (the group's
only test that signs in **twice**) tripped a `LateInitializationError` in the deferred-push
queue that aborted `Messaging.identifyDevice` on every login after the first (§6.1).

Accounts are handled by `accounts_controller.dart` (a `profiles` view over PocketBase's
`users`/`_superusers`); permissions are nine rows (`Perm`) with two or three levels each.
The group needs a **second session**, so `Fixtures.loginAs` signs out and back in — and
`Fixtures.signInAsAdmin` puts the harness's own session back, because `E2E.signIn` returns
early for *any* live session and every later test would otherwise run under the account the
previous test created.

- [x] `01: the accounts screen lists accounts` — rows, and the screen's own `admins: N` /
      `users: N` counts.
- [x] `02: an account can be created` — through the panel's three fields; the row appears
      (the list is lazy, so the search box is what makes it findable).
- [x] `03: an account is created disabled and can be toggled` — a new account is stored
      `operate: 0`; the panel's switch takes it to `1` and back.
- [x] `04: an account signs in with its own email and password` — a real second session, and
      the shell says whose it is.
- [x] `05: a permission-less account is offered no gated route` — the admin's registry
      contains `dashboard`/`patients`/`calendar`, the new account's contains only the
      dashboard: gated routes are *omitted*, not drawn locked.
- [x] `06: the account switch decides who is an operator` — the switch is not a login gate
      (§6.2); it decides whether the signed-in account is offered as an appointment operator.
- [x] `07: an admin has no locked route` — every `Route.accessible` is true.
- [x] `08: a granted permission unlocks its screen` — `patients` at its highest level, granted
      through the row's own flyout, and the screen opens in the next session (this is what
      the notes group's permission test was waiting for).
- [ ] `09: permission changes apply on the next login` — **skipped**: `08` already covers
      "granted", and a *revoked* one is the same machinery with one more sign-out.
- [ ] `10: an account can be removed and its rows survive` — **skipped**: nothing in the UI
      deletes an account (disabling it is the app's removal, and the clinic's records are the
      clinic's).
- [ ] Not covered: `07` of the original list — *every* permission gating *its* screens, one
      test per screen. The mechanism is asserted once (`05`), and per-screen gating is a
      product of the same `routes.allRoutes` filter.

### 2.6 `insights` — **done** (`groups/insights.dart`, 3 pass / 2 skip)

The charts are asserted through the chart widgets they draw with
(`StyledBarChart`/`StyledLineChart`/`StyledStackedChart`) and the numbers through
`chartsCtrl` — the values the charts are handed. Reading a rendered subtitle back
would mean parsing a localized sentence to get at a count.

- [x] `01: the charts render` — the chart kinds the screen always draws, plus the
      range selector's two ends.
- [x] `02: the appointment total follows the data` — a booking made today reaches
      `chartsCtrl.filteredAppointments` (the window is a database read the screen
      re-runs on a committed change).
- [x] `03: the period changes the numbers` — the period switch takes, and the
      chart periods change with it.
- [ ] `04: the calendar system changes the axis labels` — **skipped**: that is a
      setting (§2.9 `04`), and switching it belongs to that group.
- [ ] `05: an empty clinic renders empty charts, not an error` — **skipped**: needs
      a *fresh* database, and the suite shares one (same reason as
      `dashboard 06`/`07`).

### 2.8 `deleted_items` — **partly done** (`groups/deleted_items.dart`, 2 pass)

- [x] `01: an archived record is listed` — a patient archived from its own panel
      shows up here.
- [x] `02: filtering by type works` — filtering to notes takes the patient out of
      the list.
- [x] `03: restoring a record puts it back in its screen` — covered in
      `patients 13` (select the row, restore from the command bar, reopen it).
- [ ] `04: permanent deletion removes it from the server` — **no such action exists
      in the UI** (see §6.2): archiving is the app's delete, and nothing purges.
- [ ] `05: the empty state renders` — needs a database with nothing archived.
- [ ] Not covered: appointments/labworks/expenses rows and the screen's sort
      control (§2.8 `01`'s "every kind"), which needs those kinds archived.

### 2.9 `settings_general` — **done** (`groups/settings_general.dart`, 4 pass / 4 skip)

**Measured on this tree: `+4 ~4: All tests passed!`** (2026-09-28, 56s) — the 4 pass / 4 skip
below, restored. It was `+0 ~4 -4` before the `ItemTitle` fix in §6.1: all four reds were the
same `string is not well-formed UTF-16` burst, thrown on the screen the app lands on after
login (before the settings screen is even opened), which is also why it looked like a
`WK.settingsItem`-placement problem and was not one.

The cards are collapsed `Expander`s in a lazy `ListView`; each has a stable identifier
(`WK.settingsItem(id)`), a `Key('<id>_text_field')` / `Key('<id>_combo')` inside it, the scope
indicator (`AppliesToIndicator`) on the **collapsed header** and any `footer` inside the
content. `Fixtures.revealSettingsCard` / `expandSettingsCardByTitle` / `setSettingsText` drive
them. **This group is what found the UTF-16 crash in §6.1** — every test used to fail on it.

- [x] `01: every card renders` — currency, language, date format, calendar view, calendar
      system, dental notation.
- [ ] `02: a changed card persists across screens` — **skipped, kept as the regression**: typing
      a different value into the currency card never makes its Save button appear (§6.2), so the
      change cannot be committed from the harness.
- [x] `03: a card says what it applies to` — `AppliesToIndicator` renders on the collapsed
      header of both a device-scope card (language) and an app-scope one (currency).
- [ ] `04: the calendar system changes the dates app-wide` — **skipped**: switching it rewrites
      how every later test's dates read and the suite shares one clinic (§2.15).
- [ ] `05: the dental notation switches the teeth charts` — **skipped**: needs a teeth chart
      with labels on screen.
- [x] `06: the AI card offers its switch without AI keys` — the `ai_services_ena` combo renders.
      The cache reset is asserted **present only**: pressing it clears the local database and
      resynchronizes (minutes, and it would destroy the suite's own state).
- [ ] `07: settings are per clinic` — **skipped**: needs a second clinic (§2.15).
- [x] `08: the privacy note sits next to the AI settings` — the `InfoBar` in the AI card's
      expanded content.

### 2.10 `settings_services` — **done** (`groups/settings_services.dart`, 5 pass / 1 skip, verified)

**Verified green: `+5 ~1: All tests passed!`** (2026-09-25), after a run of `+1 -5`.
**Measured on this tree: `+5 ~1: All tests passed!`** (2026-09-28) — its first run here, and it
only became *runnable* when the section and field keys went on (`WK.serviceSection`,
`WK.serviceField`, §0.2): before that, `openServiceSection` waited for a key nothing drew. The
bullets below are the migration branch's lessons; the outcome is not.

Three things
made the difference, and each was a harness lesson rather than a product change: a shut fluent
`Expander` keeps its content laid out, so "is the section open?" has to be judged by its **height**
(§6.3); the sections' list cannot be scrolled by drag or `ensureVisible`, so its `ScrollPosition` is
driven directly; and a services save must wait for its dialog to be gone — while it is up, the
section behind it is not hit-testable, so a second save tapped the barrier and the helper read the
*previous* dialog's text and reported success.

The six sections (`meta`, `auth`, `file_upload`, `s3`, `smtp`, `backups`) are PocketBase
**server** settings (`login.pb!.settings`), rendered only for an admin on an online session —
so each test has two sides: what the app draws and what the server ended up holding. They are
anonymous `Expander`s below the cards; `WK.serviceSection(id)` and `WK.serviceField(id)` are
what a test addresses them by, and `Fixtures.openServiceSection` / `tapInSection` /
`saveServiceSection` drive them (the sections are long, so the settings list is scrolled by
driving its `ScrollPosition` — see §6.3).

- [ ] `01: an admin is offered every service section` — **skipped, kept as the regression**. In a
      fresh process the settings route does not come up for the group's *first* test: the nav tap is
      retried (`Fixtures.openRoute` prints its retry) and it still times out, while 02–05 open the
      very same screen in the same run and find their sections. The account is an admin at that
      moment (asserted, and it passes), so it is the screen, not the permission. Coverage is kept by
      02–05.
- [x] `03: a mail server change reaches the server` — a marker host through the app's Save, read
      back from `/api/settings` **through a poll** (the settings snapshot lags the write: asserting on
      the first read showed the previous run's marker and looked exactly like a save that never
      happened). Restoring the old host is best-effort and only warns — a second write of that key
      does not land, through the app *or* the server API (§6.2).
- [x] `04: a bad S3 configuration fails with a message` — the section's own Test button against
      an unreachable endpoint reports an `ERROR` `InfoBar` instead of throwing.
- [x] `05: an upload limit change reaches the data collection` — the limit is stored on the
      `imgs` field of the `data` collection (`maxSize`, in bytes), and it is put back after.
- [x] `06: an account without the admin flag is not offered them` — a created, enabled account
      signs in with no service section anywhere, and the settings screen is not built for it at all
      (the nav pane offers the route locked, or not at all).
- [x] `02: a mail password is hidden until it is revealed` — the SMTP password field is
      obscured, its own reveal button changes that, and it can be hidden again.
- [ ] Not covered from the original list: `05` "a good S3 configuration round-trips a file" and
      `06` "over-size upload is rejected" both need a writable bucket / a real upload against a
      configured S3 target — §2.12 dicom and §2.4 attachments carry the upload paths that can be
tested without one.
- [ ] `07` "changes are rejected without superuser rights" is covered where it is visible: an
      account that is not an admin is not shown the sections at all (`06`).

### 2.11 `backups` — **done** (`groups/backups.dart`, 3 pass / 4 skip, verified)

**Verified green: `+3 ~4: All tests passed!`** (2026-09-25). `01`, `02` and `04` pass; `03` and `05`
are skipped with their evidence in the body, and `06`/`07` for the reasons below.

**On this tree (2026-09-28) it had not been run at all**: `WK.serviceSection('backups')`,
`WK.serviceField('backups_cron' | 'backups_maxKeep' | 'backups_s3_endpoint')` and
`WK.backupRow(key)` were all declared and attached to nothing, so nothing here could be
opened or seen. They are attached now (§0.2) — **measured: `+3 ~4: All tests passed!`**,
which is the 3 pass / 4 skip this group always claimed. Two things were worth writing down on
the way:

- `02: creating a backup adds a row` waits for the new row **by its own key**
  (`WK.backupRow(element.key)`, on the row's `ServicesListItem`) ✓.
- `04: a cron preset and the keep limit reach the server` failed first, and the log named the
  reason: it taps `WK.serviceField('backups_cron')` expecting a **preset dropdown** to open,
  but the key was on the *disabled* box that merely shows the cron expression while the real
  picker is the `ComboBox<String>` beside it. A tap on a disabled field only *warns*
  (`warnIfMissed`), so the test then spent its 60s wait on a preset list that can never open.
  `Fixtures.serviceFieldText` already says a `serviceField` may sit on "a `CupertinoTextField`
  **or a `ComboBox`**" — the key is on the combo now, and `04` passes.


Backups are the server's (`login.pb!.backups`): the app lists them, creates one, and deletes or
restores one per row. Every assertion here has a server side and a UI side, and anything the
group changes (the cron schedule, the S3 fields, a backup it makes) is put back or removed.

Its first two runs were taken out by things that were not its own: the login-blocking
`localOnly`/sync bug (§6.1), which made every test report *"The local database never opened after
signing in"*; and the boot stall, whose hung frame leaves the test binding's guard claimed, so one
stall turned the rest of a run into `Guarded function conflict` failures (§6.2). `01` also carried
the first-test-of-a-run nav-tap signature, which `Fixtures.openRoute` now retries.

- [x] `01: the section offers its list controls` — create, upload, refresh, and the schedule
      half (the auto switch, the cron preset dropdown, the keep limit).
- [x] `02: creating a backup adds a row` — the server's list grows by one and the app draws the
      new row (the server makes it asynchronously, so the list is polled).
- [x] `03: a backup can be deleted from its row` — through the row's own delete button and its
      confirmation dialog, with both sides checked.
- [x] `04: a cron preset and the keep limit reach the server` — a preset + a keep count through
      the app's Save, read back from `/api/settings`, then restored.
- [x] `05: the backups S3 fields save and reload` — the section's own S3 switch and endpoint.
- [ ] `06: a failed backup says so` — **skipped**: PocketBase fails a backup it cannot write, so
      forcing one means pointing the shared clinic at a broken S3 target.
- [ ] `07: a backup carries attachments` — **skipped**: a local backup holds the data file, and
      restoring one is destructive to the clinic this suite shares.

### 2.12 `dicom` — **done** (`groups/dicom.dart`)

**On this tree (2026-09-28) it had not been run at all**: all six handles it waits for
(`WK.dicomScreen`, `WK.dicomScanButton`, `WK.dicomAutoImportToggle`, `WK.dicomPendingCard(key)`,
`WK.dicomApprove`, `WK.dicomChangeMatch`) were declared and attached to nothing, so not one of
these tests could get past its first wait. They are attached now (§0.2) — see §2.10's note for
what that does and does not claim.

The X-ray link is a **Windows-only feature by construction**: `DicomController.isSupported` is
`!kIsWeb && Platform.isWindows` and the route is gated on it, so on any other platform there is
nothing to open and every test skips with that reason (§4.1).

The group drives the app's own scan end to end: a real `.dcm` (the sample the repo ships for
exactly this, `test/fixtures/dicom/sample.dcm`) is copied into a real temp folder, the folder is
set as the clinic's watch directory, and the controller scans it with the real parser — the
isolate, the metadata cache, the skip log, the matcher and the screen are all the app's. Two
things the app does in `main()` have to be done by the harness instead (`support/dicom_fixture.dart`):
`initDicomToolkit()` (the native engine) and `initializeDicomScan()` (which *touches* `dicomCtrl`,
the thing that registers the scan lifecycle with the login).

- [x] `01: the screen renders with no DICOM files` — the "no watch folder" empty state, the scan
      button offered but **disabled**, and an empty pending list.
- [x] `02: the auto-import toggle persists` — through the Linked Patients dialog: the switch
      flips, the clinic's setting follows, and reopening the dialog reads it back.
- [ ] `03: a folder can be chosen as the watch directory` — **skipped**: `FilePicker.getDirectoryPath`
      is an OS dialog a widget test cannot answer. What the setting *does* is `04`.
- [x] `04: a file dropped in the watched folder is imported` — one pending import, its file count,
      and the card on screen (keyed by the record key it was built from).
- [ ] `05: a .dcm can be uploaded on web` — **skipped: the web import path does not exist.**
      `handleNewDcm` returns `''` on web (`lib/utils/imgs.dart:193`), the route is Windows-gated,
      and the gallery's file picker sends every file through `handleNewImage` — so a `.dcm` picked
      on web lands as an ordinary attachment. Recorded in §6.2 as a missing feature, not a bug.
- [x] `06: an imported file is matched to a patient by name and date` — the patient is created with
      the name the **file itself** carries (read through the same parser, so a new sample cannot
      break the test) plus a visit on its study date; the scan matches it with confidence > 0.9, the
      card shows both sides, and the patient is handed back at the end (or a later scan in this
      group would match it again).
- [x] `07: an unmatched file appears in the unmatched list` — with only an unrelated patient in the
      clinic, the import comes back unmatched, the card says the match has to be picked by hand
      (`dicomNoMatch`), and it offers no approve.
- [ ] `08: a skipped file says why` — **skipped**: there is no UI for it (`DicomSkippedLog` keeps
      the reason in the device database and its own doc says the screen does not surface it). Unit-covered.
- [x] `09: the matching dialog lets the user pick a patient` — the card's "change match" opens the
      picker, the patient is picked by name, the date-alignment step names both sides, and its Save
      is what the dentist's choice lands on.
- [ ] `10: the viewer opens and renders the image` — **skipped**: the dialog is opened from a gallery
      entry that is in the record's `dcmImgs` (which needs an approve — see `12`), and neither the
      dialog nor the `DicomViewer` widget carries a key.
- [ ] `11: the viewer controls work` — **skipped**: no keys on any control (the two window-level
      sliders are fluent's, wrapping material's, like the a11y note in §4). The pref they write is
      unit-covered (`dicom_viewer_prefs_test.dart`).
- [ ] `12: a preview png is uploaded to the record and named correctly` — **skipped**: it needs a
      full *approve* (copy, upload, render a PNG, upload that too), and the naming rule plus the
      group-based sibling resolution are unit-covered (`dicom_helpers_test.dart`,
      `dicom_orphans_cleaner_test.dart`, `dicom_gallery_test.dart`).
- [ ] `13: deleting the record removes the DICOM link` — **skipped**: a link only exists after an
      approve (`12`), and `DicomLinksStore`'s add/unlink/removeKey are unit-covered.
- [ ] `14: the registries survive a restart` — **skipped**: they moved out of Hive into the **device**
      database (`dicom_links`, `dicom_file_meta`, `dicom_lru`, `dicom_skipped`,
      `dicom_pending_matches`, `dicom_unmatched`), and that database is opened once per process — so
      "a restart" is the one thing this harness cannot stage (same as `errors_and_recovery 03/04`).

The feature had **no widget keys at all**, so the screen, its scan button, the auto-import switch,
a pending card and the card's approve/change buttons were given stable keys (`WK.dicomScreen`,
`WK.dicomScanButton`, `WK.dicomAutoImportToggle`, `WK.dicomPendingCard(key)`, `WK.dicomApprove`,
`WK.dicomChangeMatch`). Everything else on that screen still has to be addressed by copy.

### 2.13 `patient_side` (portal)

**Group `patient_portal` written — 6 pass / 1 skip.** The portal is the app's only *unauthenticated*
surface, so half of this group is a server-side security check: it reads the collections with a client that
is **genuinely anonymous** (see below) and asserts what a stranger can and cannot get.

- [x] `01: the public view cannot be listed without a pid` — no `pid`, no rows. The view's rule is
      `@request.query.pid != "" && pid = @request.query.pid`, so the patient id is a capability the
      **server** enforces rather than a client filter anyone can drop.
- [x] `02: a pid scopes the public view to that patient` — with two patients seeded, every row that
      comes back carries the requested pid.
- [x] `03: a wrong or injection-shaped pid yields nothing` — `04: a crafted pid cannot enumerate other
      patients` — a well-formed id belonging to nobody, `" || pid != ""` and `x' || '1'='1` all return
      nothing.
- [x] `04: an injection-shaped patient id is refused before a request` — the app's own guard:
      `PatientSide.activate` rejects an id outside `^[a-zA-Z0-9_-]{1,64}$` (the id is interpolated into a
      request) and says so on the login screen.
- [x] `05: the patient page shows the linked patient's visits only` — the app is put into portal mode
      the way the link does it (`activate()` reads the link's four values, loads *that* patient's visits
      from the `public` view and calls `launch.open(Open.patient)`), and another patient's name is
      asserted absent. The test leaves the mode through the app's own `logoutPatientSide()`.
- [x] `07: the record collection is not readable without a session` — no patient, appointment, note or
      expense row reaches an unauthenticated caller. The single exception is a `settings_global` row
      (`ISO_country____`), which is deliberate — the portal reads the clinic's display settings that way —
      and is recorded in §6.2.
- [ ] `06: the portal is localized` / `07: no staff chrome` — not written.
- [ ] `06: the patient's shareable link is minted onto the record` — **skipped, kept as the regression**:
      `generatePatientLink()` posts the long link to a **shortening server** and stores the answer, so on a
      machine that cannot reach it the button correctly reports an error and stores nothing. That is an
      environment limitation, not an app one.
- [ ] `08: a QR link and a typed link behave the same` — **skipped**: a QR needs a scanner; the typed
      link's path is what `05` drives (`activate` with the link's own four values).

**Two traps this group paid for, both now in the memory notes:** `PocketBase(url)` is *not* an
anonymous client — its default auth store persists, so a fresh client inherits the session the app just
established, which is how the first version of this group "proved" the public view was open to anyone
(the anonymous client needs `AsyncAuthStore(save: …, clear: …)` no-ops). And the portal is a whole-app
*mode*: a test that enters it must leave through `patientSide.logoutPatientSide()`, or the next test
fails inside `signIn` because there is no login form on screen.

### 2.14 `localization_rtl` — **done** (`groups/localization_rtl.dart`, 5 pass / 1 skip)

**Verified green: `+5 ~1: All tests passed!`** (2026-09-25).

**Measured on this tree: `+5 ~1: All tests passed!`** (2026-09-28, first measurement here) — the
group was in the "never run" list because it had not been measured since the rollback, and
`01: every locale renders the staff shell` passes here *without* the §6.1 dashboard-title fix
that the migration branch needed: the list-square title row in this tree's
`dashboard_screen.dart` is still `Row(mainAxisAlignment: spaceBetween, children: [Txt(title),
IconButton])` with no `Flexible`, and no locale overflows it at 1600px with these labels. Worth
an eye if those titles grow or the squares narrow (see §6.3).

`03`, `04` and `06` were written after the first run showed `01` and `03` failing on real findings
(the dashboard overflows §6.1 and English-only keys), and all three then failed for reasons of their
own — two of them the *test's* fault, one a helper's (see the bullets). A run in between hit the
boot wedge in §6.2.

Five dictionaries (`En`, `Ar`, `Es`, `El`, `Fa`), chosen by index in the app's **local**
settings — so a test that changes the locale must restore English before it ends, or every
later group asserts translated labels. `txt()` falls back to the key, so a missing translation
is invisible from the outside; the group's job is to make it visible.

- [ ] `01: every locale renders the staff shell` — **skipped, kept as the regression**: the run
      stops dead in this test (todo.md §6.2). Its body is the one that found the dashboard
      header overflows in every non-English locale.
- [x] `02: an RTL locale mirrors the shell` — the shell's `Directionality` flips, and the app
      bar's back arrow points the other way (it is drawn from the direction).
- [x] `03: no locale renders a raw key or an empty string` — every *translated* dictionary is
      checked for a value that is its own key and for empty values. Two exemptions, both earned by
      the run: English is the **source** dictionary, so its values *are* its keys by design
      (`"mode": "mode"`, `"labwork": "labwork"`, `"ascending": "ascending"` — the English word
      for each is the key), and the metric abbreviations are written the same way in **every**
      language (`mm`, `min` in Spanish), which is a small explicit set beside the test that grows
      only from its own output. "Has every English key" is deliberately *not* asserted: English
      carries keys the others never had, the app only looks up the keys it uses, and that half is
      what `01` renders.
- [x] `04: a locale choice is applied by the settings card` — the user's own path through the
      language card (which also triggers a resync). It needs the card to be really **open**: the
      first version tapped a dropdown inside a `Expander` that was collapsed-but-laid-out, so the
      tap landed on the card's header and the option wait timed out after 60s (§6.3).
- [x] `05: the locale survives a restart` — the setting is device-scoped and persists.
- [x] `06: the login screen offers every locale` — the pre-login picker has its own combo
      (`WK.loginLangComboBox`) and every language in it is offered by name. The app restores the
      stored session on **every** boot (`login.fromJson` re-activates the token), so the test has to
      reach the login screen the way a user does — `Fixtures.signOut` — and signs back in at the
      end so the later groups still find a session.
- [ ] Not covered: dates/numbers per locale (§2.9 `04` covers the calendar system), and the
      patient-side screen's own language picker (that is §2.13).

### 2.15 `multi_clinic` — **the group file does not exist** (`groups/multi_clinic.dart`)

**A clinic *is* a server URL** in this app: no clinic list, no switcher, no per-clinic settings.
What makes two clinics two is `AppDatabase.pathFor(url)` — one local database per URL — and
switching is the user's own path: log out, then log in to the other server.

The harness has **one** PocketBase, so the second clinic's server is a URL with nothing listening:
the login fails, the app offers "proceed offline", and that login creates and opens the second
clinic's own database. What the tests prove is therefore the *local* separation — the two URLs share
nothing — which is what a second live server would also get; with a reachable second server the same
code path separates the server data too. (This is the same fact §1.6 recorded: a clinic's database is
keyed by its URL, so an unreachable server is a *different clinic*, not a broken one.)

- [x] `01: a second clinic can be added and switched to` — a second url, a database of its own
      (created by that login, and a *different file* from the first clinic's), still empty, and the
      first clinic's file untouched.
- [x] `02: each clinic's data stays separate` — a record written in A is not in B (B inherited
      nothing), and the record is handed back at the end (server first — §6.2).
- [x] `03: switching back to A shows A's data` — a round trip through B leaves A's record and A's
      screen exactly as they were.
- [ ] `04: the login form remembers the last server per clinic` — **not writable as specified: the
      feature does not exist.** One server url is stored with the session, and a real logout clears
      it; there is no per-clinic memory and no clinic list. `login 08` covers the one value from the
      other side.
- [x] `05: an existing clinic gets the schema reconciliation on admin login` — the `public`
      collection's list rule is drifted to a **valid** other rule (`'false'` is rejected by
      PocketBase: "invalid or incomplete filter expression"), the per-clinic marker is cleared, and
      an admin login puts the app's definition back *and* records the marker.
- [x] `06: the schema reconciliation is skipped when the version marker is current` — with the marker
      current, the same login leaves the drift alone; the tearDown restores the canonical rule and
      clears the marker so the next admin login reconciles again.
- [ ] `07: a legacy Hive-era clinic migrates without losing rows` — **the path does not exist**:
      `hive` is not a dependency, there is no migration code (only per-store
      `StoreMigration(toVersion: 2)` schema migrations), and the `*.hive` files in `apexo-files/`
      are read by nothing.

The marker itself lives in the **device** database (`schema_versions`, one row per clinic,
`schemaVersion = 1`) and is read/written with `appliedSchemaVersion` / `storeAppliedSchemaVersion`.

### 2.16 `lifecycle_platform` — **done** (`groups/lifecycle_platform.dart`, 8 pass / 1 skip)

**Verified green: `+8 ~1: All tests passed!`** — re-measured 2026-09-28 on this tree, in 1m37s
(`pwsh -File tools/run_e2e.ps1 -Group lifecycle_platform`). It was **red here** between
2026-09-27 and that date (`+3 ~1 -5`, then `+6 ~1 -2`), for two reasons that are neither
fluent's nor the 2026-09-28 routing refactor's: the group's nav taps were waiting on
`WK.btnNewPatient` / `WK.btnNewAccount` / `WK.globalAction(…)`, which the rollback left
**attached to nothing** (see §0.2 and §6.1), and `05` narrowed the window to 300px where the
pane header overflowed by 214px. Both are fixed — §6.1 — and `06` is skipped for the
phone-layout clipping that the video work recorded. `08` also needed the test itself fixed:
it walks a history, and it was inheriting the router state test `05` leaves behind (§6.3).

This group drives window **sizes**: `Fixtures.sizeTo` sets the test view, and the app reads its
width from a `LayoutBuilder` (`launch.layoutWidth`), which is what moves it between display
modes. The 710px boundary is the app's own (`routes.showBottomNav`), so it is the one the tests
assert — including the 710..1000px *compact pane*, which is no longer stepped around now that its
header shrinks instead of overflowing.

- [x] `01: a device with no session starts on the login screen` — no shell, `Open.login`.
- [x] `02: a restart keeps the session, the settings and the data` — a re-pump (the harness's
      restart): still signed in, the patient still there, the theme still dark, then back to light.
- [x] `03: the pane folds from expanded to compact and back` — at 1600px the routes are offered
      and there is no phone bar; at 600px the phone bar is drawn.
- [x] `04: the phone layout draws a bottom bar that navigates` — and it goes away again when the
      window grows.
- [x] `05: a bar that cannot fit its routes offers More` — at 300px the overflow routes are in
      the `More` flyout (this is what found the accounts counts-row overflow, §6.1).
- [x] `06: a panel stays reachable in the phone layout` — the panel opens with a barrier behind
      it, minimizes to its bar (`PanelsManager.minimize()`), and restoring brings its fields back.
- [x] `07: Escape closes a flyout` — the bell.
- [x] `08: the back arrow goes back one screen at a time` — patients → calendar → back → patients
      → back → dashboard, and with nothing behind it the arrow is gone.
- [x] `09: the theme switch changes the app brightness` — `FluentTheme.brightness` flips and the
      action icon follows it.
- [ ] Not covered: the bottom-nav *drawer* at phone widths (`routes.showBottomNav`'s companion),
      and the portrait clipping the video work recorded for Dashboard/Notes (§6.2).

---

## §3. P2 — external services and the long tail

### 3.1 `ai_services` (every test here uses `skip:` — they call the `dataextraction` Worker)

- [ ] `01: audio transcription fills the dental notes`
- [ ] `02: a receipt photo fills the expense fields`
- [ ] `03: post-op notes are generated from the appointment`
- [ ] `04: a Worker failure is reported and the draft is not lost`
- [ ] `05: a very long recording is rejected with a reason`
- [ ] `06: the transcription locale setting is respected`
- [ ] `07: cache reset clears the stored extraction state`

**Not written as of 2026-09-28.** There is no `groups/ai_services.dart` in the tree at all,
so this is a block of tests to author, not a group to re-enable.

### 3.2 `notifications` — **the group file does not exist** (`groups/notifications.dart`)

The heading here used to say "**done** (`groups/notifications.dart`, 7 pass / 4 skip,
verified)". The file is not in the tree: `ef3a3fd` ("Bring back the e2e suite, minus the
parts that test the migration itself") removed it deliberately, because the bell's second
producer was the localpocket change feed (`StoreChangeNotifications`), which the
Hive-restored `lib/` does not have. The entry list below is kept as what the group would
have to cover again; nothing here has been run on this tree.

**Verified green: `+7 ~4: All tests passed!`** (2026-09-25). `04` was the last one out — the
appointment notice's action navigated to `"appointments"`, which is not a route at all (its
`hideOnRoute` had the same wrong string), so the button neither opened the calendar nor hid
itself there; both strings are `calendar` now (§6.1). Its passing also clears the labworks and
notes notices, whose actions the same test walks — it stops at the first bad one, so they were
unverified until this run.

The bell's list has two producers (FCM on Android/iOS, the database's change feed on web and
Windows) plus computed lists. A Windows test can honestly drive the computed lists, the
change-feed decision and the deferred queue; FCM, the relay's delivery and the platform
permission are not observable from here and are skipped with their reasons.

- [x] `01: the bell counts today's appointments on the first open` — asserted as a *delta* (the
      suite shares one clinic) and against the badge; this is the regression it was written for:
      the bell used to open with the counts of the previous refresh, i.e. zeros.
- [x] `02: an appointment today raises an in-app notice` — title, icon and its action.
- [x] `03: a due labwork raises its own notice` — an appointment with `hasLabwork`, not yet
      received, is counted by `dueLabworks` and drawn with its count.
- [x] `04: every notice action names a route that exists` — and, by calling it, that it opens
      that route. **This found a real bug**: the appointment notice said `"appointments"` in both
      its `hideOnRoute` *and* its own `routes.navigate` call, where the route's identifier is
      `calendar` (§6.1).
- [x] `05: the deferred queue holds one entry per record` — a second push for the same record
      replaces the first; clearing a store's queue leaves nothing behind. Driven directly, and
      the test says why: `PushRelay.sendPush` is fire-and-forget, so it cannot be made to fail
      without cutting the machine's network.
- [x] `06: a change-feed row decides its notice without throwing` — a remote change for this
      account notifies, another account's does not, a local one does not; the rows come from the
      real store, including the `archived`-less shape the old crash needed.
- [x] `07: login ensures the clinic's key for the relay` — the `notifications_k` row exists with
      a key, and `ensureKey()` returns the same one.
- [ ] `08`/`09` — **skipped**: the FCM prompt and the pointer-events container are the web
      bridge's (`fcm/fcm.js`), and `Messaging.initializeReceiving` does nothing on Windows.
- [ ] `10` — **skipped**: `sendPush` is fire-and-forget (the response is never read), so a test
      can observe neither a delivery nor a refusal; the relay's own state needs a device token.
- [ ] `11` — **skipped**: a permission denial needs a platform with FCM (Android/iOS).

### 3.3 `upgrade` — **done** (`groups/upgrade.dart`, 4 pass)

**Verified green: `+4: All tests passed!`** (2026-09-25).

The whole feature is one piece of device state plus one dialog, and both are reachable without
waiting out startup's ~1s timer: `showDialogsIfNeeded()` (`lib/app/app.dart`) compares
`localSettings.lastSeenVersion` with `version.current()`, shows `changelog.forVersion(current)` and
then remembers the version — so a stale `lastSeenVersion` *is* the state an update leaves behind.

- [x] `01: the changelog entry is shown and then remembered` — first asserts
      `version.current() != '0.0.0'`: that is the "could not read my own version" fallback and
      `showDialogsIfNeeded` skips the changelog entirely when it sees it, so an app that cannot name
      its version never announces an upgrade. Then the entry for that version must exist in
      CHANGELOG.md, and the dialog (raised through `showChangelogDialog(bContext, entry:)`) must
      **name the version** it describes and **contain the entry's first change** — an entry, not a
      bare "what's new" label. Storing the version afterwards is the second half of the feature.
- [x] `02: a skipped release shows the current version's entry only` — with 0.14.1 and the current
      version both in CHANGELOG.md, the dialog's text holds the current entry and (when the two
      entries differ) not the older one's first line: upgrading across several releases is not a
      concatenation of everything missed.
- [x] `03: the new-version dialog is macOS-only` — `needsUpdateNotification` is
      `!kIsWeb && Platform.isMacOS`, so on Windows it is false *and* the dialog is not on screen
      after startup. A platform split that is asserted rather than assumed.
- [x] `04: an upgrade keeps the clinic's data` — a patient created before the "upgrade" is still
      readable after it: the changelog path touches no store (migrations happen on the database open).

**Trap:** the tests that move `localSettings.lastSeenVersion` restore it in `addTearDown`. Leaving it
stale would have the next boot raise the changelog dialog over the login form
(`E2E.dismissStartupDialogs` would cover it, but the app's own state is not the test's to leak).

### 3.4 `errors_and_recovery` — **done** (`groups/errors_and_recovery.dart`, 1 pass / 3 skip verified)

**Verified green: `+1 ~3: All tests passed!`** — `02` is the group's real test and `01` is skipped
for the boot wedge (§6.2).

The shell's errors button is also the reconnect button: with errors recorded it turns red, shows
their count and opens the list; without them it reconnects. Both states are driven through the
app's own controller — what is asserted is the panel and the button, not the plumbing that
reports a failure.

- [ ] `01: the errors panel collects, counts and clears them` — **skipped, kept as the
      regression**: the run stops dead in it (todo.md §6.2). Records two occurrences of one
      failure and one of another (the panel counts repeats as `×2`), asserts the badge, then
      clears them through the panel's own reconnect button.
- [x] `02: proceeding offline disables the sync action and the app works` — the app's offline
      state is `loginCtrl.proceededOffline` (setting `network.isOnline` does not hold: the
      database's sync-status watcher publishes the real connection over it), the sync button is
      disabled, the reconnect button is offered, and the screens still work.
- [ ] `03: a failed local-database open offers a way out` — **skipped**: the only way to fail the
      open is to hand the app a database it cannot read, and the database is opened **once per
      process** — every test after it, and the next run's reset, would inherit it.
- [ ] `04: a corrupted local file is reported, not swallowed` — **skipped** for the same reason.
- [ ] `05: an expired token triggers re-authentication` — not covered: it needs the session
      deleted server-side (`askForLoginAgain` is the path under test).
- [ ] `06: a crash-free start after wiping local data` — covered by the suite itself: every run
      wipes local data and boots into the login screen (`lifecycle_platform 01`).

---

## §4. Cross-cutting checks

### 4.1 Every group runs on both platforms

Run each group with `tools/run_e2e.ps1` (native) and `tools/run_e2e.ps1 -Target web`, and
treat a platform-specific skip as a defect to record, not a pass. Known platform splits:

| Area | Native | Web |
| --- | --- | --- |
| Login, patients, appointments, labworks, notes, expenses, insights, accounts, settings | yes | yes |
| File picker / attachments | yes | yes (blob path) |
| DICOM folder watching, auto-scan | yes | no (upload only) |
| FCM push | yes | relay/JS path |
| Screenshots on failure | no | yes |
| Second-tab guard | n/a (always false) | yes |
| Local data wipe between runs | yes | no (browser profile) |

### 4.2 Accessibility

**Group `tooth_chart` — written, 3 pass / 2 skip.** The chart is driven through the patient panel's
dental-notes tab, which is the chart a user edits; conditions land in the panel's *draft*, which is
exactly what the tooth keys reflect (`WK.tooth(iso, selected:)`), so a test can see which tooth a tap
recorded without saving anything to the record.

- [x] `01: every permanent tooth is drawn and keyed by its ISO code` — all 32, by key.
- [x] `02: a tap records the condition on the tooth it was drawn on` — **the recorded regression**:
      the node for tooth 11 used to open 12. Both neighbours are asserted too, because "recorded
      somewhere" is not the claim; "recorded on this tooth and no other" is. It passes, which is
      what proves `TeethSelector`'s fix (the action attached to the tooth's own node rather than to a
      label-only semantics node) holds.
- [x] `03: two teeth keep their own conditions` — `36` and `37` each keep theirs, and `35`, `38`, `46`
      are asserted clean.
- [ ] `04: the label inside a tooth follows the notation` — **skipped, kept as the regression**:
      driving the notation card and *then* opening a chart leaves the chart without its nodes. The
      wait inside `openChart` for the tooth key passes, and by the time the label is read the node is
      gone (`Bad state: No element` through `Fixtures.labelText`, the shared helper — so it is not a
      finder-shape problem). The rules themselves are pure (`_isoToUniversal`: 18→1, 11→8, 48→32) and
      the labels are drawn by `DentalNotation`; what is untested is the card changing a chart opened
      after it.
- [ ] `05: the state wheel names the tooth it will write to` — **skipped** for the same reason; worth
      unblocking with `04`.
- [ ] Do **not** write a test for the Windows `AXTree` error flood: it is an upstream engine
      bug (`ax_tree.cc`), not reproducible from the app alone.

**Group `accessibility` — written, 4 tests: `+4: All tests passed!`** (2026-09-25). The app is
Flutter, so its accessibility tree *is* the `Semantics` tree and
`tester.getSemantics(finder).getSemanticsData()` is exactly what a screen reader is handed
(`flagsCollection.isButton` / `.isTextField`; `hasFlag`/`SemanticsFlag` are deprecated and not
exported at this Flutter version).

- [x] `01: every screen's primary action is an announced button` — new patient, new appointment, new
      note and new account: each has to be a *button* with a non-empty label, so it can be announced
      and activated rather than being an icon nobody can name.
- [x] `02: the search field keeps its own semantics boundary` — the regression recorded in
      `screen_command_bar.dart`: the field once merged into the whole content area (~780x620 in the
      web build) and an assistive click then hit a list row underneath. The assertion is about
      **size** — the field's node must be no larger than the `TopSearch` bar that owns it, and must
      stay a bar (`height < 200`). **Width is not the property:** the field is `Expanded`, so its
      width legitimately *is* the content width (1264 here), and an assertion on it fails on a
      correct app. `SemanticsNode.rect` is also in its *parent's* space, so it cannot be compared
      with `tester.getRect` (global) — the sizes can.
- [x] `03: a dialog keeps focus and hands it back` — the notes board's add-column dialog
      (`WK.btnAddColumn`: a `ContentDialog` whose title field is autofocused) must hold focus while
      it is up and release it when cancelled. `WK.panelArchive` is *not* a dialog — it opens a
      fluent `Flyout` (`ConfirmDeleteFlyout`), so waiting for a `ContentDialog` after it burns the
      full timeout.
- [x] `04: the command bar answers the keyboard` — Tab until focus lands on the search box's own
      `FocusNode` (up to 80 stops; on failure it prints the trail of stops it reached), then
      `tester.enterText` proves the field is the one that takes input. **Comparing
      `primaryFocus.context` to the `EditableText` element can never be true** — the attached context
      belongs to a `Focus` widget below it — and a raw key event inserts no text in a widget test
      (there is no platform IME), so neither half can be faked.
- [ ] `05: the semantics tree is reachable in a browser` — **web only, not written**: on web the
      semantics tree stays off until the placeholder is clicked
      (`page.evaluate(() => ph.click())` on `flt-semantics-placeholder`, which is off-viewport), so
      the native group above cannot cover the browser's own exposure of it. It needs a web run of
      this group (§0.4: `flutter drive`, one file per run, no per-test filter).

### 4.3 Test mechanics worth knowing before writing these

- **A "restart" inside a run is not a restart.** Re-pumping `ApexoApp` (`E2E.boot`) gives a
  clean widget tree, but the app's singletons — `login`, the stores, the open database —
  keep running. Tests that mean "the process started again" (§1.1 `11`, §2.16 `02`) need a
  second `flutter test`/`drive` run with the state left behind, not a re-pump.
- **The reset happens once per run, on the first `E2E.boot`.** A test that needs a known
  baseline seeds its own data instead of relying on an empty server (§0.1).
- **Web has no test filter** (§0.4): `flutter drive` rejects `--plain-name`, so a web run
  executes a whole file — `tools/run_e2e.ps1 -Entry <file>` picks which file.
- **`SemanticsNode.rect` is expressed in its *parent's* space**, with the transform carried
  separately, so it cannot be compared with `tester.getRect` (global). Compare **sizes**
  (`field.rect.size` vs `tester.getSize(widget)`) — the two differ by the nav pane's offset even when
  they describe the same box (0,0-origin vs 328,102 in one run).
- **`find.text('Cancel')` matches two widgets**: a `Txt` renders a `Text` of its own, so the label
  appears twice. Ask for the *button that has the text*
  (`find.widgetWithText(FilledButton, txt('cancel'))`) or use `E2E.tapFirst`, which taps `.first`
  itself rather than nesting a `.last` inside another finder (that shape throws from the mismatch
  description instead of naming the real failure).
- **A panel's delete confirmation is a fluent `Flyout`, not a `ContentDialog`**
  (`DeleteButton` → `showFlyout` → `ConfirmDeleteFlyout`): `waitFor(find.byType(ContentDialog))` after
  `WK.panelArchive` waits out its whole timeout. For a dialog that is reliably up, use one with an
  autofocused field (the notes board's add-column dialog).
- **A raw key event inserts no text in a widget test** — there is no platform IME, so
  `sendKeyEvent(keyA)` never reaches an `EditableText`'s controller; `tester.enterText` is the only
  way to type. And "the keyboard arrived" must compare **focus nodes**
  (`FocusManager.instance.primaryFocus == tester.widget<EditableText>(f).focusNode`): comparing
  `primaryFocus.context` to the `EditableText` *element* is never true, because the context belongs to
  the `Focus` widget *below* it.
- **A batch must start from a tree that compiles, and must not be edited while it runs.** An
  `integration_test` edit that leaves a compile error (or a concurrent `lib/` refactor) makes every
  *later* group fail at `+0 -1` with `Failed to load …: Build process failed` while the group already
  running is unaffected — which reads as six unrelated failures. Check `flutter analyze lib
  integration_test` immediately before launching.

### 4.4 Scale and performance budgets

**Written and green: `perf_budgets` = `+7: All tests passed!`** (2026-09-25; `02` was red once on a
harness race that `E2E.boot` no longer has — `boot` waits for the app's own restore now, §6.3 — and
the group was re-verified green on 2026-09-26 after the `title` fixture fix and a hand-back that
**verifies** itself, §6.2/§6.3). The
group seeds real
volume into the store (one bulk write each) and asserts a **budget** per screen while printing the
measurement, so a regression shows up as a number that grew rather than as a flaky red test. The
budgets (20–30s) are generous on purpose: they are there to catch an order-of-magnitude change (an
N+1 read, a missing index, a synchronous decode of every row in `build`), not a stopwatch
difference. **Measured on this machine:**

| Step | Measured | Budget |
| --- | --- | --- |
| Seeding 1000 patients (one `putAll`) | 608–795 ms | 30 s |
| Seeding 200 visits across the month | 556–910 ms | — |
| Patients screen with 1000 patients | 1483–1746 ms | 20 s |
| Calendar with 200 visits in the month | 3262–3482 ms | 25 s |
| Search over 1000 patients | 266–286 ms | 15 s |
| Insights over the seeded month | 1770–1835 ms | 30 s |
| Notes board with 200 notes in one column | 1212–1262 ms | 25 s |

`06` — handing the seeded rows back — is the group's slowest test by far (**~3 of the group's 4
minutes**): PocketBase has no bulk delete, so a thousand rows is a thousand requests (against a
server the same process is also syncing with), and the loop keeps going until a fresh **read** of the
server says nothing of this group's is left (§6.3).

- [x] `01: the clinic is filled to scale` — the fixture, run as a test: since `setUpAll` has no
      tester, and the clinic database is only opened by a login inside a test, the seeding had to
      be the group's first test (`Bad state: The database is not open yet` proved it).
- [x] `02: the patients screen opens with 1000 patients` — timed to the list's *own total*, not to a
      row: the list is paged **and** sorted by a column that is not the title, so page one need not
      hold any seeded name (waiting on one timed out; the search test over the same rows passes).
- [x] `03: the calendar opens a month holding 200 visits` — cross-checked against
      `chartsCtrl.filteredAppointments`, which is also what caught the seeding bug below.
- [x] `04: searching 1000 patients finds one row` — a name from the middle of the seeded range,
      which is not on the first page.
- [x] `05: the insights screen aggregates the seeded visits` — the count, not the drawing.
- [x] `06: the seeded rows are handed back` — the suite shares one clinic, and a leftover thousand
      patients would change every other group's paging and search. Asserted on the *rows*: the
      search box holds the text being searched for, so a plain `textContaining` matched the field
      and not a patient.
- [x] `07: the notes board opens a column holding 200 notes` — the board is the app's heaviest
      screen (every column is its own list of note cards, and each card reads the note it draws),
      and its fixture is the cheapest kind: `Fixtures.seedNotesBulk` writes a column —
      **a column *is* a note with `isColumn: true`**, which is what makes seeding one a store write
      rather than a dialog-driven one — plus two hundred notes in two `putAll`s. The budget is on
      *opening* the board with that column in it; the cross-check is that every seeded note comes
      back (`Fixtures.storedNote('e2e note 0199')` reads through the board's own query), so a board
      that quietly dropped rows cannot pass by being fast. Deliberately **not** "scrolls without
      jank": frame timings are not assertable here and the columns are lazy, so that would be a
      proxy for something nothing measures.
- [ ] `08: a cold web start with a warm OPFS database beats the bootstrap bound` — web only
      (§0.4: `flutter drive`, no per-test filter).
- [ ] `09: the group's own seeding stays out of every other group's way` — asserted inside `06`
      today (a leftover thousand patients would change every later group's paging and search).

**Bug found while writing it (in the fixture, not the app):** the bulk id helper folded the row
index with `i % 100`, so rows 0 and 100 were the *same* id — a seed of a thousand patients wrote a
hundred, and a seed of two hundred visits collapsed to exactly the hundred the insights assertion
then reported (`Expected: a value greater than or equal to <200> Actual: <100>`). Ids are now
`prefix + 9 stamp digits + 4 index digits` (fifteen alphanumerics, and the index fits whole).

---

## §5. Suggested order

1. §6's open questions — they block a whole group each.
2. §1.2 patients_crud leftovers (sort, views, show-more, Deleted Items restore).
3. §1.4 appointments_crud — `03` is the keystone test for the calendar, the dashboard and
   the panels.
4. §1.3 patient_panel, §1.5 appointment_panel, §1.6 sync_offline — the core loop.
5. §2.2 labworks, §2.3 notes, §2.5 expenses, §2.1 dashboard, §2.6 insights.
6. §2.7 accounts + permissions, §2.9/§2.10 settings, §2.11 backups, §2.12 dicom, §2.13 portal.
7. §2.14 localization_rtl, §2.15 multi_clinic, §2.16 lifecycle_platform.
8. §3 and §4 as they become affordable.

Each new group is one file under `integration_test/groups/` plus **one line in
`e2e_test.dart`** — a group that is not registered there silently does not run.

---

## §6. Found while writing these (all verified, none of them guesses)

### 6.1 Fixed

#### 2026-09-28 — the migration branch's fixes are *not* in this tree either

Everything below with a "found by" line was found and fixed against the **localpocket
migration branch**, which `af8e771` rolled back — so the code went with it and the restored
suite walks into the same bugs again. Re-applied here, in the order they were re-found:

- **`ItemTitle`'s avatar initial cut an emoji in half.** `settings_general` was `+0 ~4 -4`:
  every test in it died on `Invalid argument(s): string is not well-formed UTF-16` (see the
  §6.2 entry below for what that looks like), thrown while building a `TextSpan` from the
  screen's landing state — no app frame in the stack, and the same burst in all four tests.
  Found by printing the offending data from a temporary unpaired-surrogate check in
  `Txt.build` (`"\ud83d"`, one code unit) and then the titles from a check inside a
  replacement helper: **appointment titles are built from `DF`'s formats, which start with
  `📅`** (`settings_stores.dart`), so every screen listing appointments was one frame away
  from it. `initialOf(Model)` returns `String.fromCharCode(title.runes.first)` now.
  **`settings_general` `+4 ~4: All tests passed!`** — which is also what its documented
  "4 pass / 4 skip" always said.
- **The appointment history flyout's header overflowed by 18px** (§2.4 entry below has the
  detail): `appointments 12`'s `Row` in `open_appointment_panel.dart`, both halves
  `Flexible` + ellipsis now.
- **`WK.fieldLabworkLabName` was attached to two widgets** — the lab-name box *and* the
  order-notes box beside it, so the key matched twice and `WK.fieldLabworkOrderNotes` (which
  the suite waits for) was attached to nothing. The notes box carries its own key now, and
  `WK.fieldLabworkReceived` / `WK.fieldLabworkAppointment` are attached.
- **The three clipping bugs are back** and are fixed through one helper this time:
  `lib/utils/clip.dart` (`clipCodePoints` clips by code point; `fitsInCodePoints` is the
  "does it need clipping at all" half). `isoCC()`'s `substring(0, 2)` (a pasted flag emoji is
  four code units), the 14-character name cuts in the calendar, notes and insights screens,
  and the patient label's 10-character cut all go through it.
  `test/unit/utils/clip_test.dart` pins the property rather than the arithmetic: every
  prefix length of an emoji-bearing label must be *well-formed UTF-16*.
- **A multiline tag field was 4px short of its own contents** (`appointments 14`: *"prescriptions
  can be added and removed"*). `TagInputWidget` forced `height: visibleTags.length * 40 + 40` on
  the box in **both** modes, and the box then hands its child `height − 8` — a 1px border *and*
  3px padding on each side, where the formula only budgeted its own 6px of padding. With one
  chip the field's column had 32px for 36px of content. On top of that, `AnimatedSize` keeps
  the chip block at its **old** height for the 250ms it animates down, and the multiline chips
  are a `Column(spacing: 3)`, which the formula does not know about either. So removing the
  prescription the test had just added reported
  `A RenderFlex overflowed by 4.0 pixels on the bottom` — with a *defunct* render object, which
  is why the message points at no widget ("creator: … (DEFUNCT)", and no
  "error-causing widget" line). The identity was recoverable from the dumped creator chain
  (`… ← StatefulElement ← _LayoutBuilderElement ← StatefulElement ← ParentDataElement<FlexParentData> ← Flex`)
  plus the numbers: a tight 32px child box with a 4px offset is a 40px container with the
  borders and padding the formula forgot. A **multiline** field sizes itself now
  (`height: null`) and its input box is not an `Expanded` (a flex child of an unbounded
  `Column` is a layout error); the row case keeps its one-line height. **Measured after the fix:
  `appointments 14` passes** (the group is `+14 ~1` with it).
- **Archiving from an edited panel left it dirty** (`appointments 11`: *"deleting from the
  panel and closing does not warn"*). `RowPanel.setArchived` archived the record without
  re-baselining the panel's snapshot (`markSaved()`), so `hasPendingEdits` still compared the
  draft against what the panel looked like when it opened: the header kept saying **Cancel**
  over work that was already stored, and `closePanel` met the "close anyway?" flyout —
  `Fixtures.closePanel(allowPrompt: false)` is the test's whole point, so it waited out its
  60s: `Timed out after 60s waiting for the panel to disappear`
  (`fixtures.dart:177` ← `appointments.dart:238`). `persist()` had always re-baselined
  (`markSaved()`); the archive path is a store write of its own and has to do the same.
  **Measured after the fix: `appointments 11` passes** (the group is `+14 ~1` with it).

#### 2026-09-28 — on this tree (Hive data layer, after the migration rollback)

Measured before/after with `pwsh -File tools/run_e2e.ps1 -Group lifecycle_platform`
(`+3 ~1 -5` → `+6 ~1 -2` → **`+8 ~1: All tests passed!`**, 1m37s).

- **The "route-open failure" is a missing key, not a routing bug.** `Fixtures.openRoute`
  waits for the target screen's key after the nav tap; the tap lands (measured with a
  throwaway diagnostic test: after tapping the patients item, `pane.selected = 1`,
  `items = 11`, `routes.currentIndex = 1`, `routes.currentRoute().id = 'patients'` — fluent
  *did* jump the body), and then the wait times out because **the key it waits for is
  attached to nothing**. **52 of the keys the suite waits for were declared in
  `lib/widget_keys.dart` and attached to no widget in `lib/`** (audit: `tools/key_audit.ps1`).
  That is what made whole groups red, what kept tripping `settings_services 01` and
  `backups 01` "in a fresh process", and what the harness had grown a retry workaround
  around. It is **not** a regression from the 2026-09-28 routing refactor, and not a fluent
  bug: a bare `NavigationView` + `NavigationPane(selected: …)` follows its selection
  correctly (`test/widget/app/navigation_body_test.dart`).
- **Fifteen of them are re-attached**: `WK.btnNewPatient`,
  `WK.btnNewAppointment`, `WK.btnNewAccount` / `WK.btnNewAdmin`, `WK.btnNewSupplier`,
  `WK.btnNewLabwork`, `WK.btnNewNote` (the six screens' command bars — they are what
  `Fixtures.openPatients` / `openCalendar` / `openAccounts` / `openExpenses` / `openNotes` /
  `openLabworks` wait for), the account panel's `WK.fieldAccountName` /
  `WK.fieldAccountEmail` / `WK.fieldAccountPassword` / `WK.accountOperates` /
  `WK.permissionSelector(id)` (`Fixtures.createAccount` and `Fixtures.setAccountEnabled`
  wait for those), `WK.listSearch` (`TopSearch`'s `CupertinoTextField`), `WK.showMore`
  (`ShowMoreBar`'s button), and `WK.globalAction(id)` — which needed a stable id on the
  shell's actions (`NetworkAction.identifier`: `notifications`, `theme`, `sync`, `errors`).
  37 remain; §0.2 lists them.
- **`NetworkAction.disabled` was dead code again.** The flag is set in four places
  (sync/errors while a sync runs, while the session works offline, while there is nothing to
  reconnect) and `_buildActionIcon` passed `onPressed` straight through, so a disabled action
  was still pressable and a tap on it did nothing instead of failing loudly.
  `Fixtures.globalActionDisabled` (and the sync tests that rely on it) need the widget to
  honour the flag: it now passes `null` when `disabled == true`.
- **The pane header overflowed by 214px in a minimal pane** (`CurrentAccount`,
  `lib/common_widgets/current_account.dart`) — found by `lifecycle_platform 05`, which
  narrows the window to 300px on purpose and died on
  `A RenderFlex overflowed by 214 pixels on the right` before it could assert anything. It was
  a fixed 130px name box beside the logout button in the ~26px strip a minimal pane gives the
  header. Now a `LayoutBuilder`: below 150px the header draws nothing at all (a minimal pane
  lays it out in the hamburger's strip, where neither a name nor a logout label fits; the
  logout is also on the dashboard's command bar), above it the name is `Flexible` + ellipsis
  inside an `Expanded`. This is the §6.2 bullet that used to say "still overflows" — it is
  fixed again, and the note is gone from there.
- **The accounts screen's counts strip overflowed** — `5.3px` at a 1280px window, and its
  refresh button's inner `Row` (default `mainAxisSize.max`, inside a `Row` that hands a
  non-flex child *unbounded* width) claimed whatever the bar had and reported `16px`. It is a
  `Wrap` now and the button's row is `mainAxisSize: MainAxisSize.min`. Pinned by
  `test/widget/features/accounts_counts_row_test.dart`, which reproduces both in under a
  second at 1280/1264/710/300px instead of costing a 30s e2e run per attempt.
- **The deferred-push queue could only be initialized once, per process.** `_DeferredPush.hiveBox`
  (`lib/services/notifications/push_deferring.dart`) was `late final`, but `reset()` exists so
  that the *next* login re-runs `init()` for its own clinic server — and assigning a `late final`
  twice throws `LateInitializationError`. The throw landed inside `Messaging.identifyDevice`,
  which `login.activate` awaits, so on **every login after the first one in a process** the
  clinic's relay key was never ensured and no device was registered. Found by `accounts 08` —
  the group's only test that signs in twice — which failed with
  `#1 _DeferredPush.hiveBox= … #2 _DeferredPush.init … #3 _LoginService.activate` until
  `late final` became `late`. `accounts` is `+8 ~2` with it.
- **`Fixtures.openRoute` now settles past the pane's transition.** The ready key appearing is
  not the same as the pane having *finished* swapping screens: fluent wraps the body in an
  `AnimatedSwitcher`, so the screen being left stays mounted for its 250ms transition — and
  two screens mounted at once means two `WK.listSearch` boxes, which throws
  `Bad state: Too many elements` in whichever helper types into one next.
- **The login screen's "clear" button did not clear the form** (`lib/features/login/login_screen.dart`).
  It ran `login.logout(true)`, which empties the *stored* url and email — but the three fields
  hold their own `TextEditingController`s, and the screen's observer (`fillFromPersistence`)
  only ever writes a **non-empty** value back, so the address and the email stayed on screen:
  a form that looks signed in with nothing behind it. `login 08` pinned it
  (`Expected: empty / Actual: 'https://pb.apexo.app' — the server url stayed in the field`);
  the button empties its own fields now, and `login` is `+12 ~3`.
- **An offline login never said it was offline** (`lib/services/login.dart`).
  `proceededOffline` means "this session is the offline one" — the shell's sync action disables
  itself on it and the errors action becomes a reconnect — but `activate(online: false)` never
  set it: it only defaulted to `true` on a cold start, so the login that *proceeded offline*
  left it at whatever the last online login made it (`false`), and the shell still offered a
  sync. `login 09` (`Expected: true / Actual: false — the app does not know the session is
  offline`) fails without it; the `else if (!online)` branch sets it now.
- **The first-launch dialog was unreachable** (`lib/app/app.dart`, `lib/services/login.dart`).
  `showDialogsIfNeeded` ran once, from a one-second timer in `ApexoApp.createElement` —
  *before* the login that creates a clinic can set `launch.isFirstLaunch` — and nothing
  re-checked the flag, so the welcome dialog needed a startup where a clinic appeared within a
  second. It is idempotent, so `login.activate` calls it now (as
  `ApexoApp.showDialogsIfNeeded()`, static because it reads only globals); `login 12` waited
  180s for a dialog that could never come, and `login 13` then found `12`'s leaked dialog on
  screen. Both pass.

- **The patient seeders wrote a field that does not exist.** `Fixtures.seedPatientsBulk` and
  `seedPatients` wrote `'name'`, but a patient's name is **`title`** on the wire
  (`Patients.title = schema.text('title')`): a thousand seeded patients had no name at all, and §1.6's
  newly pulled rows kept arriving "nameless". It went unnoticed because the one test that reads those
  names (`perf_budgets 04`) asserted `find.text(wanted)` — which also matches the **search box**
  holding the very string being searched for, so the test passed on its own input. Both seeders write
  `title` now, that assertion is scoped to a **row**, and the second-writer helper writes `title` too.
- **The scale fixture's "handed back" was only half true.** With the seeded patients finally *named*,
  `perf_budgets 06` stopped passing on an empty list and showed what the purge actually did: purging
  only **locally** does not stick while the server still holds the rows — one pass left **24**
  patients in the clinic and a second left 28 (so it is not a race that settles; see §6.2). The test
  now deletes them on the **server** first (bulk, in parallel batches — PocketBase has no bulk
  delete), purges locally, syncs, and waits for **both** sides to be empty (bounded).
- **The navigation pane's header overflowed by 214px the moment the pane went compact.**
  `CurrentAccount` (`lib/common_widgets/current_account.dart`) held a fixed 130px name box in a `Row`
  with the logout button, so a pane with ~26px of inner width — a panel open on a 1280px window, or
  any phone layout — carried 230px of content. Found by `lifecycle_platform 05`, which narrows the
  window to 300px on purpose (the phone bar's *More* flyout needs a bar that cannot fit its routes)
  and died on `A RenderFlex overflowed by 214 pixels on the right` before it could assert anything.
  Two steps, because there were two overflows behind each other: the name is `Flexible` + ellipsis
  inside an `Expanded` group (which took 214px down to 61px — *the button's own width* is what was
  left), and below ~150px the header draws **nothing at all**, since a **minimal** pane lays it out
  in the hamburger's strip where neither a name nor a logout label can exist. The logout it holds is
  also on the dashboard's command bar, so nothing became unreachable.
- **A disposed screen kept being notified, and `unObserve` could never drop it.** Observers are
  compared with `identical()` in `lib/core/observable.dart`, and a **method tear-off** is a new
  object every time the method is mentioned: `login.observe(fillFromPersistence)` and
  `login.unObserve(fillFromPersistence)` were never the same function, so `dispose()` removed
  nothing. Deliveries also travel through a broadcast *stream*, so the notification carrying the
  restored session could land after a screen was gone. Both halves came out in one line of the
  app's own log: `Error while notifying an observer: A TextEditingController was used after being
  disposed` (`_LoginScreenState.fillFromPersistence` — reported to Sentry on every sign-in), plus a
  silent second copy of the same observer on every rebuild. Fixed by comparing with `==`, which is
  the language's own rule for two tear-offs of the same method on the same receiver and exactly
  what the documented *"registering the same function twice changes nothing"* meant; the login
  screen also guards with `if (!mounted) return;`. Regression:
  `test/unit/core/observable_test.dart` → "unObserve drops a method tear-off". Found by the
  `perf_budgets` run — the app logs its own errors into the test output, so the e2e suite sees
  them.
- **Signing in could hang forever on one slow request.** Every optional server step of the online
  login — the `data`/`public`/`profiles` probes, `initializePocketbase`, `initializeProfiles`,
  `reconcileSchema` and `Messaging.identifyDevice` — calls the server through the `pocketbase`
  client, which has **no request timeout**, and the surrounding `catch` blocks only handle
  *failures*, not hangs. A request that never answers therefore parked the login on that step's
  loading label for good, while each of those steps is re-attempted on the next sign-in. Each one
  is bounded now (`_loginStepTimeout`, 60s, in `lib/services/login.dart`); giving up is safe and
  the failure path is what those steps already had. Found while chasing the e2e wedge below: the
  harness resets the server immediately before its first login, so every one of those steps runs
  against a cold, just-initialized PocketBase on every run.
- **A notice's "view" button neither opened the screen nor hid itself on it.** Both halves of
  one appointment notice were wrong in `static_notifications.dart`: `hideOnRoute` said
  `"appointments"` (the route's identifier is **`calendar`**, and the flyout compares the value
  against `routes.currentRoute.identifier`, so the button stayed while the user was already
  there) *and* the action itself called `routes.navigate("appointments")` — a route that does
  not exist, so pressing **View** did nothing at all. The change-feed dispatch in
  `static_notification_dispatch.dart` had the identifier right all along. Found by §3.2 `04`,
  which asserts that every notice action names a route that exists **and** opens it.
- **The settings screen could spin forever.** Its `_load()` read the six app-scoped settings in
  one `try`, and any single throw — the store facade throws until the database open completes,
  and this screen is rebuilt while the database is opened or closed under it (login, a resync,
  the local-data reset) — left `_loaded` false, so the screen showed a `ProgressRing` and
  nothing else, silently (the `catch` swallowed the reason). Seen as
  `settings_services 01` timing out on "the settings screen" once per run while every later test
  in the same run passed. It now retries a few times and logs the failure if every attempt
  fails.
- **A clinic database holding a `localOnly` store cannot sync — so the app could not log in
  at all.** The deferred-push queue was declared `localOnly: true` *inside* the clinic
  database. localpocket 0.3.7+ refuses PocketBase sync for any database holding such a store
  (0.3.8 rejects the attachment at the open), so `AppDatabase.open` threw
  `ValidationException: Cannot attach PocketBase sync: store "deferred_push" is localOnly` on
  every fresh clinic — and the login flow caught it and failed loudly
  (`localDatabaseFailed`), leaving the app on the login screen with no database behind it.
  Found by the `backups` group, whose every test failed with **"The local database never
  opened after signing in"** (`E2E.waitForDatabase`) with that exception in the log above it.
  Fixed by moving the queue into the **device** database — which is opened `localOnly: true`
  database-wide and never syncs, so device-local state belongs there — with a `clinic` column
  (`login.url`) so one device database can hold several clinics' queues without ever sending
  one clinic's notification through another clinic's relay key. The store went to version 2
  for the column; the clinic's store list no longer mentions it; the regression is
  `test/unit/services/notifications/push_deferring_test.dart` → "a clinic database that no
  longer holds the queue still syncs" (attaching no longer throws). Undelivered retries queued
  before the change are dropped with the old table.
- **The app logo overflowed its row in a compact pane.** `AppLogo` is a fixed-width Row
  (icon + name + version) and also sits in the navigation pane header, which goes compact as
  soon as a panel is open on a 1280px window: `A RenderFlex overflowed by 99 pixels on the
  right`. Fixed with a `FittedBox(fit: BoxFit.scaleDown)` — the row scales instead of
  overflowing.
- **`Backend.resetLocalData()` did not wipe the local database.** It deleted `*.hive` and
  `*.lock` only, and the migrated stores live in `localpocket`'s SQLite file: every run
  inherited every patient from every earlier run while the server was reset to empty. Now it
  also deletes `*.db` with its journal/WAL siblings and each clinic's attachment directory
  (found by its `blobs` child — the root is `apexo-<clinic hash>`, not `localpocket_blobs`,
  which is the web worker's OPFS directory and never exists on this path).
- **A picker built before its list arrived never showed its suggestions.**
  `TagInputWidget.didUpdateWidget` only reacted to `initialValue`, never to `suggestions`, so
  a picker whose rows load asynchronously (the appointment panel's patient picker, the
  labwork picker) kept the empty list it was first built with. And even with the list
  updated, `AutoSuggestBox` paints its dropdown from the items it was *last* given, so the
  overlay is now reopened (post-frame) when the suggestions change. Second half: a chip's
  label is `Flexible` + ellipsis and each chip is capped at the row's width, because a long
  patient name in a `limit: 1` picker is wider than the field and was overflowing the row
  (`2.0/1.5` pixels, sometimes an outright paint overflow).
- **The suggestion dropdown clipped and overflowed.** Rows are drawn by
  `TagInputWidget._buildSuggestionRow` now: `AutoSuggestBox`'s own row is a `ListTile` whose
  title wraps, so a 26-character patient name became two lines (40px) inside the row the
  overlay allocates (26px) — `A RenderFlex overflowed by 14 pixels on the bottom`, with the
  second line clipped. One line, ellipsized, with the hover and keyboard highlight kept.
- **A failed test poisoned every test after it.** Panels live in the global
  `PanelsManager.active`, so a test that failed with a panel open left it there and the next
  boot rendered it (its `close` then timed out on a panel it never opened). `boot` now calls
  `PanelsManager.closeAll()`, which is also what logout needs.
- **`ItemTitle`'s chip pushed its own row past the box it was given.** The chip (up to
  `maxWidth`) and the treatment labels beside it share a row only as wide as the caller's
  box; a long patient name plus a label strip exceeded it, and the row reported
  `A RenderFlex overflowed by 4.5 pixels` in the dashboard's squares (box ≈150 wide,
  `maxWidth: 123`, 40px of labels). The chip is `Flexible` now — it ellipsizes its own text,
  so it is the side that gives. Only reachable once a visit is booked *for today*
  (the square is fed by `todayAppointments`), which is why the dashboard's own tests should
  keep an eye on it.
- **`openAppointmentTile` waited for a tile the agenda never built.** The day's agenda is a
  `ListView.builder`, so everything below the fold is simply not in the tree — and no finder
  can see it. A *full* run books several appointments on the same day, so a test that books
  late found its own tile outside the built range and failed with
  `Timed out after 60s waiting for the tile for "e2e patient …"` (`patient_panel 06`, twice;
  the same group alone was green, which is what made it look random). The fixture now scrolls
  the agenda (`drag` on the tile's own `Scrollable`) until the wanted tile exists, and the
  failure message reports how many tiles were built, so the next occurrence explains itself.
- **The labwork panel's visit button overflowed by 74px.** `open_labwork_panel.dart` built its
  "appointment: <date> <patient>" button as a `Row` of an icon plus two labels whose `Txt`
  asked for `TextOverflow.ellipsis` **without a flex factor** — an ellipsis does not stop a
  text from laying out at its natural width, so a long patient name pushed the row past the
  303px the open pane gives it (`A RenderFlex overflowed by 74 pixels on the right`, and every
  labworks test failed on it). Both labels are `Flexible` now, and the date label ellipsizes.
- **`WK.fieldLabworkLabName` was used twice.** `LabWorkEditor` keyed both its lab-name
  `AutoSuggestBox` and its order-notes `TextFormBox` with it, so `find.byKey` matched two
  widgets and the notes field was unreachable by key at all. The notes box uses
  `WK.fieldLabworkOrderNotes` (which existed and was unused).
- **Five dead labwork keys removed** (`fieldLabworkaddition`, `fieldLabworkTitle`,
  `fieldLabworkPrice`, `fieldLabworkPaidToggle`, `fieldLabworkPhoneNumber`): the lab price/paid
  feature they belonged to has no schema fields and no widgets left (§2.2).
- **`TagInputWidget` called `setState` while its element was defunct.** fluent's
  `AutoSuggestBoxState.dispose()` runs `_unselectAll()`, which fires every item's
  `onFocusChange(false)` — the app's handler then called `setState`, and the framework
  asserted `'_lifecycleState != _ElementLifecycle.defunct': is not true` *while finalizing the
  widget tree*. The guard in place (`if (!mounted) return;`) does **not** catch it: during
  `dispose()` `State.mounted` is still `true` (`_element` is only nulled after `dispose()`
  returns) while the element is already defunct. `if (!mounted || !context.mounted) return;`
  is the honest check. It surfaced as every labworks test failing with "This test failed after
  it had already completed", attributed to whichever test ran next — the panel that owned the
  picker was simply being closed. Reported against fluent_ui 4.13.0 as well: firing user
  callbacks from `dispose()` is not something a caller can defend against except this way.
- **The labwork editor re-dirtied its draft right after a save.** `AutoSuggestBox` re-emits the
  text it already holds (its controller listener fires on every change), and the editor wrote it
  back unconditionally — so the panel was dirty again the moment it was saved and
  `Fixtures.save` waited forever for "nothing to save". Both handlers now compare first (a
  picker whose value did not change marks nothing dirty).
- **Two attachments with the same filename collapsed into one.** `_rewriteColumn`
  (`lib/features/appointments/attachments.dart`) skipped naming the file it had just been
  handed whenever the column already carried that *name* — `_columnNames` compared labels —
  so the second of two same-named uploads stayed in the store with nothing naming it: absent
  from the gallery, and an orphan to anything that reads the column. Found by §2.4 `12`,
  which is now the regression. The rule is: name a reference the record did not already have
  (`uploadAppointmentFile` compares the ref count across `attach`, since `attach` dedupes
  identical bytes by handing back the existing ref), and skip only a ref PocketBase has
  already named, or one sharing the added file's `group` (an X-ray and its preview).
  `test/unit/features/appointments/appointment_attachments_test.dart` covers both halves
  (17 tests, including "a second attach of identical bytes reuses the reference").
- **The appointment history flyout's header overflowed by 18px.** Its title row
  (`open_appointment_panel.dart`, the `Row` inside the `FlyoutContent`) laid out the icon, the
  "other appointments (n)" label and the patient's name at their natural widths inside a
  340px flyout, so `A RenderFlex overflowed by 18 pixels on the right` failed `appointments 12`
  (a layout overflow reds whatever test is running). Both halves are `Flexible` with
  `TextOverflow.ellipsis` now.

- **A truncated emoji made Flutter's paragraph builder throw.** A string holding half of a
  surrogate pair is not valid UTF-16, and `RenderParagraph` refuses it:
  `Invalid argument(s): string is not well-formed UTF-16`, thrown while *building a TextSpan* —
  so it reds whatever test happens to be running, with no app frame in the stack. Three plain
  cuts could produce one, and all are character-aware (`characters`, now a declared
  dependency) instead of `substring`: `ItemTitle`'s avatar initial (`substring(0, 1)` on a name
  that starts with an emoji), the 14-character name cuts in the calendar, notes and insights
  screens, and the ISO country code the phone parser reads
  (`settings_global_store.dart`, `substring(0, 2)` — a flag emoji is *four* code units, so a
  country code stored as `🇺🇸` became a lone surrogate). Found by §2.9: **every** settings test
  failed on that exception, and the settings screen draws exactly that country code
  (`2 issues → 1` after the fix; the remaining one was the harness's fault).

- **The dashboard's card headers overflowed in every non-English locale.** The title `Row` in
  the dashboard columns (`dashboard_screen.dart`) laid its `Txt` out at its natural width beside
  the card's icon button, so the longer translations pushed it past the column it is given:
  `A RenderFlex overflowed by 138 pixels on the right` (Persian/Greek/Arabic), 54, 49 and 30 in
  the others — found by §2.14 `01`, whose whole point is rendering the shell in each language.
  The title is `Flexible` + ellipsis now.
- **The deferred-push queue could only be initialized once.** `_DeferredPush.hiveBox`
  (`push_deferring.dart`) was `late final`, but `reset()` exists so that the *next* login re-runs
  `init()` for its own clinic server — and assigning a `late final` twice throws
  `LateInitializationError`. The throw happened inside `Messaging.identifyDevice`, which
  `login.activate` awaits, so on **every login after the first** in one process the clinic's
  relay key was never ensured and no device was registered. Every suite run's log carried it
  (`Could not initialize notifications: LateInitializationError: Field 'hiveBox' has already
  been initialized`) and it was dismissed as noise until the notifications group read the code.
  `late` now, not `late final`.
- **The accounts screen's counts row overflowed at phone widths.** `_buildAccountsScreen`'s row
  of the refresh button plus `admins: N` / `users: N` is laid out at its natural width, so at
  300px (`lifecycle_platform 05`) it reported `A RenderFlex overflowed by 5.3 pixels on the
  right` — which reds whatever test is running. Both counts are `Flexible` + ellipsis.

- **The login screen's "clear" button did not clear the form.** It ran `login.logout(true)`, which
  empties the *stored* url and email — but the three fields hold their own `TextEditingController`s
  and the screen's observer (`fillFromPersistence`) only ever writes a **non-empty** value back, so
  the address and the email stayed on screen: a form that looks signed in with nothing behind it
  (§1.1 `08`). The button empties its own fields now.

- **`NetworkAction.disabled` was dead code, and the offline shell offered a sync.** The flag is set
  in four places (`sync`/`errors` while a sync runs, while the session works offline, while there is
  nothing to reconnect) and the shell widget passed `onPressed` straight through — so nothing was
  ever disabled. Found by §1.1 `09`: pressing *sync* on an offline session ran `resync()` →
  `login.activate(url, [token], true)` with an **empty** token → `Invalid token` → the user was
  thrown back onto the login screen with "Error while logging-in". `errors_and_recovery 02` asserts
  the *model* flag (`_action('sync').disabled` is true while offline), which is why the claim looked
  covered: what was missing was the widget honouring it. The action button now passes `null` when
  disabled, and `Fixtures.tapGlobalAction` waits for the action to be pressable instead of tapping a
  dead one.

- **An offline login never said it was offline.** `proceededOffline` means "this session is the
  offline one" — the sync action disables itself on it and the errors action becomes a reconnect —
  but `activate(online: false)` did not set it: it only defaults to `true` on a cold start, and the
  login that *proceeded offline* left it at whatever the last online login made it (`false`), so the
  shell still offered the sync above. §1.1 `09` pins it now.

- **The first-launch dialog was unreachable.** `showDialogsIfNeeded` calls its only check from a
  one-second timer at startup (`ApexoApp.createElement`), and `launch.isFirstLaunch` is set by the
  **login** that finds the server has no collections — seconds later, and on any sign-in after a
  server was reset. Nothing re-checked the flag, so the welcome dialog needed a startup where a
  clinic appeared within one second. It is a top-level function now (`lib/app/app.dart`) and
  `login.activate` calls it once it has a session — idempotent, so a normal login shows nothing.
  Found and pinned by §1.1 `12`.

### 6.2 Open — each one blocks a group

> **Read with the note at the top of this file in mind.** Five entries below are about
> **localpocket**, which this tree does not have (`af8e771` rolled it back): *A local purge of
> a synced row does not stick*, *`network.isOnline` never goes false for a paused engine*
> (the `network.onOffline['localpocket']` half), *A server-side delete is invisible*
> (`MissingRemotePolicy.recreate`, `lib/core/db/conflict_policy.dart`), the *46-minute first
> attachment*, and the parts of the settings/portal entries that quote
> `/api/settings` snapshots through a localpocket `Store`. They are kept because they are
> what the migration-era runs found, not because they are actionable here. Everything else
> is about code this tree does have.

- **A local purge of a synced row does not stick, and the reason is in the engine.** `patients.purge(id)`
  removes the row in the local database, but the row is still on the server and the next pull brings it
  back: `perf_budgets 06` purged a thousand seeded patients and found **24** of them in the store
  afterwards, then 28 after a second pass — and 34 in a later run. Not a race that settles, and not a
  timing problem: `Store.purgeDirect` calls `vanishRecordMetadata(..., deleteSyncAndOutbox: true)`
  (`localpocket 0.3.8`, `kernel/store.dart:286` → `kernel/sync/sync_tables.dart:756`), which deletes the
  row's `lp_sync_row` **and** its `lp_outbox` entries and **queues nothing** — there is no delete op in
  `PushOp` at all (only create/update). So a local delete is never pushed, the remote row survives, and
  the pull then sees a remote row it has no record of and re-inserts it. Handing rows back therefore has
  to go **server first** (delete remotely, *confirm*, purge locally, sync), which is what the fixture
  does now. Two questions for the app: should a *local* delete queue a remote deletion, and should a pull
  recreate a row the user deleted here but which still exists there? (This is the same missing delete
  feed as the bullet below.)
- **`network.isOnline` never goes false for a paused engine, and a write made while it is paused is
  never pushed.** Found writing §1.6's `02` (the core sync promise), which is skipped because of it.
  The app's offline state comes from the *engine's* status — `hookDBToNetwork` publishes
  `network.isOnline` from it — and none of the three levers a test can pull produces an offline
  status: flipping the flag itself is republished `true` within a frame (a paused engine still reads
  as online); `network.onOffline['localpocket']()` — the handler the app's own watcher calls
  (`setConnectivity(false)` + `pause()`) — pauses the engine while the shell still offers a *sync*;
  and `setConnectivity(false)` on its own emits nothing at all. Worse: with the engine paused, a row
  created through the panel **never reached the server**, even after resume plus both sync paths
  (the shell's action and the callbacks it runs) — three runs. Two questions for the app: should a
  paused engine read as offline to the shell, and should a paused engine keep the write queued? (A
  *real* offline — a login that cannot reach the server — does queue writes; see §1.6 `02`.)
- **A server-side delete is invisible, and the local copy is not pushed back.** §1.6 `05`: delete a
  row with a second client and sync — the local record stays (right: it is the user's data) and the
  server does **not** get it back (`the server has the row again: false`), so the two sides stay out
  of step until that row is touched again. The incremental pull is keyed on `updated` and PocketBase
  has no delete feed, so no pull can see a delete; the store's `missingRemote: recreate` policy did
  not fire for a row that had already been pushed. Worth a decision: recreate on every sync, or let
  "clear local data" be the only way to drop such a row (what the tests assert today).
  **…but a row this device still has *dirty* is a different story**: `perf_budgets 06` deleted 200
  seeded visits on the server and the app **put them back** — the next push found the remote record
  gone and `MissingRemotePolicy.recreate` (`lib/core/db/conflict_policy.dart`, what every store in
  this app uses) re-created it, so the hand-back needed a second pass for the visits while the
  thousand patients (already settled, no pending op) stayed gone. So "the server deleted it" is
  respected for a settled row and silently reverted for an unsent one.
- **The clinic's display settings are readable without a session.** The `data` collection's list rule
  admits `settings_global` rows to anyone (`@request.auth.id != "" || store = "settings_global"`-shaped),
  which is how the patient portal reads the clinic's currency and prescription header while logged out —
  `PatientSide.activate` does exactly that, and its comment calls it "getting currency". Verified with a
  genuinely anonymous client (`patient_portal 07`): an unauthenticated list of `data` returns one row,
  `settings_global/ISO_country____`, and no clinical rows at all. So nothing patient-related leaks, but the
  clinic's own settings are world-readable. If that is not wanted, the way out is the same as the portal's
  own: a scoped view (like `public`) that exposes only the handful of display settings the portal needs,
  and a `schemaVersion` bump so the reconcile pushes the narrowed rule to existing clinics.
- **A second settings write does not take — through the app *or* the server API.**
  `settings_services 03` writes a marker mail host through the SMTP section, saves it (the server gets
  it — asserted), then tries to put the old host back and the server keeps the marker. Three things
  were ruled out: the field really holds the old value before the save (asserted), the save's own
  dialog reports `smtp_save_success`, and the restore was then done **through the server API**
  (`settings.update`) instead of the UI — which also did not land, and neither did a 20-second poll of
  `settings.getAll()` (`_waitForServerSetting`). So the read is not lagging the write: the second write
  of that key is being ignored. That matters beyond the test — a user editing SMTP twice in a row sees
  the second edit silently not saved — and the clinic's mail host is now left as an `e2e-…` marker
  (`pb.apexo.app` is the test server). The test asserts the first write (its actual subject) and only
  *warns* about the restore.
- **The pane header overflowed when compact — fixed 2026-09-28.** Kept here as the
  resolution of the contradiction between §2.16 and §6.1: `CurrentAccount` is a
  `LayoutBuilder` now (draws nothing below 150px, shrinks its name above it). See §6.1.
- **A *new* tag cannot be driven from the harness.** The non-strict box mirrors only the
  clinic's existing tags into its suggestions (`_updateSuggestions` +
  `_filteredSuggestions` dropping empty labels), so a new tag has nothing to click and Enter
  is the only way in — and a synthetic Enter from `tester.sendKeyEvent` never reached the
  field's focus node (`_commitTypedText`), while the same keystroke works in the running app.
  Either the harness needs a different way to inject the key, or `_commitTypedText` has a
  wiring problem worth a widget test of its own. Until then `patients 07`/`08` stay skipped.
  The appointment panel's patient picker is the *same* widget but `strict: true` with real
  patient suggestions, so it can be driven by picking one from the dropdown — which is what
  unblocked the appointments group.
- **A filename column cannot address two files with the same name.** With the §6.1 bug fixed,
  the column holds the name twice (`['x.jpg', 'x.jpg']`): both files are recorded, but
  `attachmentBytes(rowId, name)` / `downloadFile` resolve whichever reference `_refNamed`
  reaches first, and the two only become distinguishable once PocketBase reports the name it
  stored one of them under. Nothing *loses* a file, but a gallery that lists by name shows
  two identical labels. Needs a decision — an id in the column would break a non-upgraded
  client, and a locally invented suffix would fight PocketBase's own naming.
- **The first attachment of a fresh database can take ~46 minutes.** Seen in
  `tmp/attach2.log`: after the reset messages `attachments 04` ran for 46:45 before passing,
  with nothing logged in between, while every later attach in that run took seconds and the
  next run of the group took 49 seconds end to end. So it is a one-off cost of the first
  attach on a wiped install (the first blob write and/or the first upload session) rather than
  of the attachment path — but a real user's first attach would sit there too, which makes it
  worth understanding. (The boot wedge below is the *same shape* — a first-thing-after-a-wipe
  cost that is invisible while it happens — so treat "the run is quiet and the app is alive"
  as this class of bug.)
- **There is no email validation anywhere.** No `isValidEmail`, no validator, no
  `invalidEmail` string: the patient panel writes whatever is typed straight through, so
  §1.2's "an invalid email is rejected" cannot be written as a passing test. That is a product
  decision (reject, or normalise like the phone number), not a test gap.
- **Archiving a patient hides its appointments from the agenda.** The records survive
  (asserted: the day's appointment count is unchanged) and restoring the patient brings them
  back, but the calendar's agenda cannot resolve the *name* of an archived patient, so the
  visit is not listed while the patient is archived. Worth a decision: keep showing it under
  the patient's name, or say "archived patient" in the tile.
- **The patients screen has no grid/list view**, and `WK.dataTableListView`,
  `WK.dataTableSortBy` and `WK.toggleSortDirection` are declared in `widget_keys.dart` but
  attached to nothing — keys that promise UI which does not exist (like `WK.loginScreen`).
  §1.2 `10` is therefore recorded as a gap rather than a test.
- **A previous visit's dental notes cannot be copied** into the open appointment: the panel
  shows them read-only (an `AppointmentExtraNotes` expander). §1.5 `07` needs that action to
  exist before it can be tested.
- **A patient's panel cannot be reopened after booking a visit.** In `patients 15` the row is
  found (the search returns it and the tap lands on the name inside it), but the panel never
  opens — three runs, always a 60s wait on `WK.fieldPatientName`, while the identical flow
  *without* a booking (`patients 09`) passes. Either the calendar screen leaves something
  behind that swallows the tap, or the panel's route is stuck. Until it is understood, the
  no-cascade rule is asserted through the store instead (and this is the one place the
  harness drives the app's own API rather than its UI in this group).
- **The calendar loses a day's appointment marker across month pages** (`calendar 08`, kept
  skipped as the regression): paging one month away and back leaves the count badge gone
  (`Expected: <3>, Actual: <null>`) while the appointments are still in the store and the
  screen is confirmed to be back on the current month. The data is intact, so this is a
  *drawing* bug — most likely the marker events are keyed per month page and not rebuilt on
  return. Worth fixing before the calendar is trusted to show "nothing booked" on a day.

- **The account switch is not a login gate.** `operate` (the account panel's *Operates on
  patients* switch) is read only by `login.currentLoginIsOperator`, which the appointment
  operator pickers use; `_LoginService.activate` never looks at it and the server rules do not
  either — so a switched-off account signs in normally, with access to whatever its
  permissions allow. §2.7's "a disabled account cannot log in" therefore cannot be written as
  a passing test: `accounts 06` asserts the flag where it *does* act (it decides whether the
  signed-in account is offered as an operator). If the switch is meant to be access control,
  the login path needs the check — and the panel's wording needs to say which of the two it is.

- **A text settings card never offers its Save button in the harness.** `settings_general 02`
  types a different currency code into the card's `CupertinoTextField` and no Save appears, so
  there is nothing to press and the change cannot be committed (`"The currency card never
  offered a Save button after \"EUR\" was typed into it"`). `enterText` does reach the field (the
  value read back afterwards is the typed one), the card is expanded, the button exists in other
  cards (`06` presses the AI card's combo) and the field's controller is non-null — so the
  condition is the *typed-vs-stored* comparison in `SettingsItem` (`_controller.text != value`),
  which is what `buildSaveCancelButtons` hangs on. Worth a widget test of `SettingsItem` alone:
  the screen is otherwise fine, and this is the only card edit the suite cannot make.

- **Opening the errors panel stops the test run dead.** `errors_and_recovery 01` never gets past its
  first line: the run's log freezes there (once for 13 minutes) while the app process stays alive,
  and nothing in the test can be the cause — every wait in it is bounded (60s) and `E2E.settle`
  pumps a fixed number of frames. The one thing it does that no other group does is open the
  errors flyout (`showErrorsFlyout`), so that is where to look. The test is kept as the
  regression; the shell half of the same story (the sync/reconnect button and its badge) is
  asserted in `errors_and_recovery 02`.

- **Some groups stop the test run dead on their first test.** Two of the newest groups —
  `errors_and_recovery 01` and `localization_rtl 01` — freeze the run on their own first line
  (13 and 8 minutes, app process alive, no further log output) and neither can be the cause by
  itself: every wait in them is bounded (60s) and `E2E.settle` pumps a fixed number of frames.
  **Diagnosed, 2026-09-24:** wrapping `E2E.boot`'s stages so each one names itself, prints its
  duration and fails on its own timeout (`E2E.stage`) put the freeze on `pump ApexoApp` — a
  1.8s stage that had already completed, sitting right after the local-data wipe.
  **Corrected, 2026-09-25: the retry cannot work, and it made the failure worse.** A hung
  `pumpWidget` never releases the test binding's async guard, so the retry's second
  `pumpWidget` throws **"Guarded function conflict"** — and from that moment *every* guarded
  call in *every* later test fails the same way: one wedged test in `notifications` turned a
  `+6 ~4 -1` run into `+0 ~4 -7`, with the app never having been the cause of the other six.
  `E2E.boot` no longer retries: the stage's 90s bound names the stage that hung and the run is
  over, honestly. What it does now is pump five **empty** frames (`settle`) *before* the first
  `pumpWidget`, so whatever the wipe and the device-database open left in flight has drained
  before the app's first frame — that is the one thing that distinguishes the frame that hangs.
  The *cause* of the hang itself is still unproven; the evidence so far is that nothing at all
  is logged while it hangs (no exception, no app output) and that the app process stays alive,
  which points at a frame that never completes (a channel that never answers, or a build loop)
  rather than at a slow stage.

### 6.3 Worth knowing before writing more

- **A store row can have two ids, and the blob's is the one a `Model` reports.** The store's map is
  keyed by the **document** id (the PocketBase `data` row), while each `Model` takes its `id` from
  the **value** (`record.data['data']`): `Model.fromJson` reads `json['id']` and invents a random one
  when it is absent, and `Model.toJson` always writes it. Every row the app writes therefore has the
  same id twice; a row written by *hand* with a value that has no `id` gets the same row under two
  ids — look it up by key and you find it, ask `docs.values` for it and you get a model whose `id`
  is invented. `Fixtures.patientIdOf` reads the model's id, which is how `sync_offline 01`/`03` failed
  (`the pulled row is not readable by name`) while `_waitForLocalRow` — a key lookup — passed:
  `RemoteRows.insert` was writing the unrealistic shape. Anything that hand-writes a row (a fixture,
  a second device) must put the id **in the value** as well, which `RemoteRows.insert` now does.
- **Wire values are the schema's, and the wrong field name is silent.** A patient's name is
  **`title`** (`Patients.title = schema.text('title')`); `name` is not a field, so a row written with
  it is created, synced and rendered with *no name* — see §6.1. The same applies to a hand-written
  `RemoteRows.insert(store: 'patients', data: {...})`: the keys of that blob *are* the store's field
  names.
- **`find.text(x)` matches the search box once `x` is in it.** "The search found the record" has to
  be asserted as a **row** (`find.ancestor(of: find.text(x), matching: find.byType(ListTile))`); two
  tests passed on nothing because of this, one of them for months (§6.1).
- **The login does not sync by itself.** `lib/app/routing/routes.dart` refreshes the stores on a
  *route change*: `AppRouter.navigate` / `goBack` fire `_syncStores(route)`, the one switch beside
  the router that replaced the old per-route `onSelect` closures (it awaits where they awaited and
  `unawaited(...)`s where they fired and forgot). That is what pulls a clinic after a fresh login —
  the dashboard is a route change; the shell's sync action and the reconnect are the other two
  entry points. A test that wants a pull logs in (and lands somewhere) or presses the sync action.
  A unit test that only wants the router state can use `navigateWithoutSync` (it is
  `@visibleForTesting` precisely because `navigate` fires those store syncs).
- **The run's first boot resets the server** (`E2E.resetState`), so anything a test needs the server
  to hold *before* its login has to be written after that boot — the first version of §1.6 `01` wrote
  its row before it, and the reset deleted the row it was about.
- **`RemoteRows` (`support/remote_rows.dart`) is "another device"**: it writes the `data` collection
  by hand (`store` + the row's fields), reads rows back, patches a field and deletes. A second
  `LocalPocket` would only test the engine against itself.
- **A DELETE that comes back as an error may still have deleted the row.** Handing back a thousand
  patients with 25 concurrent deletes, 173 requests were confirmed and 827 came back as errors — and a
  probe of the server afterwards found only **160** of the thousand left, so most of those "failures"
  had landed (client-side socket errors under the burst). Counting successful responses is therefore
  not counting deleted rows: `RemoteRows.deleteMany` runs at `concurrency: 8`, **asks** (`find`) about a
  failed id before believing it, retries the ones that really are still there, and returns a
  `DeleteReport` (`12 deleted, 3 left (429 too many requests x3)`) instead of an int. And a hand-back
  loop should take its next round's work from a fresh **read of the server** (`titledLike`), not from
  what the requests claimed. PocketBase has no bulk delete; one request per row is the only way. The
  passing run's log: `pass 1: patients 1000 deleted, 0 left (404 The requested resource wasn't found.
  x114), visits 200 deleted, 0 left — the server still has 0 patient(s), 200 visit(s)` → `pass 2:
  visits 200 deleted, 0 left` → `after the purge: 0 patient row(s) in the clinic, 0 on the server`. The
  `404 x114` is the *good* news of the map: those ids were never on the server (or another device had
  already handed them back), which is a success for a hand-back — and the 200 visits that "came back"
  are the `recreate` policy (§6.2), not a failed delete.
- **A `tearDown` runs with the widget tree already gone.** `testWidgets` takes its tree down before the
  tearDowns run, so any tap or finder in one is looking at an empty stage — and it *looks* like a broken
  app: `login 09`'s first hand-back called `Fixtures.signOut` (→ `openDashboard`) there and spent 60s
  waiting for a nav item, while `launch.open()` was still `Open.staff` and the counts were
  `NavigationView`=0, `WK.builder`=0, `WK.btnLogin`=0. State-only work is fine (a store call,
  `login.activate(url, [email, password], true)`) — that is how a test that drove the app offline leaves
  a normal session behind.
- **`WK.globalActions` is in the app bar of *every* route**, the login screen's included: it is the
  `NetworkActions` row (`app.dart`, `NavigationAppBar.actions`), not a "the shell is up" finder.
  `E2E.signIn` gets away with waiting for it because `waitForDatabase` behind it is the real gate; a test
  that drives the login itself watches `launch.open()` (`login`'s `_waitForStaff`).
- **A `Txt` hands its own key to the `Text` it builds**, so `find.byKey` matches **two** widgets for every
  keyed label (`findsWidgets`, or `.first` to tap one). Fluent does the same thing with a `Tab`: its key is
  on the header `HoverButton` as well, so a tab is switched **by icon** (`Fixtures.openPanelTab`,
  `login`'s `_openResetTab`) — `find.byKey(tabKey)` cannot be tapped at all.
- **A boot restores the stored session**, so "the login screen" is only reachable by signing out:
  `Fixtures.signOut` is safe to call from anywhere (a no-op when the form is already up) and
  `E2E.enterCredentials` on a signed-in app throws `Bad state: No element` instead of anything useful.
- **The reporter labels app log lines with the test whose zone registered the listener**: every `➡️:`
  line after the first boot reads `login 01: the login screen is shown` in the log. It is the zone, not a
  second copy of the test — don't chase it.
- **`Backend.dropCollections()` is the only way to reach the first-launch path.** `resetServer` deletes
  *and re-creates* the `data`/`public` collections, so `launch.isFirstLaunch` (set when the collection
  probe 404s) can never be set by a normal run; dropping them and letting the login recreate them is what
  `login 12` does.
- **The startup dialogs are recorded, not swallowed**: `E2E.firstBootDialogTitles` (the first boot of the
  run, the only one that can see the changelog — a wiped device has no "last seen version") and
  `E2E.lastBootDialogTitles` (the boot in hand). `login 13` asserts both: shown once, then not again.
- **PocketBase answers `204` to `request-password-reset` for an address with no account** (both
  `_superusers` and `users`), so a reset test can use a made-up address: nothing is mailed, no error, and
  the app's success path still runs. Measured by hand (`tmp/probe_reset.ps1`).
- **A boot restores the session by itself, so "the login screen" needs a sign-out.** `login` is a
  persisting singleton whose `fromJson` runs a whole `activate(url, [token], true)` when a token is
  stored, and `launch.open()` only becomes `Open.staff` at the *end* of it. A test that expects the
  login form — or types into it — is racing that restore: `perf_budgets 02` caught the form
  mid-flight and spent 60s waiting for a button the restore had already taken away, and the app
  logged a write into the disposed login screen's controller on the way (§6.1). `E2E.boot` has a
  `restore the app's stored state` stage now that waits on `login.ready` / `localSettings.ready`
  inside `tester.runAsync` (real I/O, outside the fake-async zone a test body lives in), and
  `signIn` only fills the form while it is really there. A test that *wants* the login screen signs
  out first (`Fixtures.signOut`, which `loginAs` uses too) — `localization_rtl 06` does that.
- **`ObservablePersistingObject.ready` *is* "my stored state is restored"**, and it completes after
  an async `fromJson` — for `login`, after a full login. Await it instead of guessing frame counts.
  Its notifications are also delivered through a stream, which is why an observer can be called
  *after* its screen was disposed: an observer callback has to be safe to call late.
- **A settings card can be built, collapsed and off-viewport all at once.** `revealSettingsCard`
  returned as soon as the card *existed* (the list keeps children inside its cache extent) and
  `expandSettingsCard` as soon as its `_combo` existed (fluent's `Expander` lays its content out
  while collapsed — the trap above). Both are "built"; neither is "visible" or "open", and the tap
  that follows derives an offset that lands on the card's header and only *warns*
  (`localization_rtl 04` then waited 60s for a dropdown option it was never offered). Both helpers
  now `ensureVisible` the card and judge "open" by **height**, the way `openServiceSection` does.
- **`find.byType(Scrollable).last` is a text field's scrollable** whenever the screen holds one:
  every `EditableText` carries an internal `editable` `Scrollable` (`axisDirection: right`) and it
  sorts *after* the list, so a `scrollUntilVisible(scrollable: find.byType(Scrollable).last)` drags
  a text field, never the list, and gives up with `Bad state: No element` — which is what
  `settings_general 03` died of after months of passing (the settings screen grew a field).
  Address the list's own:
  `find.descendant(of: find.byKey(WK.settingsList), matching: find.byType(Scrollable)).first`.
  **A `Scrollable` is not "the scroll view"**: say which one, by key.
- **Lists are paged to 10 rows** and sorted by title, so a record created by a test is often
  not on screen. `Fixtures.openPatient` searches for it when it is not visible.
- **The panel publishes its dirty state from a 750ms timer** (`PanelScreen`), so reading the
  save button straight after a keystroke is a race — wait with
  `Fixtures.waitForSaveState`.
- **`find.text(name).first/.last` throws on an empty match** (`Bad state: No element`) instead
  of waiting. Wait on the plain finder first, or use `E2E.tapFirst`.
- **A `.first`/`.last` finder must not be *nested inside another finder*, nor handed to an
  `expect`.** `FinderBase.found` asserts (`No results have been found yet …` / `Bad state: Too
  many elements`) while the *failure* is being described, so a plain mismatch surfaces as a
  finder error and hides what actually happened. The fix is a key, not a cleverer finder: the
  board's columns are `WK.columnRoot(id)` / `WK.columnHeader(id)`, its cards
  `Fixtures.noteCardById(noteId)`.
- **fluent's `Tooltip` is not material's** — `find.byTooltip` (which matches `material.Tooltip`)
  never matches one, so a `Tooltip(message: txt('addNote'), child: IconButton(…))` is
  unreachable by its message. That is why the board's add-note and delete buttons carry keys.
- **The notes board is a `Row` inside a horizontal `SingleChildScrollView`.** Past a few
  columns the rest are laid out *beyond the right edge of the window*, and a tap on one derives
  an offset that hit-tests nothing: `tester.tap` only warns (`warnIfMissed`) and the tap
  silently does nothing. `scrollUntilVisible` cannot help — a built widget is already visible
  to a finder. `Fixtures.revealInBoard` drives the `ScrollPosition` directly (a `tester.drag`
  would land on a card, not the scroll view).
- **An expanded note card replaces its title *label* with a field**, so after expanding, a
  finder that matched the title text sees nothing: look the card up by note id. Related
  shapes: an inline save button only exists once the text differs from the stored value; a
  column write lands *after* the dialog that started it has closed, so "it exists now" is a
  wait (`Fixtures.waitForColumn`), not an assertion.
- **`Fixtures.stamp` appends a counter.** Two calls in the same millisecond produced two
  identically named columns, and every finder on the board then matched twice.
- **The calendar opens on two weeks**, so a fixed day of the month can be outside the view;
  pick days relative to today. Today's cell carries `calendarSelected`, not its date key.
- **The agenda (and every list) is lazy**: an off-screen row is not in the widget tree at all,
  so a finder cannot see it and `ensureVisible` cannot rescue it. Scroll the list first —
  `Fixtures.openAppointmentTile` does this for the day's agenda.
- **`mounted` is not "still alive" during `dispose()`.** A fluent widget that fires a caller
  callback from its own `dispose()` (the `AutoSuggestBox`'s `_unselectAll` does) reaches the
  widget while `State.mounted == true` and the element is already `defunct`, so `setState`
  asserts. `if (!mounted || !context.mounted) return;` does **not** catch it either —
  `Element.mounted` is `_parent != null`, still true. The failure is reported against the
  *next* test ("failed after it had already completed"), never the one that caused it. The
  harness drops errors whose **stack** passes through `auto_suggest_box.dart`
  (`E2E.installKnownFlutterIssueFilters`, installed at boot, per test and on teardown — the
  binding swaps its own `FlutterError.onError` around every test, so one install point is not
  enough). One occurrence still escapes into the gap the binding owns: `labworks 01` is
  skipped for it, since the labworks screen's search box is an `AutoSuggestBox` and the
  callback fires while that screen is torn down.
- **A panel can swallow its own Save tap.** After a field backed by fluent's
  `AutoSuggestBox` (the lab-name box, the tag pickers) has been typed into, an open suggestion
  overlay — a root `OverlayEntry` drawn over the panel — can sit between the tap and the
  footer. `tester.tap` only warns (`warnIfMissed`), so the save silently never happens and the
  test fails later with "The panel never settled to nothing to save". `Fixtures._tapSave`
  now blurs first, scrolls the control into view and settles before tapping.
- **The right-hand pane header duplicates `WK.btnLogout`** — scope the finder to the screen
  you mean.
- **The first test in a run pays for the reset** (`E2E.resetState` on the first `boot`), which
  costs a few seconds before the app is usable.
- **The tests share one database.** Only the first `boot` of a run resets the server and the
  local file, so an earlier test's patients and appointments are still there. Assertions must
  be relative ("the count goes up by one") or scoped to the record under test
  (`openAppointmentTile(patient: name)` picks that patient's tile, not the day's first one).
- **A panel draws its tabs as icons only** — `Panel.showTitles` defaults to `false`, so
  the label passed to `PanelTab` is never rendered. Switch tabs with
  `Fixtures.openPanelTab(tester, title)`, which taps the tab's icon inside the `TabView`.
- **Only the selected tab is built.** The price and the post-op notes are on the
  *operative-details* tab, so a test that reads or writes them must switch to it first; a
  finder for a field on another tab matches nothing at all.
- **Finders do not see what a scroll view has scrolled out of sight.**
  `Fixtures.enterField` scrolls the panel's body (reached through a field that is on screen,
  so it cannot grab the screen behind the panel) until the field is reachable;
  `Fixtures.fieldText` reads with `skipOffstage: false`, and descends into wrappers, because
  the key often sits on a wrapper (`LiveTranscribingTextField`) rather than the field.
- **The suggestion dropdown is an `OverlayEntry`, not a `Flyout`.** The fluent overlay is
  inserted into the root overlay, so `find.descendant(of: find.byType(Flyout), ...)` never
  matches a suggestion; match the row's own text instead (excluded `EditableText`, which holds
  the same string).
- **A localized label matches twice.** `Txt` *is* a `Text` that builds another `Text`, so
  `find.text(txt('gallery'))` reports two widgets and a plain `tester.tap` refuses to pick
  one. Use `E2E.tapFirst`, or assert with `findsWidgets` when only presence matters.
- **Everything the dashboard shows is live in every test.** `E2E.signIn` lands on the
  dashboard, so a square that overflows fails *unrelated* tests — that is how the `ItemTitle`
  fit bug surfaced, from a single test that booked a visit for today.
- **The teeth chart is reachable without a key of the chart's own**: each tooth carries
  `WK.tooth(iso, selected:)`, whether it is the patient's chart or an appointment's. Tapping a
  tooth opens the state wheel (a flyout above 900px of width, a dialog below), and the
  condition is a `tx_options.dart` label.
- **The patient's summary bills completed visits only.** `PatientAppointmentBundle.done` is
  "marked done *and* not in the future", so pricing a visit booked for tomorrow changes
  nothing in the totals. `Fixtures.createAppointment(day: DateTime.now())` books a visit that
  has already happened (the day cell is drawn at 00:00).
- **`find.text(x)` also matches the search box once `x` is in it** (an `EditableText` holding
  the same string), and the command bar comes first in the tree — so "tap the first widget with
  this name" focused the field and never opened the record. `Fixtures.openPatient` now taps the
  name **inside its row**, and the row's own `ListTile` is left alone because a selectable row
  toggles selection when the row itself is pressed. This one only failed in a *full* run: with
  a short list the row is already visible and nothing is typed into the search box.
- **A layout overflow fails the test it happens in.** `IntegrationTestWidgetsFlutterBinding`
  reports layout errors at the end of a test (`Multiple exceptions … at least one was
  unexpected`), so a stray `RenderFlex overflowed` anywhere in the app is a red test. That is
  how the dropdown-row and chip overflows above were found — worth remembering when a test
  fails with no assertion of its own having fired.
- **A shut fluent `Expander` keeps its content laid out, and findable.** It only animates its
  height to zero (`SizeTransition`), so a field, a Save button and every key inside a closed
  section are in the tree and match a finder — they are simply not hit-testable, and
  `tester.tap` only *warns* (`would not hit test on the specified widget`), so the failure
  lands much later as a dialog that never came. **Never answer "is it open?" by looking for
  its content**: that is how the services group skipped every expansion and left six shut
  sections behind (`openServiceSection` saw a Save button and concluded it was open).
  `Fixtures` now judges a section by its **height** (a shut one is a header, `minHeight: 42`;
  an open one is header + content) and fails by name if the tap did not open it.
- **The same fact makes the settings list un-scrollable by arithmetic.** Its
  `maxScrollExtent` counts only the *collapsed* heights, so with six shut sections it read
  `58 of 58` (viewport 950) while a control inside one of them sat at y≈1267 of a 1000px
  window — and `getRect` on that control happily returns the y. Symptom to recognise:
  "could not scroll to a control; the list is at N of N" for a control whose rect is *below*
  the list's own content extent; the cure is to open the section first.
- **The nav pane no longer draws a route an account cannot open.** The 2026-09-28 routing
  refactor deleted that branch: `NavigationPane.items` is built from
  `routes.visibleRoutes` (the catalog filtered through `_accessible`), so a gated route is
  **omitted**, and `accounts 05` is right about it. The old text here — an inaccessible item
  built with `Icon(WindowsIcons.lock)` and `onTap: null`, which `Fixtures.openRoute` would
  tap to death — describes the pre-refactor shell and is kept only as the history of why
  `openRoute` verifies that it arrived. A permission test asserts the **absence** of the
  item (and that the screen was never built), not a lock.
- **Never clear stray processes while a suite is running.** Killing `apexo.exe` /
  `flutter_tester` before starting the next group murdered the group still running: its
  remaining tests and `tearDownAll` all reported `- did not complete`, which reads like a
  failure but is a killed run. Read the log's last summary line before starting the next one.
  Related: a run piped through `Select-String … | Select-Object -Last N` prints **nothing**
  until the pipe ends (`Select-Object -Last` buffers) — `Tee-Object -FilePath tmp/<name>.log`
  first and `Get-Content … -Tail 8` to watch it live.
- **A test that walks the router's history inherits the tests above it.** `routes` is
  app-global and every test in a group shares it: `lifecycle_platform 05` finishes on the
  accounts screen, so `08`'s `patients → calendar → back → back` landed on `accounts` where it
  expected `dashboard` (`Expected: 'dashboard' / Actual: 'accounts'`, twice). It calls
  `routes.reset()` first now — the app's own "dashboard, nothing behind it" state — rather
  than assuming nobody left a trail. The app was right both times; the test was the thing
  with the unstated precondition.
- **A `Timed out after 60s waiting for the X screen` after a nav tap is a missing key, not a
  broken route.** `Fixtures.openRoute` verifies it *arrived* before it retries, and the retry
  exists because a tap can genuinely miss — but if the key in the second `waitFor` is attached
  to nothing, the retry can only fail the same way. Diagnose it with the diagnostic test in
  `lifecycle_platform`'s history (values that settle it: `view.pane?.selected`,
  `routes.currentIndex`, `routes.currentRoute().id`, and `find.byKey(target)`), or with
  `tools/key_audit.ps1`, before touching `Fixtures`, the router, or `lib/app/app.dart`.
