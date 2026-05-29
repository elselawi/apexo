### [0.12.0]
fixed the flyoutFix and applied it more widely in the app
unified page scaffold into the main app screen so we don't have to define a screen widget safe inset for every page
barrierDismissable and dismissWithEsc for all applicable dialogs
fixed an issue with bottom navbar not displaying when the keyboard is open
screen titles are now clickable and open a dropdown for other screens
implemented dispose for all applicable controlleers across the app, less memory leaks, more stable, and performance improvements should be expected
redesinged most of app screen and panels for consistency in UI and UX
unified error message dialog
a dialog asking to login when the token suddenly becomes invalid while the app is open
changed the whole strategy of phone number handling and input to a wider text field that accepts any string then extracts phone numbers and turns them into clickable buttons at the same panel, auto validates, auto adds country code ..etc
re-design and complete overhaul of the patients page
made a utility function for date formatting that is reused across the app
unified the design of all command bars across all pages
unified the design of all search across all pages
unified the "show more" slicing button across all 
fixed inversed swipeDetector in RTL contexts
hide (not disable) the text box when the tag input (parent) is dsiabled
better CSV export (major overhaul)
implemented CSV import
share the globalSettings store into the modellingDocs isolate to get the country code
major overhaul and redsign of the accounts page
ability to taget specific tabs when opening panels (implemented on patients and appointments panels)
fixed a bug in dashboard controller displayed archived appointments even if we're hiding the archived
redesigned dashboard screen + clickable suppliers
major overhaul and redsign of the expenses and suppliers page
use GridGallery widget in orderRow
major redesign and overhaul in labworks screen
more semantic and better login screen
added 2 pixels spacing in network actions
fixed few permission issues in expenses page and notes page
faster patients page
removed country code from global settings and replaced it with auto-filled based on first IP visit ISOCountryCode
periodicity clickable toggle buttons in insights screen
better designed bar and radar charts
all charts are now better viewed on all platforms and screen sizes
initialize the settings store as the first store

### [0.11.0]
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

### [0.10.4]
- notifications and sounds for windows

### [0.10.3]
- fixed safari iOS notification error

### [0.10.1]
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

