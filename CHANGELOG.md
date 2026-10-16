### ____0.15.2____
- New feature & Improvements
    - New and redesigned dental charting experience



### ____0.15.1____

- New Features & Improvements
    - The tooth editor opens as a wheel of treatments around the tooth: choosing one records it and leaves a wide notes field, with the chosen treatment on one side of the top, dictation on the other, and Save and Clear controls along the bottom. Save closes the editor with the note kept; Clear takes the note away and puts the wheel back. Tapping a treatment twice, or anywhere outside the editor, closes it; a treatment of your own can be typed straight into the field, with no save button. Teeth that carry records show a read-only summary of earlier visits, keeping the patient's baseline apart from dated visits; any visit listed there can be opened from the summary or brought into the record being edited, and a treatment the chart holds without a visit to back it is named as the chart's note instead of appearing as a bare label. The separate expanders that used to list earlier appointment notes have gone: that history lives in this summary now.
    - Patient browsing keeps the detailed table view, with avatars, patient information, search, sorting and selection. Removed the sparse grid view and its toggle.
    - Patient details now warn about invalid email addresses and prevent saving them until corrected. Leaving the email blank is still allowed.
    - A new patient-page access switch lets clinics hide a patient's appointments from the patient portal. Existing clinics receive the server update on administrator sign-in; access changes take effect after synchronization.
    - Tooth treatments and notes from earlier appointments can be copied into the appointment being edited.
    - Rows in patients, appointments, labworks, expenses and accounts open a context menu on a long press (touch) or a right click (mouse, trackpad or pen): the actions that row already offers, anchored where you pressed, with the platform's touch feedback on the long press and following the reading direction in Arabic and Persian. On the web, where the browser keeps right click for itself, the long press opens the menu. A row that opens a panel now lists one item per tab, so a patient's dental notes, an appointment's operative details or a supplier's paid orders sit one press away, and reaching a patient is part of the same menu: call, text, WhatsApp, Telegram and email.

- Reliability & Bug Fixes
    - Patient tables and appointment payment summaries now refresh consistently after appointment edits, reassignment, archiving and synchronization, including in already-open patient panels.
    - Fixed image and X-ray downloads on the web and enabled saving user-selected files in sandboxed macOS builds.
    - Improved saving and synchronization so overlapping operations do not lose later edits, pending offline changes survive reconnects, and outdated login sessions cannot overwrite current data.
    - Queued saves are preserved locally when logging out or switching clinics. Incoming updates become visible even while another record is being edited, and bulk imports keep the archive index consistent.
    - Conflict resolution keeps the winning edit's prescriptions, tags, tooth annotations and drawings, including intentional deletions, rather than restoring removed entries from the losing edit.
    - Remote synchronization uses bounded keyset pagination so concurrent updates do not skip records. Attachment deletion rejects ambiguous names and filename-prefix collisions instead of deleting a different file.
    - Editing panels keep unsaved changes separate from stored records. Deleting or restoring from a panel saves its current edits and clears unnecessary save prompts; failed saves keep the draft available for correction.
    - Patient link generation and access changes no longer leave a false unsaved-changes warning or mark unrelated edits as saved. Failed link generation leaves the existing link unchanged.
    - Settings fields no longer reset the cursor while typing. Cancel restores the latest saved value, and incoming settings updates do not overwrite unfinished edits.
    - The speech-recognition language setting now stores language codes and converts older saved selections automatically. Selecting a lab suggestion correctly updates the appointment.
    - Welcome and release-note dialogs no longer depend on a slow update-server response, and release notes appear only once per app session. Update checks have a timeout.
    - Fixed login-form clearing, offline status reporting, first-launch welcome timing, and notification setup after switching clinics or signing in again.
    - Appointment reminders now open the calendar, and unavailable toolbar actions are properly disabled.
    - Fixed layout overflows in narrow navigation, account counts, settings, patient labels, appointment history and prescription tags. Emoji in names and appointment titles no longer cause rendering failures.
    - Calendar navigation retains its broad date range without fractional scrolling errors. Search fields expose a correctly sized accessibility target, and tooth-chart selection updates immediately after recording a condition.
    - Improved DICOM scan cancellation, retrying initialization, serialized approvals, progress reporting and patient matching. Canceling a scan preserves batches awaiting review rather than approving them automatically.
    - Attachment matching no longer confuses filename prefixes with file identities. File metadata work runs off the UI thread, and CSV imports handle final empty fields while rejecting incomplete quoted values.
    - Improved notification change detection, callback error handling and connection retries. AI tokens stay tied to the correct clinic and are cleared on logout; failed backups no longer leave the app stuck in a busy state.
    - Removed diagnostic logs containing transcription text, device tokens and notification payloads.
    - The DICOM import confirmation reads as a sentence again: it was showing a raw translation key instead of its title.
    - Open panels relabel their tabs when the language is switched, instead of keeping the labels they were opened with.

- Testing & Developer Experience
    - Expanded end-to-end coverage across the main clinic workflows, including attachments, AI services, notifications, clinic switching, offline synchronization and recovery.
    - Improved test fixtures, UI interactions and cleanup, with optional service tests kept separate from workflows that can run without those services.
    - Added focused regression tests for panel saving, patient validation, settings, calendar navigation, tag fields and test helpers.
    - Updated the end-to-end runners and VS Code tasks, consolidated the testing instructions, and removed the superseded test checklist.
    - Added the missing UI test keys and corrected duplicate keys so tests can reliably locate screens and controls. The key audit reports no missing handles.
    - Navigation uses typed routes instead of string identifiers, avoiding silent navigation failures and keeping the selected screen stable when permissions change.
    - Added the shared context-menu widget behind the new row menus, and a contract test asserting that each panel's tab strip and the context menu that opens it cannot drift apart, alongside a check that every tab title is a real translation key.

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

