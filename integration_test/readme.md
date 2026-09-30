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
`Cross-Origin-Embedder-Policy=require-corp` and the database opens.
`integration_test/web_open_test.dart` is the smallest test that covers the database
handshake.

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
# web, one file instead of the whole suite (about a minute and a half)
pwsh -File tools/run_e2e.ps1 -Target web -WebHeaders -Entry integration_test/web_open_test.dart
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
file — `flutter test`'s `E2E_GROUP` define is the lever instead, and `-Entry
<file>` is what makes a single-file web check (like `web_open_test.dart`) cheap
enough to run on every change.

`dart integration_test/watch.dart [filter]` re-runs the suite on save (it shells
out to `tools/run_e2e.ps1`).

### All of them

`pwsh -File tools/run_e2e.ps1` with no `-Group` runs **every registered group, in the order the
file registers them** — and it builds once, so it is by far the cheapest way to cover the whole
suite (25 group files; `attachments`, `notifications` and `multi_clinic` have no group file —
`ef3a3fd` removed them with the migration). The order is not decoration: each group's tests use
the records the groups before them left behind, so a full run is the faithful measurement, while
one process per group is the one that says *which* group a red count belongs to:

```bash
pwsh -File tools/run_e2e_groups.ps1 -Groups login,patients,calendar
```

That loop runs `run_e2e.ps1` once per group, tees each to `tmp/run_<group>.log`, kills stray
`flutter_tester` processes in between, and prints one summary line per group. It is what the
results in `todo.md` were measured with.

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

The recovery is: kill the strays — `Get-Process apexo,flutter_tester,cmake | Stop-Process -Force`
(`tools/run_e2e_groups.ps1` does this between groups, and `apexo`/`flutter_tester` alone are not
enough: the locking process is usually **`cmake`**) — then delete whatever it was holding
(`build/windows/x64/firebase_cpp_sdk_windows_*.zip` and `build/windows/x64/extracted/` for the last
one; `build/windows/x64/CMakeCache.txt` + `CMakeFiles` for the third), and re-run. `flutter clean`
does *not* help while a stray holds the tree, and can make it worse.

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
  test problem (see `todo.md` §6.2).
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
  assertion. Three real ones came out of this suite (`todo.md` §6.1); if a test fails with no
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

### Backlog

`integration_test/todo.md` is the list of groups we still owe the app. Read its opening
note first: most of its "verified green" lines were measured against the
localpocket-migration tree, which `af8e771` rolled back — this suite was restored against a
shape of the app that is no longer here. The keys it waits for are attached again (the audit
in §0.2 is at zero), but **the migration branch's bug fixes are not**: the rollback dropped
the code with the UI, so the suite keeps re-finding bugs that section 6.1 had already
recorded as fixed.

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
  }, skip: 'needs the fake-clock seam (todo.md §0.2)');
  ```

  That replaces the old `--` suffix. There is no replacement for the old `++`
  suffix: every test stands on its own now, and "this one must run first" is a bug
  in the test, not a marker.
- A failing test fails the run (the tool reports it by name); nothing in the suite
  reports success on a step that failed.

`todo.md` lists the groups still to write, with the test names and what each one
should prove.

### Why the change?

The old harness (`base.dart`, one `testWidgets` running every group, a mode file)
existed to boot the app once and share the session. It cost per-test reporting,
filtering, `skip`, timeouts and sharding — CI saw a single test called "runs every
group". Since a per-test boot is ~1s and the app's own state survives anyway, the
harness bought little for what it hid.
