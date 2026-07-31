### ____0.14.0____

- New Features & Enhancements
    - **DICOM / RVG X-Ray Import (Windows)**: One-click workflow to import X-rays from RVG sensors. Configure watch folders once, then Apexo scans for new `.dcm` files every 90 seconds. Smart matching suggests which patient each X-ray belongs to based on embedded metadata. Once a DICOM patient ID is linked, future X-rays auto-import without manual steps. Includes a full cross-platform interactive viewer with windowing, rotation, color-map presets, invert, and measurement tools (ROI statistics, ruler in mm). Imported X-rays sync to all devices via PocketBase.

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

