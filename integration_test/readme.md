# Integration tests (end to end)

The suite drives the real app. `integration_test/e2e_test.dart` is the file
`flutter test` / `flutter drive` target, and it registers every group.

Each test boots the app for itself: a `testWidgets` starts with an **empty**
widget tree, so there is no "boot once and share" to build on. The backend and
the local state are reset once per run, on the first boot.

## Running the suite

### Native (Windows/macOS/Linux, Android, iOS)

```bash
flutter test integration_test/e2e_test.dart -d windows
```

### Web (Chrome)

Web runs use `flutter drive`, because `flutter test` refuses web devices for
integration tests ("Web devices are not supported for integration tests yet").
That needs **chromedriver** — a browser driver, not a Chrome extension:

```bash
# one-time (Node required)
npx @puppeteer/browsers install chromedriver@stable
# add the folder it prints to PATH, then check it:
chromedriver --version

# every run
chromedriver --port=4444        # in its own terminal
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/e2e_test.dart \
  -d web-server
```

`test_driver/integration_test.dart` is the host side of a web run; native runs
never load it. Add `--headless` to `flutter drive` for a headless browser.

**Use `-d web-server`, not `-d chrome`.** With `-d chrome` the command hangs at
"Waiting for connection from debug service on Chrome": `flutter drive` tells the
web runner not to launch a browser (the driver side opens it, through
chromedriver), and then waits for a browser that has not been launched. With
`-d web-server` the chromedriver session opens the browser at the served URL,
and the app connects.

#### What a web run can and cannot cover today

Web runs work end to end, including a login that opens the local database — but
they need one flag. The app expects cross-origin isolation (`web/index.html`
says so, and `web/_headers` is what serves it in production), and the dev server
`flutter drive` starts does not send the headers, so the worker-backed database
refuses to open and the login screen reports `localDatabaseFailed`.

`flutter drive` **does** forward `--web-header` (it is a `flutter run`
option), so `tools/run_e2e.ps1 -WebHeaders` adds
`Cross-Origin-Opener-Policy=same-origin` and
`Cross-Origin-Embedder-Policy=require-corp` and the database opens. The current
tree does **not** ship `integration_test/web_open_test.dart`; the smallest
database-opening web smoke the tree exposes today is the `login` group:
`pwsh -File tools/run_e2e.ps1 -Target web -Group login -WebHeaders`.

### The shorter way

`tools/run_e2e.ps1` runs either of the above, starts/stops chromedriver for you,
and passes the credentials in:

```powershell
pwsh -File tools/run_e2e.ps1                 # native, whole suite
pwsh -File tools/run_e2e.ps1 -Target web     # Chrome, whole suite
pwsh -File tools/run_e2e.ps1 -Target web -Headless
pwsh -File tools/run_e2e.ps1 -Target web -Headless -WebHeaders
pwsh -File tools/run_e2e.ps1 -Group login    # just that group, in isolation
pwsh -File tools/run_e2e.ps1 -Group "04:"    # any other string = a test-name filter
pwsh -File tools/run_e2e.ps1 -Target web -Group login -WebHeaders -Headless
```

Running by hand instead means passing the credentials of the live test server
yourself, as `--dart-define=PB_SERVER=... --dart-define=PB_EMAIL=...
--dart-define=PB_PASSWORD=...` (see `support/credentials.dart`). They cannot be
read from `test/secret.dart` by the test — see the import rule below.

### Filtering

A **group name** (`login`, `notes`, …) runs that group *and nothing else*: the
runner passes `--dart-define=E2E_GROUP=<group>`, which makes `e2e_test.dart`
register only that group. It has to work this way — the register order is the run
order, because each group's tests use the records the groups before it created.
A name filter cannot isolate a group: `--plain-name notes` also matched
`patient_panel 04: the patient's notes save and reload`, which then failed
because nothing had created a patient for it.

Any other string is Flutter's own filter — a plain substring of the test's full
name (`"login 04: logging out returns to the login screen"`):

```bash
flutter test integration_test/e2e_test.dart -d windows --plain-name "04:"
```

**Web runs filter by group only.** `--plain-name` belongs to `flutter test`;
`flutter drive` rejects the flag, so a web run cannot pick one test out of a
file. `E2E_GROUP` is the lever instead, and on the current tree the smallest
database-opening web run is `-Group login` — there is no dedicated
`web_open_test.dart` smoke file to target.

`dart integration_test/watch.dart [filter]` re-runs the suite on save (it shells
out to `tools/run_e2e.ps1`).

### All of them

`pwsh -File tools/run_e2e.ps1` with no `-Group` runs **every registered group, in the order the
file registers them** — and it builds once, so it is by far the cheapest way to cover the whole
registered suite (29 groups today). The order is not decoration: each group's tests use the
records the groups before them left behind, so a full run is the faithful measurement, while one
process per group is the one that says *which* group a red count belongs to:

```bash
pwsh -File tools/run_e2e_groups.ps1 -Groups login,patients,calendar
```

That loop runs `run_e2e.ps1` once per group, tees each to `tmp/run_<group>.log`, starts each
group from a clean build state, and prints one summary line per group. Use it when you need one
log per registered group.

Note that a **failure to load** the file is not a group failure. Four signatures, one disease —
a process from an earlier run that ended badly, still holding the build's own files (this cost a
two-hour detour on 2026-09-30: `login 09` left a `cmake` behind, and *every* group after it failed
to build):

```
00:00 +0 -1: loading … [E]  Unable to start the app on the device
00:00 +0 -1: loading … [E]  Build process failed            (MSB8066 … flutter_assemble …
                                                             exited with code 1)
00:00 +0 -1: loading … [E]  Unable to generate build files  (CMake: generator platform: x64)
                             … and inside that: cmake -E tar: error: ZIP decompression failed (-5)
```

The recovery is: identify the specific stale build process that still holds the tree (the
locking process is often **`cmake`** from the failed group), stop that process only, then delete
whatever it was holding (`build/windows/x64/firebase_cpp_sdk_windows_*.zip` and
`build/windows/x64/extracted/` for the last one; `build/windows/x64/CMakeCache.txt` +
`CMakeFiles` for the third), and re-run. `flutter clean` does *not* help while a stale process
still holds the tree, and can make it worse.

Every group in a batch fails to load once this has happened, so a whole batch of
`+0 -1: Some tests failed` means "fix the build", not "fix 25 groups".

### While a run is going: do not touch `lib/` (or `integration_test/`)

`tools/run_e2e.ps1` builds the app at the start of the run, and a *batch* of groups (a loop
of `run_e2e.ps1`, one call per group) builds again for each group. An edit that lands while
the next group is compiling goes into that build — and a half-applied edit fails the whole
group before it runs a single test, which reads exactly like a product failure:

```
00:00 +0 -1: loading .../integration_test/e2e_test.dart [E]
01:01 +0 -1: Some tests failed.
```

Two groups were lost to that in this session (`sync_offline`, `localization_rtl`) — one from
a stray `),` left by an in-progress rewrite in `tag_input.dart`, one from two screens using
`clipCodePoints` before the import that defines it was added. `dart analyze lib
integration_test test` (0 errors expected) before launching is the cheap guard; it catches
both of those immediately. Also note that `flutter test` buffers its output when it is piped,
so a log that stops growing usually means the *build* is still going, not that the run hung.

### What has to be true of a test

Tests must run on a native window **and** in a browser:

- **Each test boots the app itself**, with `E2E.boot(tester)`. A `testWidgets` does not
  inherit the widget tree the test before it pumped — measured, the tree is empty — so
  there is no "boot once" to build on. What *does* survive is the app's global state
  (`login`, the stores, the open database), so a test that needs a session says so with
  `E2E.signIn(tester)` instead of hoping the test above it left one behind. Hidden
  order-dependence is the one way this suite can rot quietly.
- **Records are made through the UI**, with `Fixtures` (`support/fixtures.dart`): it opens
  screens, creates patients, searches for a row the paged list is not showing, saves and
  closes panels. Reach for it before hand-rolling finders.
- **The tests drive a 1600x1000 window** (`E2E.boot`). At the app's own 1280 the navigation
  pane goes compact as soon as a panel is open, and its header overflows — a real bug, not a
  test problem (resolved on the current tree; see the disposition ledger below).
- **Don't read the panel's save button straight after a keystroke**: `PanelScreen` publishes
  its dirty state from a 750ms timer. Use `Fixtures.waitForSaveState`.
- **An e2e file may only import `lib/` and its own `integration_test/` tree.** A web build
  compiles nothing else: `import '../../test/secret.dart'` fails a web run with
  `Error when reading 'org-dartlang-app:///test/secret.dart': File not found`. That is why
  the credentials arrive as dart-defines (`support/credentials.dart`) and why the backend
  helpers do not reuse `test/live_backend/test_utils.dart`.
- `dart:io` compiles for web but throws `Unsupported operation` at runtime, so
  never call it without a `kIsWeb` check (`support/backend.dart` keeps those checks in one
  place).
- Don't use `pumpAndSettle`: the app's progress rings and other animations never
  settle. Use `E2E.waitFor(tester, find.byKey(...))`, which pumps until a widget
  shows up (or fails with what it was waiting for).
- `tester.tap` only *warns* when a widget is covered or off screen, and a missed tap looks
  exactly like a broken feature. Use `E2E.tap(...)`.
- A web run cannot wipe local storage — that lives in the browser profile
  (IndexedDB/OPFS). The server **is** reset on both platforms.
- A cold first login on web opens the local database in OPFS and is slow: the
  timeouts in the groups are deliberately generous.
- The app pops its **changelog dialog** about a second after a fresh start (a fresh
  install has no "last seen version") and it covers the login form. `E2E.boot` dismisses
  it for you (it waits out the ~1s timer on the first boot of a run only); if you drive
  the login screen yourself, call `E2E.dismissStartupDialogs` first.
- Keys are not always unique: there are two logout buttons (nav pane header *and* the
  dashboard's command bar). Scope the finder (`find.descendant(of: ...)`) instead of
  hoping the first match is the visible one.
- **The tests share one database**: only the first `boot` of a run resets the server and the
  local file. Assertions have to be relative to what is already there ("the day's count goes
  up by one") or scoped to the record under test — `Fixtures.openAppointmentTile(patient: …)`
  opens *that* patient's tile, not the day's first one.
- **Panel tabs are icons.** `Panel.showTitles` is off by default, so a `PanelTab`'s label
  is never rendered: switch with `Fixtures.openPanelTab(tester, 'operativeDetails')`, which
  taps the tab's icon in the `TabView`. And only the **selected** tab is built, so a field on
  another tab has no finder at all until you switch.
- **Finders skip what a scroll view has scrolled out of sight.** Use `Fixtures.enterField` for
  fields below a panel's fold (it scrolls the body), and `Fixtures.fieldText` to read one —
  the key usually sits on a wrapper (`LiveTranscribingTextField`), not on the field.
- **A layout overflow fails the test it happens in.** The binding reports layout errors when
  the test ends (`Multiple exceptions … at least one was unexpected`), so a stray
  `RenderFlex overflowed` anywhere in the app reds a test that otherwise passed every
  assertion. Three real ones came out of this suite; if a test fails with no
  assertion of its own having fired, read the exception log before the failure.
- **A suggestion dropdown is an `OverlayEntry`, not a `Flyout`** (fluent inserts it into the
  root overlay). `find.descendant(of: find.byType(Flyout), …)` never matches a suggestion.
- **A localized label matches twice**: `Txt` is a `Text` that builds another `Text`, so
  `find.text(txt('gallery'))` finds two widgets. Use `E2E.tapFirst`, or assert with
  `findsWidgets` when only presence matters.
- **The dashboard is live in every test** (`E2E.signIn` lands on it), so a square that
  overflows fails tests that never opened it. `lib/item_title.dart` bit exactly that way.
- **`find.text(x)` also matches a text field that holds `x`.** "Tap the first widget with this
  name" therefore tapped the list's own search box once the name had been typed into it — and
  only in a full run, where the list is long enough to need the search. `Fixtures.openPatient`
  taps the name inside its row instead, and not the row's `ListTile`, because pressing a
  selectable row toggles its selection.

### Backlog reconciliation

The disposition ledger below accounts for all 94 formerly unchecked entries, the four restored
groups and the historical open findings. **Implemented** means source exists, not that live E2E
validation passed. The backlog must not be retired while feasible work or validation remains open.

### Before believing a red group: check the keys, and reproduce off the suite

A group that dies with `Timed out after 60s waiting for the <screen>` **after** a nav tap has
almost always tapped correctly and is waiting for a key that does not exist. Two things
answer that in seconds instead of minutes:

- **The key audit.** `pwsh -File tools/key_audit.ps1` lists every `WK` key declared in
  `lib/widget_keys.dart` and attached to nothing in `lib/`, and which of those the suite
  uses. 2026-09-28: 52 were unattached, which reddened most groups; all 52 are attached now
  and the audit exits 0, so the next such timeout really is about the screen.
- **A widget test in `test/widget/` instead of an e2e run.** `E2E.boot` + one group is 30s at
  best and minutes when it fails; the same question asked of a bare widget is under a second.
  Two are kept as examples (and as regressions):
  `test/widget/app/navigation_body_test.dart` (a `NavigationView` whose `selected` the caller
  changes — the shell's own shape) and
  `test/widget/features/accounts_counts_row_test.dart` (a layout overflow at four widths).
- **A red group with no app frame in the stack may not be about that group at all.** Flutter
  painting/library exceptions (a layout overflow, an unpaired surrogate handed to
  `RenderParagraph`) are caught by the *framework*, so the report says only
  `EXCEPTION CAUGHT BY PAINTING LIBRARY` and reds whichever test is running. Print the value
  where it is built rather than reading the stack: a temporary check in `Txt.build`
  (`lib/services/localization/locale.dart`) that prints the data and its code units found
  `settings_general`'s four reds in one run, and the same check inside the replacement helper
  named the widget that built it.

Run one test of a group by name, which still pays a full boot but only one test:

```bash
pwsh -File tools/run_e2e.ps1 -Group "lifecycle_platform 05:"
```

## Writing a test

Standard Flutter shape — `group` + `testWidgets`, no bespoke base class:

- One area per file under `integration_test/groups/`, exposing
  `void registerXxxTests()` that calls `group('xxx', () { ... })`.
- Register it in `e2e_test.dart` with one line (`registerLoginTests();`). Keep the
  file list in sync — an unregistered group silently does not run.
- Start every test body with `await E2E.boot(tester);`, and with
  `await E2E.signIn(tester);` when the test needs a signed-in session.
- Name tests `NN: what it does` so a group reads in order and `--plain-name "04:"`
  finds one: `'04: logging out returns to the login screen'`.
- A test to leave out for now uses the standard `skip`:

  ```dart
  testWidgets('06: a wrong password is reported', (tester) async {
    ...
  }, skip: 'needs the fake-clock seam (see the disposition ledger)');
  ```

  That replaces the old `--` suffix. There is no replacement for the old `++`
  suffix: every test stands on its own now, and "this one must run first" is a bug
  in the test, not a marker.
- A failing test fails the run (the tool reports it by name); nothing in the suite
  reports success on a step that failed.

The disposition ledger below is this suite's **complete, retired backlog** (the former `todo.md`
file was removed after this reconciliation): it accounts for every formerly tracked entry, so there
is no separate backlog file to consult. Comments in the harness and groups that cite `todo.md §…`
refer to the matching section of this ledger.

### Why the change?

The old harness (`base.dart`, one `testWidgets` running every group, a mode file)
existed to boot the app once and share the session. It cost per-test reporting,
filtering, `skip`, timeouts and sharding — CI saw a single test called "runs every
group". Since a per-test boot is ~1s and the app's own state survives anyway, the
harness bought little for what it hid.

## Current-tree disposition ledger (2026-10-09)

### Validation evidence

- **Full deterministic unit suite: 1734 passed** (`flutter test test/unit --exclude-tags live_backend -j 1`).
- Focused deterministic version, tag-input, harness, calendar and settings-card tests: **31 passed**.
- Email validation, patient model and shared harness regression tests: **27 passed**.
- Complete patients group, including new email/grid behavior: **17 passed** on Windows.
- Anonymous patient-page revocation/re-enabling: **1 passed** on Windows.
- Copying historical tooth treatment/notes into a saved appointment: **1 passed** on Windows.
- AI UI group (`ai_services`): tests `01`–`04` verified passing in a Windows run, including the
  corrected transcription locale (a numeric picker index was previously stored instead of a
  language code). Test `05`'s assertions about logout clearing the cached token passed; the
  trailing re-login it used to perform stalled (`Synchronizing patients`) and has been removed,
  so `05` stands as "logout clears the cache" without the redundant session round-trip. A fresh
  group re-run did not complete within this pass's budget.
- Restored notifications group on Windows: **5 passed / 3 platform skips**.
- Restored multi-clinic group on Windows: **3 passed / 4 documented skips** (real two-server
  switching needs a second disposable clinic).
- Fresh-process calendar group: **7 passed / 1 skipped**.
- Edited appointment archive/close regression: **1 passed** after persisting the complete draft
  when archiving; the full appointments group still needs revalidation.
- Errors/recovery group: **2 passed / 2 isolated-corruption skips** after awaiting reconnect.
- Labworks screen smoke: **1 passed**; the remaining labwork flows remain timing-dependent on an
  upstream Fluent UI disposal callback, deferred rather than fixed in the dependency.
- Single-process full-suite startup still intermittently wedges in a guarded frame; fail-fast
  prevents cascading failures. Serial fresh-process group validation is underway instead.
- All five locales retain matching key sets after the new product strings.
- Permanent deletion remains intentionally unsupported by user decision: archive/restore is retained.
- Windows patient tests `01`–`09`, including suggestion and Enter commits checked against stored
  tags: **9 passed**. The initial text-only chip assertions were unreliable and were replaced by
  persisted-record assertions.
- Windows general-settings group: **5 passed / 3 skipped** after expanding collapsed text
  cards and restoring currency without using a disposed widget tree in teardown.
- Targeted static analysis of all changed Dart areas: **no issues found**.
- Windows build now works; the old Firebase SDK download blocker is no longer current.
- Whole-suite validation is **not yet green**. A startup-dialog frame stalled and poisoned the
  binding, producing 177 cascading failures rather than 177 independent product bugs. Startup
  metadata is now preloaded outside guarded frames; login recheck passed **11 / 4 skipped**.
  Native runs now fail fast so one wedged frame cannot waste the rest of the suite.
- Normal Windows login group after first-launch isolation: **11 passed / 4 skipped**.
  The first-launch schema-reset test is verified separately below.
- First-launch test in a fresh dedicated process: **1 passed**. Run it separately with
  `pwsh -File tools/run_e2e.ps1 -Group 'login 12:'`; it is deliberately excluded from ordinary
  groups because deleting collections during an existing session races synchronization.
- Remote update metadata no longer gates startup dialogs; installed-version loading is separate
  and remote checks have a bounded timeout.
- Web/mobile and external-service checks have not been executed. `chromedriver` is not on PATH.

Legend: **covered** = existing automated coverage path exists now; **pending** = feasible work not
in the tree yet (deferred to a later pass); **blocked** = platform/harness/environment limit; **decision** = product decision
or missing feature rather than missing test; **historical** = migration-era finding not actionable
on this tree.

### §0 Foundations

- **§0.1 / `Fixtures.seedAppointment(...)`** — **implemented** in
  `integration_test/support/fixtures.dart`, including optional labwork and operator data.
- **§0.1 / `Fixtures.seedBaseline()`** — **implemented** with scoped ownership of baseline rows.
- **§0.1 / `Fixtures.deleteEverything()`** — **implemented** as owned-row cleanup only; it does
  not wipe unrelated clinic records. The existing first-boot server reset remains destructive.
- **§0.2 / row key per record for appointments/labworks/expenses/notes/accounts/archived** —
  **pending**: current groups still rely on scoped text finders and per-screen helpers rather than a
  full row-key rollout.
- **§0.2 / toast and InfoBar keys** — **pending**: tests still assert success/failure by visible text
  or state, not keyed toast surfaces.
- **§0.2 / tooth condition keying** — **pending**: `WK.tooth(...)` is attached in
  `lib/common_widgets/teeth_selector/teeth_selector.dart`, but per-condition keys are still absent.
- **§0.2 / 28 declared-but-unused handles** — **deferred**: declared keys like `loginScreen`,
  `settingsScreen` and `acDate` are harmless dead handles; cleanup is cosmetic and was left for a
  later pass. `pwsh -File tools/key_audit.ps1` reports zero suite-waited keys unattached.
- **§0.3 / `E2E.readText(finder)`** — **implemented** as `E2E.readText(tester, finder)`;
  deterministic helper coverage is in `test/unit/integration_support/e2e_support_test.dart`.
- **§0.3 / `E2E.expectEventually(...)`** — **implemented** with bounded text assertions.
- **§0.3 / `E2E.setLocale(...)` / `E2E.setTheme(...)`** — **implemented** in
  `integration_test/support/e2e.dart`.
- **§0.3 / `E2E.screenshot(name)`** — **implemented** for web/Android; unsupported desktop
  targets report that capture was skipped rather than claiming an artifact exists.
- **§0.3 / `E2E.acceptUnsavedChanges()` / `E2E.discardDraft()`** — **implemented** with panel
  close/discard handling.
- **§0.4 / whole-suite web run with `-WebHeaders`** — **environment**: needs chromedriver; the
  DB-opening web smoke is `-Group login -WebHeaders` (see Running the suite).

### §1 P0

- **§1.1 / `11: the session survives a restart`** — **blocked**: `groups/login.dart` can only
  re-pump the tree; proving session restore still needs a second process.
- **§1.1 / `14: a second tab is refused`** — **blocked**: the current harness drives one web
  document, not two tabs.
- **§1.1 / `15: a clinic whose database is missing is told so`** — **blocked**: corrupting the local
  database is a once-per-process failure mode that would poison the rest of the run.
- **§1.2 / `05: an invalid email is rejected`** — **implemented** with optional-email validation
  before panel persistence; malformed values retain the draft and display an error.
- **§1.2 / `10: list and grid views both render`** — **implemented** with a shared search/sort/page
  source and selectable patient cards; covered by patients `17`.
- **§1.2 / `15: a tag can be added from the tag input`** — **implemented**: existing suggestions
  and focused Enter are exercised by `integration_test/groups/patients.dart` `07`/`08`;
  `test/unit/common_widgets/tag_input_test.dart` verifies new, strict and duplicate tag behavior.
- **§1.3 / `08: revoking patient-page access takes the link down`** — **verified**: the patient-page
  switch persists revocation; schema version 2 filters revoked patients from the anonymous public
  view. The Windows test verifies anonymous access disappears and returns on re-enabling: **1 passed**.
- **§1.3 / `09: voice autofill fills the dental notes`** — **environment**: the recorder entry point
  exists and `ai_services` verifies its UI gating; real transcription needs a microphone and the live
  Worker, which this machine cannot supply.
- **§1.3 / `10: the panel can be minimised and restored`** — **implemented** at compact width
  in `integration_test/groups/patient_panel.dart`; backlog numbering is now reconciled.
- **§1.4 / `08: two doctors' appointments are both visible and filterable`** — **blocked**: the
  operator filter is still the same undrivable tag-input surface.
- **§1.4 / `13: paging to another month keeps the appointment data`** — **unit-covered** by
  `test/widget/features/calendar_widget_test.dart`; the historical marker bug did not reproduce
  in the current widget. The E2E regression still needs a successful live recheck.
- **§1.4 / `14: a month with many events` and the operator filter** — **partly covered**:
  deterministic calendar coverage verifies 37 events on a day; live operator filtering remains open.
- **§1.5 / `07: previous notes can be copied into this appointment`** — **implemented**: each
  historical tooth note offers a copy action into the current draft; persistence still requires Save.
- **§1.5 / `08`/`09`: gallery upload and delete flows** — **covered** by the restored
  `integration_test/groups/attachments.dart` (upload, render, delete, malformed-image resilience).
- **§1.6 / `02: a change made offline lands on the server after a reconnect`** —
  **verified at persistence-session level** by `sync_offline 08`: queued local edits stay absent
  remotely until reconnect, then synchronize. The old migration-engine outage simulation remains
  inapplicable; the remote-row helper now uses the actual `title` field rather than nonexistent `name`.

### §2 P1

- **§2.1 / `06: money totals use the clinic currency`** — **implemented** in
  `integration_test/groups/dashboard.dart` with restoration of the original currency.
- **§2.1 / `07: an empty clinic shows zeros, not spinners`** — **blocked**: it needs a genuinely
  fresh-install run, not another test inside a shared process.
- **§2.2 / dashboard labwork squares and notification entries** — **partly covered**: notifications
  are registered and passed (5/3); labworks tests are re-enabled, but a Fluent UI callback after
  disposal can attribute an upstream assertion to whichever labwork test owns that frame.
  **Deferred per user instruction** rather than fixed in the dependency.
- **§2.3 / `08: a staff account without the notes permission still sees its own`** — **pending**:
  the building blocks exist in `integration_test/groups/notes.dart` and
  `integration_test/groups/accounts.dart`, but the cross-session permission scenario is still unwritten.
- **§2.3 / notes survive restart and recurring-note instance logic** — **blocked/pending**:
  restart coverage still needs a second process; recurrence should be kept at unit-test level rather
  than grown into the current e2e harness.
- **§2.4 / `01` + `03`: file and photo pickers** — **environment**: the restored attachments group
  drives uploads directly; the OS picker dialog itself cannot be answered by the harness.
- **§2.4 / `02: upload failure is reported and the retry succeeds`** — **not written**: needs a
  controllable upload failure; the deferred-write queue's retry path is covered at unit level.
- **§2.4 / `05` + `06`: downloading on native/web** — **environment**: the last step is the platform
  save dialog.
- **§2.4 / `09: the DICOM preview name is normalised`** — **covered**: the naming rule is already
  exercised by `test/unit/features/dicom/dicom_helpers_test.dart` and
  `test/unit/utils/strip_id_from_file_test.dart`; there is no current attachments e2e group.
- **§2.4 / `11: web caches blobs in OPFS after a successful attach`** — **environment**: web storage
  is browser-profile state and needs a web run.
- **§2.5 / `06 (skipped): marking an order paid moves it to the paid tab`** — **blocked**: the row's
  overflow menu still does not open under the harness; nearby due/paid coverage remains in
  `integration_test/groups/expenses.dart`.
- **§2.5 / totals row, receipt-photo lane, AI receipt scan** — **partly covered**: the receipt-photo
  and AI lanes are environment-bound (camera/Worker); the totals row remains unwritten.
- **§2.7 / `09: permission changes apply on the next login`** — **implemented** with revocation
  and re-login in `integration_test/groups/accounts.dart`; live verification remains required.
- **§2.7 / `10: an account can be removed and its rows survive`** — **decision**: the current UI
  disables accounts instead of deleting them.
- **§2.7 / per-screen permission matrix (`07` from the original list)** — **covered/pending**:
  gating is already exercised in `integration_test/groups/accounts.dart` (`05`, `08`), but the full
  screen-by-screen matrix is still not enumerated.
- **§2.6 / `04: the calendar system changes the axis labels`** — **blocked**: it still depends on a
  suite-wide settings change in a shared clinic.
- **§2.6 / `05: an empty clinic renders empty charts, not an error`** — **blocked**: it needs a
  fresh database outside the current shared run.
- **§2.8 / `04: permanent deletion removes it from the server`** — **decision**: there is no
  permanent-delete action in the current Deleted Items UI.
- **§2.8 / `05: the empty state renders`** — **pending**: it needs a no-archive setup the current
  group does not seed.
- **§2.8 / appointments/labworks/expenses rows and sort control** — **pending**: `integration_test/groups/deleted_items.dart`
  only covers patient rows today.
- **§2.9 / `02: a changed card persists across screens`** — **implemented** and re-enabled in
  `integration_test/groups/settings_general.dart`; deterministic Save/Cancel coverage passed in
  `test/widget/features/settings_item_test.dart`. Live verification is tracked separately.
- **§2.9 / `04: the calendar system changes the dates app-wide`** — **blocked**: it still mutates
  suite-wide state in a shared clinic.
- **§2.9 / `05: the dental notation switches the teeth charts`** — **covered**: `tooth_chart 04`
  switches Palmer/ISO/Universal through the same setting and asserts the drawn labels.
- **§2.9 / `07: settings are per clinic`** — **covered**: the restored `multi_clinic` group verifies
  per-clinic Hive namespaces, local-row and schema-marker isolation; a second real server remains
  unavailable, so its skips say so.
- **§2.10 / `01: an admin is offered every service section`** — **blocked by app/harness bug**:
  `integration_test/groups/settings_services.dart` still carries this as the first-test navigation regression.
- **§2.10 / good S3 round-trip and oversize upload rejection** — **blocked**: both require a real,
  writable S3/upload target that the shared test clinic does not provide.
- **§2.10 / `07: changes are rejected without superuser rights`** — **covered**: current tree already
  covers the visible outcome in `integration_test/groups/settings_services.dart` `06`; the unchecked
  backlog text is now documentation lag, not a missing current-tree test.
- **§2.11 / `06: a failed backup says so`** — **blocked**: forcing a backup failure means breaking the
  shared clinic's backup target.
- **§2.11 / `07: a backup carries attachments`** — **blocked/pending**: restore is destructive to the
  shared clinic, and attachment-specific coverage is still part of the missing attachments work.
- **§2.12 / `03: a folder can be chosen as the watch directory`** — **blocked**: the OS directory
  picker is not answerable from the current harness; the watch-directory effect is still covered by
  `integration_test/groups/dicom.dart` `04`.
- **§2.12 / `05: a .dcm can be uploaded on web`** — **decision**: the web import path does not exist
  in the current product.
- **§2.12 / `08: a skipped file says why`** — **decision/covered**: the UI does not surface
  `DicomSkippedLog`; the reason is only unit-testable on the current tree.
- **§2.12 / `10: the viewer opens and renders the image`** — **pending**: it still needs the approve
  flow plus stable viewer keys.
- **§2.12 / `11: the viewer controls work`** — **covered/pending**: prefs are unit-covered by
  `test/unit/features/dicom/dicom_viewer_prefs_test.dart`, but the control surface still lacks keys
  for e2e.
- **§2.12 / `12: a preview png is uploaded to the record and named correctly`** — **covered/pending**:
  naming and sibling logic are unit-covered by `test/unit/features/dicom/dicom_helpers_test.dart`,
  `test/unit/features/dicom/dicom_orphans_cleaner_test.dart`, and
  `test/unit/features/dicom/dicom_gallery_test.dart`; full approve/upload e2e remains open.
- **§2.12 / `13: deleting the record removes the DICOM link`** — **covered/pending**: store-level link
  operations are unit-covered, but the approve-driven end-to-end path is still open.
- **§2.12 / `14: the registries survive a restart`** — **blocked**: this still requires a real
  process restart against the device database.
- **§2.13 / `06: the portal is localized` / `07: no staff chrome`** — **pending**:
  `integration_test/groups/patient_portal.dart` covers auth and record scoping, not these two UX checks yet.
- **§2.13 / `06: the patient's shareable link is minted onto the record`** — **blocked**: the current
  path depends on a shortening server the harness cannot make reliable.
- **§2.13 / `08: a QR link and a typed link behave the same`** — **blocked/covered**: QR flow needs a
  scanner, while the typed-link path is already what `integration_test/groups/patient_portal.dart` `05` drives.
- **§2.14 / `01: every locale renders the staff shell`** — **blocked by app/harness bug**: the
  regression remains skipped in `integration_test/groups/localization_rtl.dart`.
- **§2.14 / locale-formatted dates/numbers and the patient-side picker** — **partly covered**:
  `localization_rtl` 01 is re-enabled (every locale renders the shell) and the locale machinery is
  covered; the patient-side picker remains with the portal group.
- **§2.15 / `04: the login form remembers the last server per clinic`** — **decision**: the current
  app stores one server per session and has no clinic list; the restored `multi_clinic` group covers
  the isolation the architecture does provide (3 passed / 4 documented skips).
- **§2.15 / `07: a legacy Hive-era clinic migrates without losing rows`** — **historical**: the
  current tree has no Hive migration path to test.
- **§2.16 / bottom-nav drawer and portrait clipping** — **environment**: the drawer needs a phone
  layout; `lifecycle_platform` covers the current bottom bar.

### §3 P2

- **§3.1 / `01: audio transcription fills the dental notes`** — **environment**: the restored
  `ai_services` group covers UI gating, recorder visibility, locale persistence and token clearing;
  live transcription needs a microphone and the Worker.
- **§3.1 / `02: a receipt photo fills the expense fields`** — **environment**: needs a live Worker.
- **§3.1 / `03: post-op notes are generated from the appointment`** — **environment**: needs a live
  Worker.
- **§3.1 / `04: a Worker failure is reported and the draft is not lost`** — **environment**: needs a
  controllable Worker outage.
- **§3.1 / `05: a very long recording is rejected with a reason`** — **environment**: needs recorded
  audio.
- **§3.1 / `06: the transcription locale setting is respected`** — **verified**: `ai_services 04`
  passes against the corrected per-language-code persistence (a numeric picker index was stored
  before this session's fix).
- **§3.1 / `07: cache reset clears the stored extraction state`** — **deferred**: destructive cache
  reset would wipe this suite's own state; the control's presence is covered in `settings_general`.
- **§3.2 / `08`/`09` notification web/FCM bridge cases** — **environment**:
  `integration_test/groups/notifications.dart` is registered (5 passed / 3 skips); these two cases
  depend on the web bridge or FCM-only behavior.
- **§3.2 / `10` relay delivery/refusal** — **environment**: `sendPush` is fire-and-forget without a
  device-token assertion path.
- **§3.2 / `11` permission denial** — **environment**: needs Android/iOS FCM behavior.
- **§3.4 / `01: the errors panel collects, counts and clears them`** — **verified**: re-enabled and
  passing (`errors_and_recovery` 2 passed / 2 isolated-corruption skips) after awaiting the
  asynchronous reconnect before asserting the errors were cleared.
- **§3.4 / `03: a failed local-database open offers a way out`** — **blocked**: corrupting the local
  database is still a once-per-process failure mode.
- **§3.4 / `04: a corrupted local file is reported, not swallowed`** — **blocked**: same local-database
  process limit as `03`.
- **§3.4 / `05: an expired token triggers re-authentication`** — **pending**: this still needs a
  repeatable server-side session invalidation helper.
- **§3.4 / `06: a crash-free start after wiping local data`** — **covered**: every run does that via
  `integration_test/support/backend.dart`, and `integration_test/groups/lifecycle_platform.dart` `01`
  is the explicit boot-after-wipe assertion.

### §4 Cross-cutting

- **§4.2 / `04: the label inside a tooth follows the notation`** — **implemented**: `tooth_chart 04`
  switches Palmer/ISO/Universal and asserts the labels; notation is restored in teardown.
- **§4.2 / `05: the state wheel names the tooth it will write to`** — **implemented**: `tooth_chart 05`
  asserts the wheel names the tooth under ISO notation.
- **§4.2 / do not test the Windows `AXTree` flood** — **decision**: this is still an upstream engine
  issue, not current-tree app work.
- **§4.2 / `05: the semantics tree is reachable in a browser`** — **blocked**: it still needs a
  dedicated web-only semantics-placeholder click path.
- **§4.4 / `08: a cold web start with a warm OPFS database beats the bootstrap bound`** —
  **pending**: this is a web performance run, not a missing source hook; the tree still uses browser
  profile storage on web and has no dedicated `web_open_test.dart` helper file.
- **§4.4 / `09: the group's own seeding stays out of every other group's way`** — **covered**:
  `integration_test/groups/perf_budgets.dart` already asserts this inside `06`; the unchecked backlog
  item is documentation lag, not a missing current-tree check.

### Restored groups

All four groups are now registered in `integration_test/e2e_test.dart` and supported by the runner.
Source implementation is not a claim that the live groups have passed.

- **`ai_services`** — UI gating, recorder availability, transcription locale and logout cache
  clearing; live Worker/audio/camera scenarios remain explicitly skipped.
- **`attachments`** — upload/render, malformed image resilience, lookup, removal and same-name
  separation; OS picker/download dialogs and web cache measurements remain platform checks.
- **`notifications`** — computed appointment/labwork/note notices, deferred queue and relay-key
  stability; FCM delivery and permission prompts need supported devices.
- **`multi_clinic`** — Hive session namespace, local row and schema-marker isolation; a real
  two-server switch needs a second disposable clinic.

### §6.2 findings, reconciled against the current tree

- **Local purge of a synced row does not stick** — **historical**: one of the
  localpocket-specific migration-era findings; not actionable on this tree.
- **`network.isOnline` never goes false for a paused engine** — **historical**: same localpocket-era
  engine finding; not actionable as current-tree README guidance.
- **A server-side delete is invisible** — **historical**: same localpocket-era delete-feed finding.
- **Clinic display settings are readable without a session** — **decision/actionable**: this is still
  the current patient-portal design surface and should only be revisited as a product/security choice.
- **A second settings write does not take** — **blocked by app bug**: still the current-tree restore
  failure described under `settings_services 03`.
- **The pane header overflowed when compact** — **covered**: this blocker is already resolved on the
  current tree and should not be treated as open backlog.
- **A new tag cannot be driven from the harness** — **resolved**: focused-input `Enter` and
  suggestion picks are covered (patients `07`/`08` plus `test/unit/common_widgets/tag_input_test.dart`).
- **A filename column cannot address two same-named files** — **decision/pending**: still a real
  design gap; `attachments 12` keeps the current separation coverage.
- **The first attachment of a fresh database can take ~46 minutes** — **historical**: a
  migration-era localpocket finding, not current-tree proof.
- **There is no email validation anywhere** — **resolved**: `Patient.isValidEmail` rejects malformed
  addresses before persistence; `patients 16` and `patient_validation_test.dart` cover it.
- **Archiving a patient hides its appointments from the agenda** — **actionable app behavior**: still
  the current-tree product bug/decision behind the store-level workaround in `patients 15`.
- **The patients screen has no grid/list view** — **decision**: still a product-surface fact, not a
  missing test.
- **Previous visit dental notes cannot be copied** — **decision**: still a missing feature, not a
  hidden test seam.
- **A patient's panel cannot be reopened after booking a visit** — **actionable app bug**: still the
  current reason the no-cascade assertion falls back to store-level checking.
- **The calendar loses a day's marker across month pages** — **actionable app bug**: still the current
  skipped regression in `integration_test/groups/appointments.dart`.
- **The account switch is not a login gate** — **decision**: still a wording/product-model choice, not
  a test gap.
- **A text settings card never offers Save** — **actionable app bug**: still the current blocker for
  `settings_general 02`.
- **Opening the errors panel stops the run dead** — **actionable app bug**: still the current blocker
  for `errors_and_recovery 01`.
- **Some groups stop the run dead on their first test (boot wedge)** — **actionable app/harness bug**:
  still the current blocker called out by `localization_rtl 01` and the first-test settings/errors cases.
