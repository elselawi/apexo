### ____0.15.1____

- Bug Fixes
    - Canceling a DICOM scan preserves pending batches without auto-approving them. Stopping scanning also cancels an in-flight manual scan when no periodic timer exists.
    - Ordinary attachment deduplication no longer mistakes hash-shaped filename prefixes for the content identity of another attachment.
    - CSV imports retain a final empty quoted field even when the file has no trailing newline.
    - File metadata checks run outside the UI isolate, and the full project passes analysis with no warnings or informational diagnostics.
    - Store persistence serializes document writes, attachment queue changes and synchronization. Concurrent synchronization callers await the same real result instead of a ten-second polling fallback; idle stores no longer keep polling timers alive.
    - Store writes retain later edits, journal remote updates before network I/O, and wait for in-flight work before switching persistence targets. Reloads ignore outdated sessions and do not replace pending edits; progress counters clear on failed storage and attachment operations.
    - Observable restoration awaits asynchronous deserialization. Observer dispatch tolerates self-unsubscription, push events snapshot collection values, and persisted writes capture values at notification time with handled errors.
    - Network callbacks use the delivered status rather than a later global value and isolate synchronous/asynchronous failures. Disposed remote stores cannot restart health retries.
    - Saved panel drafts stay separate from stored records; archive/restore updates the draft flag without falsely marking unrelated edits as saved.
    - Cached AI tokens are scoped to their clinic server, invalidated on logout, and not populated by stale authentication responses. Backup busy flags clear after failed operations.
    - Partial DICOM approvals no longer show a completion toast, upload phases reset for each date group, and anonymous manual-match keys are cleared correctly.
    - Collection-valued notification fields now retain a deep pre-edit snapshot, so edits to attachments and other lists are detected correctly.
    - Remote connection retries keep one timer instead of spawning duplicate retries.
    - Panel saves block overlapping writes, reset progress on failure, and only change a new panel into an existing one after a successful save. Both Control keys are recognized by panel shortcuts.
    - Synchronization and reconnect actions await registered asynchronous callbacks; synchronization progress is reset even when an operation fails.
    - SMTP TLS labels fit their dropdown and app-password links wrap instead of overflowing narrow settings columns.
    - Service-settings loaders ignore responses after their widgets are disposed. Failed metadata reads no longer trigger writes of default server settings, and changing the interface language no longer reauthenticates or resynchronizes clinic data.
    - Narrow tag inputs keep valid width constraints, and the default insights range ends at the current month's actual final instant.
    - DICOM persistence initialization can retry after failed box opening, approvals are serialized before imports start, and Arabic name normalization preserves non-honorific tokens.
    - CSV imports reject unterminated quoted fields. Restoring patient-side sessions handles failed authentication without an unhandled asynchronous error.
    - Removed diagnostic logging of transcription text, websocket URLs, device tokens, and service-worker payloads.
    - **The appointment reminder's View button now opens the calendar.** The in-app notice for today's appointments carried `"appointments"` as both its navigation target and its "hide me here" route, but the calendar screen's route id is `calendar` — so pressing **View** did nothing at all, and the button stayed on screen while the user was already looking at the calendar.
    - **The navigation pane's header no longer overflows when the pane is minimal.** `CurrentAccount` laid out a fixed 130px name box beside the logout button in the ~26px strip a minimal pane gives the header, which reported `A RenderFlex overflowed by 214 pixels on the right` at a 300px window (a phone layout, or a small desktop window). Below a width that can hold both it now draws nothing — the logout is also on the dashboard's command bar — and above it the name shrinks with an ellipsis instead of pushing the row apart.
    - **The accounts screen's counts strip no longer overflows.** The strip (refresh + the admin/user counts) measured its children against the full window and reported 5.3px at a 1280px window, and its refresh button's inner `Row` — which defaults to `mainAxisSize.max` inside a `Row`, which hands a non-flex child unbounded width — claimed the rest of the bar and reported 16px. The strip wraps now and that row is `MainAxisSize.min`.
    - **A disabled shell action is disabled again.** `NetworkAction.disabled` is set in four places (sync and errors while a sync runs, while the session works offline, while there is nothing to reconnect) but the app bar ignored it and always passed `onPressed` through, so a disabled action was still pressable and a tap on it silently did nothing instead of failing loudly.
    - **The login screen's "clear" button now clears the form.** It emptied the stored url and email but not the three fields, which hold their own controllers and are only ever written back with *non-empty* values — so the form looked signed in with nothing behind it.
    - **An offline login now says it is offline.** `activate(online: false)` never set `proceededOffline`, so it stayed at whatever the last online login left it and the shell still offered a sync that could not work.
    - **The first-launch welcome dialog is reachable again.** The check ran once, from a one-second startup timer — before the login that creates a clinic can set `isFirstLaunch` — and nothing re-checked it, so the dialog only ever appeared if a clinic materialized within that second. The login calls it now.
    - **The deferred push queue could only be initialized once per process.** Its Hive box was `late final` while `reset()` exists so the next login re-runs `init()` for its own clinic server; the second assignment threw `LateInitializationError` inside `Messaging.identifyDevice`, which the login awaits — so every login after the first left the clinic's relay key unensured and no device registered.
    - **A title that starts with an emoji no longer crashes the screen that lists it.** `ItemTitle`'s avatar drew the first *code unit* of the item's title, which splits a surrogate pair — and an appointment's title is built from `DF`'s formats, which start with a calendar emoji (`📅 27 / 09 / 2026 🕒 07:37 AM`). Half of one is not a string Flutter can lay out: the paragraph builder threw `Invalid argument(s): string is not well-formed UTF-16` and the entire frame was lost, on every screen that lists appointments. The initial is a whole code point now, and the other three places that shorten user data by code unit — the 14-character name cuts in the calendar, notes and insights screens, the patient label's 10-character cut, and `isoCC()`'s two-letter country code (a pasted flag emoji is four code units) — go through `lib/utils/clip.dart`, where the "is it too long to show?" guard (`fitsInCodePoints`) and the cut (`clipCodePoints`) both measure code points, so a label is never trimmed to something that would have fitted. `test/unit/utils/clip_test.dart` pins it: no prefix length of an emoji-bearing label may be malformed UTF-16.
    - **A multiline tag field no longer overflows its own box.** The prescription field forced the same `height: 40`-per-row formula in both modes, and the box around the field takes 4px a side (a 1px border *plus* 3px padding) while the copy of the formula only budgeted for the padding — so with one chip the field's column had 32px for 36px of content. It also ignored the 3px between chips and the 250ms its `AnimatedSize` stays at the *previous* height after a tag is removed, so adding and then removing a prescription reported `A RenderFlex overflowed by 4.0 pixels on the bottom`. A multiline field sizes itself now.
    - **Deleting a record from its panel no longer leaves the panel asking to save.** `RowPanel.setArchived` archived the record in the store but did not re-baseline the panel's snapshot, so a panel that had been edited kept reporting unsaved changes: the header still offered **Cancel** over work that was already stored, and closing it asked "close anyway?" about a record that is no longer there. `persist()` had always re-baselined; the archive path is a store write of its own and does the same now.
    - **The appointment history flyout no longer overflows.** Its title row laid the icon, the "other appointments (n)" label and the patient's name out at their natural widths inside a 340px flyout, which reported `A RenderFlex overflowed by 18 pixels on the right` on every visit that had a long name in it. Both halves are `Flexible` with an ellipsis.
    - **A patient's name no longer pushes the row it sits in past its box.** `ItemTitle`'s title chip had a *minimum* width equal to the caller's `maxWidth`, and a dashboard square hands that row 117px of space while asking for 123 — `A RenderFlex overflowed by 5.7 pixels on the right` on every square with a patient in it. The chip is `Flexible` with no floor now; it ellipsizes its own text.
    - **A tooth's condition is reported as soon as it is recorded.** The chart keyed each tooth with the `selected` flag it read once, when the chart opened, so recording a condition left the key saying "no condition" — the state the teeth-chart and patient-panel tests read. It is derived from the draft note now, and history (an earlier visit's note) still reads as unselected.
    - **The calendar preserves broad date access without fractional scroll errors.** Its page viewport uses a whole logical-pixel width rather than restricting navigation to three years. The original ±9999-day range is retained and expands to include an initially selected appointment outside that range.
    - **The search box is its own accessibility node again.** `TopSearch`'s field carries a `Semantics` boundary, so an assistive technology gets a node the size of the bar rather than the whole content area (measured before: 960px tall).
    - **Only one changelog dialog can be raised per process.** The startup check now runs from two places (the startup timer and the login), and a second raise left two dialogs stacked — a test that raises its own saw the one it closed come back.

- Testing & Developer Experience
    - `tools/run_e2e_groups.ps1 -Groups a,b,c` runs several end-to-end groups in one command: one `flutter test` per group (which is the only way to *isolate* a group — a group is selected by a define, not by a name filter), each teed to `tmp/run_<group>.log`, with a one-line summary per group at the end — the summary prints each log's timestamp, and each log is deleted before its group runs, because a leftover `tmp/run_<group>.log` is days old and reads exactly like a fresh result. The runner leaves unrelated app, test and build processes alone; if an interrupted earlier run holds native assets, stop that run's specific process IDs. Unknown or removed groups are rejected, failed groups produce a nonzero script exit, and `StopOnFailure` also stops on build/startup failures. If the build does get that far, `firebase_core`'s CMake skips its Firebase C++ SDK download whenever *a* file sits at `build/windows/x64/firebase_cpp_sdk_windows_13.5.0.zip` — existence, not size — so a truncated archive (`-5`, ZIP decompression failed) or a leftover empty `build/windows/x64/extracted` (CMake errors about a non-existent `firebase_app` target) is not a code problem: delete both and let it download again (`integration_test/readme.md` has the signatures).
    - `tools/key_audit.ps1` reports every widget key the suite waits for that the app never attaches. It is at zero now; a count above zero is the fastest explanation for a group that times out waiting for a screen.
    - Navigation is typed now: a route is an `AppRoute` value (one catalog in `lib/app/routing/app_route.dart`), not an id string, so that mistake is a compile error instead of a silent no-op. The router stores the current route rather than an index into a permission-filtered list — nothing can drift when permissions change — and the eleven per-route `onSelect` callbacks became one `_syncStores` switch. Removed the always-true `accessible` flag, the unused `onFooter`/`footerItems` pane list, and the unreachable lock branch in the navigation pane.
    - The phone layout's bottom navigation bar now carries the widget keys its tests look up (`WK.bottomNav`, `WK.bottomNavButton(id)`, `WK.bottomNavMore`): they were declared but never attached, and the overflow list is typed instead of `dynamic`.
    - **The end-to-end suite's keys are attached again.** Ten handles the e2e groups wait for were declared in `lib/widget_keys.dart` and attached to nothing, which made `Fixtures.openRoute` time out after a tap that *had* landed and reddened whole groups: the six screens' command bars (`WK.btnNewPatient`, `WK.btnNewAppointment`, `WK.btnNewAccount`/`btnNewAdmin`, `WK.btnNewSupplier`, `WK.btnNewLabwork`, `WK.btnNewNote`), the shared list chrome (`WK.listSearch`, `WK.showMore`), and the shell's actions (`WK.globalAction(id)`, which needed a stable `NetworkAction.identifier`).
    - **The suite's "other device" wrote a row no Apexo client writes.** `RemoteRows.insert` created the `data` row with a value that carried no `id` — while a store is keyed by the *document's* id and builds each `Model` from the value, and `Model.toJson` always writes the id there. One row, two ids: `sync_offline 01`/`03` failed on `the pulled row is not readable by name` *after* the row had visibly arrived (a key lookup found it). The fixture completes the value with the server's id now, and `03`'s own brittle assertion — it required the shell's sync action to be free the instant it wanted to press it, which only ever read `false` while the app bar ignored `NetworkAction.disabled` — is a wait for the action to become pressable instead.
    - **…and the rest of them, so nothing the suite asks for is missing.** The remaining **42** handles the suite waits for went on: the settings cards and the six services sections with their fields (`WK.settingsItem`/`serviceSection`/`serviceField`/`backupRow`), the calendar's day cells and today button, the dashboard's squares and counts, the notes board (columns, cards, the add buttons, the inline saves), the accounts panel's fields and permission rows, the expenses order row, the DICOM screen (scan, auto-import, a pending card, approve, change-match) and the labwork editor. `pwsh -File tools/key_audit.ps1` — which reports keys the suite waits for that the app never attaches — is at **zero**; 28 handles remain declared but unused. One of the labwork fields carried the **lab-name** key as well, so that key matched two widgets and the order-notes box could not be addressed at all; and the backups section's cron key sits on the **preset `ComboBox`**, not on the disabled box that only shows the expression (a tap on that one does nothing but warn).

### ____0.15.0____

- New Features & Enhancements
    - **Automatic Server Schema Reconciliation**: On administrator sign-in the app now safely applies the latest PocketBase collection definitions (rules, fields) to existing clinics via a non-destructive, version-gated schema import that runs once per app release per clinic. This is the mechanism that delivers rule changes — such as the patient portal scoping — to already-installed clinics.

- Security & Compliance
    - **Patient Portal Access Scoping**: The patient-facing `public` view is now scoped server-side to a required `pid` query parameter — a patient can only ever retrieve their own appointments, and the full appointment list can no longer be enumerated. Patient identifiers taken from links/QR codes are strictly validated to block filter injection. Existing links and QR codes keep working unchanged.

- Bug Fixes
    - Fixed the patient portal's appointment view being publicly queryable without patient scoping.

### ____0.14.1____

- New Features & Enhancements
    - **DICOM / RVG Hardening**: Improved scan caching, patient matching, automatic imports, appointment reuse, DICOM identity handling, and linked-patient management.
    - **Linked Patient Management**: Added search, deleted-link filtering, sortable columns, active/broken status indicators, unlink actions, and per-patient imported-file counts.
    - **DICOM Viewer & File Sync**: Improved original/preview upload deduplication, companion-file deletion, deferred uploads, conflict reconciliation, and stale-file healing.
    - **HIPAA & GDPR Planning**: Added a compliance planning document covering patient data, DICOM metadata, AI processing, and required safeguards.

- Testing & Developer Experience
    - Added extensive deterministic tests for DICOM scanning, approval, rollback, registry persistence and concurrency, controller lifecycle, file synchronization, deferred uploads, conflict merging, and localization.
    - Removed verbose per-file DICOM scan debug output from normal test and application logs.

- Bug Fixes
    - Fixed DICOM approval rollback and retry behavior so failed files remain discoverable.
    - Fixed blank-patient batch collisions and unified DICOM upload identity handling across importer and remote sync.
    - Fixed file-only deferred uploads, authoritative remote file reconciliation, and DICOM original/preview cleanup.
    - Updated `dicom_toolkit` to 0.2.8.

### ____0.14.0____

- New Features & Enhancements
    - **DICOM / RVG X-Ray Import (Windows)**: One-click workflow to import X-rays from RVG sensors. Configure watch folders once, then Apexo scans for new `.dcm` files every 90 seconds. Smart matching suggests which patient each X-ray belongs to based on embedded metadata. Once a DICOM patient ID is linked, future X-rays auto-import without manual steps. Includes a full cross-platform interactive viewer with windowing, rotation, color-map presets, invert, and measurement tools (ROI statistics, ruler in mm). Imported X-rays sync to all devices via PocketBase.
    - **Smarter Offline Conflict Resolution**: Concurrent offline edits now use field-level merging so non-conflicting changes from different devices are preserved, while conflicting values continue to use last-write-wins behavior. Pending image uploads are retained during reconciliation.
    - **More Reliable Offline Sync**: Hardened store sessions, deferred file uploads, local persistence, reactive caches, and file lookup by content hash to improve synchronization reliability across intermittent connections.
    - **Safer Patient-Side Access**: Strengthened patient-side access and country-code lookup handling.
    - **Dashboard Accuracy**: Archived appointments are now excluded from dashboard results and summaries.

- Testing & Developer Experience
    - Added broad unit and live-backend test coverage across core models, stores, synchronization, locking, DICOM workflows, AI services, notifications, localization, and utility features.
    - Reorganized tests into clearer unit and live-backend suites, added deterministic fixtures and test helpers, configured live-test tags, and enabled parallel execution where safe.
    - Improved notification callback handling and reactive state cleanup to make runtime behavior more robust.

- Bug Fixes
    - Fixed observable dictionary copying after item removal.
    - Standardized localization strings so new entries begin with a lowercase letter.

### ____0.13.0____

- New Features & Enhancements
    - Voice & Audio Transcription: Live streaming audio transcription for dental history and post-op notes. Voice input for individual text fields with a recording bubble. AI services authentication caching for faster startup.
    - Calendar Timeline View: Optional timeline view in the calendar alongside the existing agenda mode, with appointment duration editing directly inside the appointment panel.
    - Archive → Delete Overhaul: Renamed "Archive" to "Delete" across the app. Deleted items can now be opened in panels and restored or permanently removed. Consistent teal accent for restoration actions.
    - Persian Language & Jalali Calendar: Full Persian (Farsi) translation and support for the Jalali (Shamsi) calendar system, thanks to contribution from [Ar7in](https://github.com/ar7in).
    - Greek Language: Added Greek locale with full translation coverage, thanks to contribution from [Aris Pal](https://github.com/sealine150).
    - Expense Receipt Scanning: Scan receipts from photos to auto-fill expense items.
    - Post-Update Changelog Dialog: A "What's New" dialog automatically shown after app updates, parsed from the local changelog. Tapping the version number in the app logo also opens it.
    - File Upload Limits: Configurable file upload size limits in settings.
    - Other Appointments Mini-Window: Quick view of a patient's other appointments from within the appointment panel.
    - Appointment History: Added appointment history to the calendar screen for quick reference.
    - New Grid Gallery: Redesigned image grid gallery with an improved file uploading system.

- UI & UX Polish
    - Permissions Redesign: Rewrote the permissions system with a clearer layout that accommodates more characters and adds a dedicated revenue display permission.
    - Search Visibility: Made the search bar more visually prominent across all screens.
    - All Dialogs Keyboard-Aware: Every dialog in the app now properly handles keyboard dismissal (barrier dismiss + Esc key).
    - Icon Consistency: Unified all delete icons to `WindowsIcons` and replaced `FluentIcons.undo` with `WindowsIcons.undo`.
    - Dark Mode Button Tweaks: Refined button styles for better contrast in dark mode.
    - Recording Bubble UX: Improved the recorder bubble with a 3-minute hard limit, smoother animations, and clearer semantics for voice auto-fill.
    - Layout Fixes: Prevented text overflow in Greek and Spanish locales, fixed overflowing minimized panels, and prevented treatment labels from scrolling when viewed vertically.
    - Network Actions Localized: Error messages and sync status labels are now translated.
    - More readable duration since last appointment in the patients screen and between appointment cards.
    - Added tooltips for patients screen bottom labels.
    - Panel open/close animation when navigating between panels.

- Bug Fixes
    - Fixed panel search/filter state resetting when opening panels on tablets (medium screens).
    - Fixed a bug where reopening a panel with a different tab wouldn't update correctly.
    - Fixed scroll controller not being attached in the Labworks screen.
    - Fixed selecting note columns in the archived screen not working.
    - Fixed deleted appointments being incorrectly counted in today's revenue summary.
    - Fixed an infinite sync loop in the settings store caused by `.set()` calls inside the isolate.
    - Fixed country code override not being applied when parsing extracted phone numbers.
    - Fixed a `TextEditingController` disposed before use error on the login screen.
    - Fixed the "Open Patient" button inside appointments not responding.
    - Fixed money amounts displaying in the wrong text direction (now always LTR).
    - Fixed duplicate images appearing when swiping between appointments.
    - Fixed `TagInputWidget` not updating when its initial value changed (affected prescription fields).
    - Fixed inconsistent hover color between patients page and other pages.
    - Fixed extra notes icon and color based on the entry itself, not the first item.
    - Fixed calendar screen not listening to archive toggle.
    - Fixed search, filter, sorting, and slicing state resetting on medium screens (tablets) when opening/closing panels. Root cause: `NavigationView` rebuilds its widget tree when `PaneDisplayMode.auto` switches modes during the width animation. Fixed by anchoring each route screen body with a cached `GlobalKey` via `KeyedSubtree`, so Flutter can reparent and preserve `StatefulWidget` state across tree restructuring.
    - Added multiple `mounted` guards to prevent state modifications after widget disposal.
    - Error handling: duplicate errors now pulse the red indicator instead of showing multiple dialogs; tapping it reveals the full error list.
    - Catch and report errors during attachment uploads gracefully.

### ____0.12.0____
- New Features & Enhancements
    - In-App Settings Management: Configure 99% of relevant settings directly within the app—no more constant trips to the PocketBase dashboard.
    - Smart Phone Number Input: Complete overhaul of phone number handling. The new, wider text field accepts any raw string, auto-validates, auto-appends country codes, and extracts numbers into clickable buttons on the fly.
    - Data Portability: Major overhaul to CSV Export and introduced brand-new support for CSV Import.
    - IP-Based Location Auto-Fill: Removed manual country code configuration; the app now automatically detects and fills your ISO country code based on your initial IP address visit.
    - Session Expiration Alerts: Added an inline login prompt if your authentication token suddenly becomes invalid while the app is active.
    - Deep Linking Panels: Added the ability to target specific tabs directly when opening the Patients and Appointments panels.
    - Interactive Screen Navigation: Screen titles are now clickable, revealing a dropdown menu to seamlessly switch between different sections.
    - Demo Environment Upgrades: The demo app now automatically generates sample notes for a better testing experience.
    - Dental chart extra-notes: Extra notes can be added on top of each selected treatment.
    - Dental charts on patient can now show previous notes and extra notes.

- UI & UX Polish
    - Dashboard Redesign: Fully revamped dashboard layout featuring clickable suppliers for quicker navigation.
    - Comprehensive Page Overhauls: Major structural and visual redesigns implemented across the Patients, Accounts, Labworks, Expenses, and Suppliers pages.
    - Global Component Unification: Standardized the design of Search bars, Command bars, Error dialogs, and "Show More" pagination buttons across the entire app for a highly consistent feel.
    - Chart Optimizations: Redesigned bar and radar charts for sharper visuals and improved responsiveness across all platforms and screen sizes.
    - Accessibility & Navigation: Added barrierDismissible and dismissWithEsc support to all applicable dialog windows.
    - Cleaner Polish: Removed the unintended white background from the Windows app icon, introduced a more semantic login screen, and added a subtle 2px spacing fix to network action layouts.
    - Conditional Visibility: Hidden (rather than disabled) text input fields when their parent tag input component is disabled.
    - Media Layouts: Integrated the GridGallery widget into the orderRow component for better image handling.

- Performance & Core Architecture
    - Memory Leak Resolution: Implemented proper dispose logic for all applicable controllers app-wide, resulting in greater stability and noticeable performance gains.
    - Smoother Layout Rendering: Unified the page scaffold into the main app screen, eliminating the need to manually define safe insets for every single page widget.
    - Faster Loading Times: Optimized the Patients page for faster data rendering.
    - Isolate Optimization: Shared the globalSettings store directly with the modellingDocs isolate to efficiently retrieve country codes.
    - Startup Initialization: Configured the settings store to initialize first, ensuring user preferences are ready immediately on launch.
    - Code Reusability: Created a centralized utility function for date formatting, cleaning up repetitive code across the app.

- Bug Fixes
    - Platform Specifics: Fixed macOS version-checking routines to ensure update prompts trigger correctly.
    - Keyboard Layout Issues: Resolved a bug preventing the bottom navigation bar from displaying properly when the software keyboard was open.
    - Data Filters: Fixed a bug in the dashboard controller that mistakenly displayed archived appointments even when hidden filters were active.
    - Permissions Fix: Resolved access and permission bugs on the Expenses and Notes pages.
    - RTL Layouts: Corrected an inverted swipeDetector orientation issue in Right-to-Left (RTL) language contexts.
    - Flyout Fixes: Hardened the global flyoutFix patch and applied it more robustly across all UI panels.

### ____0.11.0____
- New field on expenses: "notes"
- Pasting a phone number now removes the spaces
- Prices & payment currency formatting
- Fixed internals & UI Improvements
    - null safety using withValues inside LinearGradient
    - better null safety on accounts
    - Bad state on dashboard screen
    - initialization of deferred pushes store
    - Notification on iOS safari
    - multiline in dental chart notes
    - updated calendar icon
    - bottom navbar inconsistencies
    - ask user to login again if the token expires while the app is open
    - fixed an issue when adding an order to en empty supplier
    - "what's a server" teaching tip
    - renamed stats to "insights"
    - prevent multiple instances from running on macos
    - bottom nav bar appearing behind android os bottom navigation buttons
    - fixed slow labworks screen
    - fixed and simplified caching mechanisms

### ____0.10.4____
- notifications and sounds for windows

### ____0.10.3____
- fixed safari iOS notification error

### ____0.10.1____
- updated version fetching mechanism


### ____0.10.0____

This is one of the most feature-rich updates yet!

-   Full redesign of the expenses system
-   New Feature: Notes & Tasks
-   New Feature: Push notifications
-   New Feature: integrated patient page, with push notifications support
-   New Feature: annotate and draw on images
-   Performance improvements through delegating JSON-Store computations to a seperate thread so that it doesn't block the UI or cause any jank
-   Various other bug fixes and improvements


### ____0.9.4____

-   patient link can now link to a telegram bot, that is as functional as the patient web page
-   contact and email buttons (hotlinks) from inside the app
-   more apparent clickable patient
-   show other appointments images in the appointment gallery
-   launch URL that downloads the latest version for the specific platform on the update dialog
-   done appointment checkbox UI improvement


### ____0.9.1____

-   UI & UX improvements on the dental chart and treatment filtering system
-   fixed some errors happening when offline
-   dental notation can be switched from the settings
-   viewing day total payments in the calendar widget


### ____0.9.0____

-   predefined treatment on dental chart and the user can filter patients by them


### ____0.8.2____

-   fixed: labworks screen overflowing
-   fixed: accounts route shouldn't be on bottom navabr
-   fixed: color of time difference in appointments list in darkmode


### ____0.8.1____

-   fixed a bug where when resyncing the routes are reset
-   fixed a bug where a new user can not have its persmission changed unless its created and being edited


### ____0.8.0____

-   Major performance improvements
-   BREAKING: Accounts are now where you find operators, doctors, users, admins and permissions
-   improved labworks screen (showing operator)
-   improved expenses screen (showing due total)
-   fixed panel header width
-   fixed darkmode issues with charts and dashboard
-   more consistent dialog styling
-   confirm deletion on images
-   other minor tweaks


### ____0.7.2____

-   fixed bugs and usability issues in expenses screen


### ____0.7.1____

-   fixed a bug in browser uploading
-   close fullscreen view when deleting an image


### ____0.7.0____

-   longer names are now visible 
-   added emoji indicatros to panel titles 
-   can delete images when they are viewed in fullscreen 
-   support for image uploading in web browsers 
-   new and improved expenses logging system and screen


### ____0.6.0____

-   Payment summary as you enter payment and cost at the appointment panel
-   Labworks are now part of the appointment but their information is aggregated at a speicific page
-   Re-designed show more button with scrollability


### ____0.5.1____

-   Added payments summary on the appointments calendar page


### ____0.5.0____

-   When applying a filter made it more clear
-   Adbility to set notes on a dental chart from the appointment panel (i.e. specific to an appointment)

### ____0.4.3____

-   Fixed: Admin mode being activated if its a first login into any device.
-   Fixed: disable date time picker if the appointment is open.
-   Fixed: Barrier behind panels in small screens.
-   Fixed: Show more button in datatable dark mode isn't visible.
-   Scaled checkboxes.

### ____0.4.2____

-   Implemented sentry for crash and error reporting.
-   Labworks can now be locked to a specific user.
-   Expenses can now be locked to a specific user.
-   Fixed: Synchronization of appointments, labworks, and expenses must be preceded by a successful synchronization patients and doctors.
-   Fixed: creating patient on the fly if its unusually not found.
-   Fixed: Substring safety in item title.

### ____0.4.1____

-   Fixed: Swiping in calendar when there's no appointment is not responsive.
-   Fixed: Translated: "there's no upcoming appointments for this doctor".
-   Fixed: Changing time would silently reset changed date.
-   Fixed: Swipe detector being too sensitive.
-   Fixed: Icon as password obscure indicator in login screen.
-   Fixed: Better alignment for top actions.
-   Fixed: "Update to newer version" prompt not working correctly.
-   Fixed: Panel tab titles having their first letter lowercased.
-   Fixed: Side panels stay open when logging-out/logging-in.
-   Fixed: Hide archive button for a data table item, if the item is open in a side panel.
-   Fixed: Some text fields didn't have placeholders.
-   New feature: dark mode.

### ____0.3.1____

-   Fixed issue with panel content not being scrollable

### ____0.3.0____

-   Fixed: Command bar height inconsistencies between screens
-   Fixed: Shouldn't change the time when just editing the date.
-   Fixed: Android system icons set to dark.
-   Fixed: Show less aggressive user mode indicator on dashboard.
-   Fixed: Submitting on fields on login screen should initiate the login process.
-   Fixed: Option in settings screen to delete/reset all local data and pull from server.
-   Fixed: avatars are not loading on datatable unless they are loaded from appointment gallery.
-   Fixed: For better memory management, evict images once the widget is disposed.
-   Fixed: Fpr better memory management, run image downloading http requests in a task que.
-   Fixed: Improved performance and memory usage by utilizing less shader intensive UI elements.
-   New: Added search emoji as search icon in filtering field
-   New: __Bottom navigation bar__ on small screens
-   New: __Side panels__: non-blocking editing/viewing windows, and a user can have multiple of them open at once.
-   New: Swiping left/right on calendar should navigate through days.
-   New: Load/create/download thumbnails in the app UI, unless a full photo is explicitly opened.

### ____0.2.6____

-   Multiple improvements in regard to performance and memory efficiency


### ____0.2.5____

-   Fixed sorting of labworks and expenses
-   Fixed change detection and reflection in demo


### ____0.2.4____

-   Web demo setup
-   Splash screen for web
-   Fixed issue with statistics screen done & missed chart


### ____0.2.3____

-   Fixed issue of android login from web app
-   Fixed issue of fast user


### ____0.2.2____

-   clear button in datatable search
-   fixed issues with photo uploading and sync


### ____0.2.1____

-   Load images on request
-   fixed issue with dates
-   minor visual improvements


### ____0.2.0____

-   Multiple improvements and fixes for better usability


### ____0.1.0____

-   Initial release
-   Distributed for windows, APK and web

