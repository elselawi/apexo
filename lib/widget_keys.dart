import 'package:flutter/foundation.dart';

/// Widget keys used in the app
class WK {
  static const fluentApp = Key("fluentApp");
  static const builder = Key("builder");
  static const loginScreen = Key("loginScreen");
  static const dashboardScreen = Key("dashboardScreen");
  static const patientsScreen = Key("patientsScreen");
  static const calendarScreen = Key("calendarScreen");
  static const labworksScreen = Key("labworksScreen");
  static const settingsScreen = Key("settingsScreen");
  static const expensesScreen = Key("expensesScreen");
  static const notesScreen = Key("notesScreen");

  /// The accounts screen and its panel: the two create buttons, the fields, the
  /// enabled/disabled switch, and one handle per permission row.
  static const btnNewAccount = Key("btnNewAccount");
  static const btnNewAdmin = Key("btnNewAdmin");
  static const fieldAccountName = Key("fieldAccountName");
  static const fieldAccountEmail = Key("fieldAccountEmail");
  static const fieldAccountPassword = Key("fieldAccountPassword");
  static const accountOperates = Key("accountOperates");

  /// One permission row of the account panel, by the localization key of its
  /// title (`patients`, `calendar`, …) — the levels inside it are labelled.
  static Key permissionSelector(String titleKey) => Key("permission-$titleKey");

  /// One settings card, by the `identifier` the screen gives it (`currency`,
  /// `language`, `calendarSystem`, `dentalNotation`, …).
  static Key settingsItem(String identifier) => Key("settings-$identifier");

  /// The settings screen's own scrollable. The screen has a second one only when
  /// a pane or a panel is open, so a test that has to scroll to a section below
  /// the fold names this one instead of guessing at `.last`.
  static const settingsList = Key("settingsList");

  /// One section of the settings screen's **services** list (SMTP, S3, backups,
  /// file upload, meta, auth). They are anonymous `Expander`s, so a test
  /// addresses them by a stable id and reaches their controls as descendants.
  static Key serviceSection(String id) => Key("serviceSection-$id");

  /// One field inside a services section (`smtp_host`, `smtp_password`,
  /// `s3_endpoint`, `s3_secretKey`, `backups_maxKeep`, …).
  static Key serviceField(String id) => Key("serviceField-$id");

  /// One row of the backups list, by the backup's own key (its file name).
  static Key backupRow(String key) => Key("backupRow-$key");

  /// The notes board's entry points and its edit dialogs.
  ///
  /// The board itself needs no key: a column is a `KanbanColumn` and a card is
  /// a `NoteCard`, and both carry their record's id, so a test reaches them by
  /// their visible name (see `Fixtures.boardColumn` / `Fixtures.noteCard`).
  static const btnNewNote = Key("btnNewNote");
  static const btnAddColumn = Key("btnAddColumn");

  /// The board's horizontal scroll view.
  ///
  /// The columns live in a `Row` inside it, so a board with more than a few
  /// columns runs off the right edge and a tap on a later column lands outside
  /// the window — a test has to scroll this first (see
  /// `Fixtures.revealInBoard`).
  static const notesBoard = Key("notesBoard");

  /// A board column's root and its (tappable) header.
  ///
  /// Columns are keyed by their record id — the header carries the name, which
  /// is all a user sees, but a name is not unique enough for a finder to use
  /// while another widget on the board shows the same text.
  static Key columnRoot(String id) => Key("columnRoot-$id");
  static Key columnHeader(String id) => Key("columnHeader-$id");
  static const fieldNoteTitle = Key("fieldNoteTitle");
  static const fieldNoteText = Key("fieldNoteText");
  static const fieldColumnTitle = Key("fieldColumnTitle");

  /// The inline title and body fields of an *expanded* note card.
  ///
  /// The board renders one card per note, so these keys repeat — always look
  /// them up through the card (`Fixtures.noteCard(title)`), never bare.
  static const noteCardTitle = Key("noteCardTitle");
  static const noteCardNote = Key("noteCardNote");

  /// The buttons a card and a column header carry.
  ///
  /// These are the board's anonymous controls; a fluent `Tooltip` is its own
  /// widget (not the one `find.byTooltip` matches), so a key is the only
  /// reliable handle.
  static const btnAddNote = Key("btnAddNote");
  static const btnNoteTitleSave = Key("btnNoteTitleSave");
  static const btnNoteTextSave = Key("btnNoteTextSave");
  static const btnNoteDelete = Key("btnNoteDelete");

  static const serverField = Key("serverField");
  static const emailField = Key("emailField");
  static const passwordField = Key("passwordField");
  static const globalActions = Key("globalActions");

  /// One of the shell's global actions — the app bar's icons, by a stable id:
  /// `notifications` (the bell), `theme`, `sync`, `errors`.
  ///
  /// They are anonymous icons and a fluent `Tooltip` is not the widget
  /// `find.byTooltip` matches, so a key is the only way to reach one.
  static Key globalAction(String id) => Key("globalAction-$id");

  /// The phone layout's bottom navigation bar, one of its buttons, and the
  /// `More` button it falls back to when the bar cannot fit every route.
  static const bottomNav = Key("bottomNav");
  static const bottomNavMore = Key("bottomNavMore");
  static Key bottomNavButton(String identifier) =>
      Key("bottomNavButton-$identifier");

  static const backButton = Key("backButton");
  static const appLogo = Key("appLogo");
  static const currentAccountSection = Key("currentAccountSection");
  static const version = Key("version");
  static const loginLangComboBox = Key("loginLangComboBox");
  static const loginTab = Key("loginTab");
  static const forgotPasswordTab = Key("forgotPasswordTab");
  static const resetPasswordTab = Key("resetPasswordTab");
  static const btnResetPassword = Key("btnResetPassword");
  static const btnLogin = Key("btnLogin");
  static const btnProceedOffline = Key("btnProceedOffline");
  static const loginErr = Key("loginErr");
  static const btnLogout = Key("btnLogout");
  static const msgSentReset = Key("msgSentReset");
  static const msgWillSendReset = Key("msgWillSendReset");
  static const dataTableSearch = Key("dataTableSearch");
  static const dataTableSortBy = Key("dataTableSortBy");
  static const toggleSortDirection = Key("toggleSortDirection");
  static const closeModal = Key("closeModal");
  static const fieldDutyDays = Key("fieldDutyDays");
  static const fieldDoctorEmail = Key("fieldDoctorEmail");
  static const fieldDoctorName = Key("fieldDoctorName");
  static const fieldPatientName = Key("fieldPatientName");
  static const fieldPatientEmail = Key("fieldPatientEmail");
  static const fieldPatientPhone = Key("fieldPatientPhone");
  static const fieldPatientAddress = Key("fieldPatientAddress");
  static const fieldPatientGender = Key("fieldPatientGender");
  static const fieldPatientYOB = Key("fieldPatientAge");
  static const fieldPatientTags = Key("fieldPatientTags");
  static const fieldPatientNotes = Key("fieldPatientNotes");
  static const fieldOperators = Key("fieldOperators");
  static const fieldPatient = Key("fieldAppointmentPatient");
  static const fieldAppointmentDate = Key("fieldAppointmentDate");
  static const fieldAppointmentTime = Key("fieldAppointmentTime");
  static const fieldAppointmentPreOpNotes = Key("fieldAppointmentPreOpNotes");
  static const fieldAppointmentPostOpNotes = Key("fieldAppointmentPostOpNotes");
  static const fieldAppointmentPrescriptions =
      Key("fieldAppointmentPrescriptions");
  static const fieldAppointmentPrice = Key("fieldAppointmentPrice");
  static const fieldAppointmentPayment = Key("fieldAppointmentPayment");
  static const fieldLabworkAppointment = Key("fieldLabworkAppointment");
  static const fieldLabworkOrderNotes = Key("fieldLabworkOrderNotes");
  static const fieldLabworkLabName = Key("fieldLabworkLabName");
  static const fieldLabworkReceived = Key("fieldLabworkReceived");
  static const fieldReceiptTitle = Key("fieldReceiptTitle");
  static const fieldReceiptDate = Key("fieldReceiptDate");
  static const fieldReceiptNotes = Key("fieldReceiptNotes");
  static const fieldReceiptAmount = Key("fieldReceiptAmount");
  static const fieldReceiptPaidToggle = Key("fieldReceiptPaidToggle");
  static const fieldReceiptIssuer = Key("fieldReceiptIssuer");
  static const fieldReceiptTags = Key("fieldReceiptTags");
  static const fieldReceiptItems = Key("fieldReceiptItems");
  static const acCheckBox = Key("acCheckBox");
  static const acDate = Key("acDate");
  static const acSideIcons = Key("acSideIcons");
  static const calendarToday = Key("calendarToday");
  static const calendarSelected = Key("calendarSelected");
  static const calendarAppointmentTile = Key("calendarAppointmentTile");
  static const calendarDayButton = Key("calendarDayButton");

  /// The chip that says what a visit carries wherever it is listed — its
  /// dental notes, prescriptions, labwork and gallery — and the icon within it
  /// for one `AppointmentIndicator` kind.
  static const appointmentInfoBadges = Key("appointmentInfoBadges");

  static Key appointmentIndicator(String kind) =>
      Key("appointmentIndicator-$kind");

  /// The day cell for one date. The *selected* day carries [calendarSelected]
  /// instead, so a test can tap a cell by date and still ask what is selected.
  static Key calendarDay(DateTime day) =>
      Key("calendarDay-${day.year}-${day.month}-${day.day}");

  /// The badge with how many appointments a day has.
  ///
  /// `table_calendar` draws markers as a *sibling* of the day widget, so this
  /// is not a descendant of [calendarDay] — it needs a key of its own.
  static Key calendarDayCount(DateTime day) =>
      Key("calendarDayCount-${day.year}-${day.month}-${day.day}");

  /// One tooth of a teeth chart, by its ISO notation.
  ///
  /// The chart draws each tooth as an SVG path, so the key is the only way to
  /// reach one; `selected` says whether the tooth carries a condition, which is
  /// what a test asks after storing one.
  static Key tooth(String iso, {required bool selected}) =>
      Key("tooth-iso-$iso-${selected ? "selected" : "not-selected"}");

  /// The chrome every row panel shares.
  static const panelSave = Key("panelSave");
  static const panelClose = Key("panelClose");
  static const panelArchive = Key("panelArchive");
  static const panelMinimize = Key("panelMinimize");

  /// A panel's window: the pill that opens and puts it away, and the button on
  /// the window itself that minimizes it.
  static Key windowToggle(String id) => Key("windowToggle-$id");
  static Key windowMinimize(String id) => Key("windowMinimize-$id");

  /// The Save/Close a window standing on its own carries, and the close button
  /// its sheet gets on a phone.
  static const windowSave = Key("windowSave");
  static const windowClose = Key("windowClose");

  /// The Save a panel window carries in its own footer, where the draft it edits
  /// is also the panel's.
  static Key windowSaveFooter(String id) => Key("windowSaveFooter-$id");

  /// The Close a standalone window carries in its header, where a panel's window
  /// has its minimize.
  static const windowHeaderClose = Key("windowHeaderClose");

  /// The header button that leaves a standalone window for the panel holding
  /// its record.
  static const windowOpenRecord = Key("windowOpenRecord");

  /// The dot beside a window's title, and above the record's kind in a panel's
  /// header, while the work in it has not been stored.
  static const unsavedDot = Key("unsavedDot");

  /// The command that puts every panel and every floating window away — out
  /// only while there is something to close and nothing unsaved.
  static const closeAllWindows = Key("closeAllWindows");

  /// List screens (patients, labworks, expenses, accounts, archived).
  static const listSearch = Key("listSearch");
  static const showMore = Key("showMore");

  static const btnNewPatient = Key("btnNewPatient");
  static const btnNewAppointment = Key("btnNewAppointment");
  static const btnNewLabwork = Key("btnNewLabwork");

  /// One of the dashboard's squares, and the number (or amount) it shows.
  ///
  /// The square's own labels are localized and the widgets are anonymous, so
  /// tests address them by a stable id (`appointmentsToday`, `paymentsToday`,
  /// `labworksDue`, `expensesDue`, …).
  static Key dashboardSquare(String id) => Key("dashboardSquare-$id");
  static Key dashboardCount(String id) => Key("dashboardCount-$id");

  /// Expenses: the panel's "add order" button, and one order row's editable
  /// money fields (the row labels them "due" and "paid") plus its overflow menu.
  static const btnAddOrder = Key("btnAddOrder");
  static const fieldOrderCost = Key("fieldOrderCost");
  static const fieldOrderPaid = Key("fieldOrderPaid");
  static const orderMenu = Key("orderMenu");

  /// The supplier panel's own body: the rename button beside the name, and the
  /// figures it leads with.
  static const editSupplierName = Key("editSupplierName");
  static const expenseSummaryDue = Key("expenseSummaryDue");
  static const expenseSummaryPaid = Key("expenseSummaryPaid");

  /// The expenses screen's primary action (it opens the supplier dialog).
  static const btnNewSupplier = Key("btnNewSupplier");

  /// The appointment's labwork: the "add labwork for this appointment" link, and
  /// the delete inside the order itself.
  static const btnAddLabwork = Key("btnAddLabwork");

  /// The X-ray link (DICOM) screen.
  ///
  /// The screen had no keys at all: everything a test needed to reach — the
  /// scan button, the auto-import switch, a pending import's own buttons — was
  /// anonymous, so a test would have had to read the English copy. The pending
  /// card is keyed by the record key it was built from (`DicomPendingImport.key`).
  static const dicomScreen = Key("dicomScreen");
  static const dicomScanButton = Key("dicomScanButton");
  static const dicomAutoImportToggle = Key("dicomAutoImportToggle");
  static const dicomApprove = Key("dicomApprove");
  static const dicomChangeMatch = Key("dicomChangeMatch");
  static Key dicomPendingCard(String key) => Key("dicomPendingCard-$key");
}
