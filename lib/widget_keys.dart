import 'package:flutter/foundation.dart';

/// Widget keys used in the app
class WK {
  static const fluentApp = Key("fluentApp");
  static const builder = Key("builder");
  static const loginScreen = Key("loginScreen");
  static const dashboardScreen = Key("dashboardScreen");
  static const bookingScreen = Key("bookingScreen");
  static const patientsScreen = Key("patientsScreen");
  static const calendarScreen = Key("calendarScreen");
  static const labworksScreen = Key("labworksScreen");
  static const settingsScreen = Key("settingsScreen");
  static const expensesScreen = Key("expensesScreen");
  static const notesScreen = Key("notesScreen");

  static const btnNewAccount = Key("btnNewAccount");
  static const btnNewAdmin = Key("btnNewAdmin");
  static const fieldAccountName = Key("fieldAccountName");
  static const fieldAccountEmail = Key("fieldAccountEmail");
  static const fieldAccountPassword = Key("fieldAccountPassword");
  static const accountOperates = Key("accountOperates");

  /// One permission row, by the localization key of its title (e.g. `patients`).
  static Key permissionSelector(String titleKey) => Key("permission-$titleKey");

  static Key settingsItem(String identifier) => Key("settings-$identifier");

  static const settingsList = Key("settingsList");

  static Key serviceSection(String id) => Key("serviceSection-$id");

  static Key serviceField(String id) => Key("serviceField-$id");

  /// One row of the backups list, by the backup's own key (its file name).
  static Key backupRow(String key) => Key("backupRow-$key");

  /// The board's entry points; the board itself needs no key — its columns and
  /// cards carry their record ids.
  static const btnNewNote = Key("btnNewNote");
  static const btnAddColumn = Key("btnAddColumn");

  /// The board's horizontal scroll view; a later column is laid out past the
  /// right edge of the window, so a tap has to scroll it into view first.
  static const notesBoard = Key("notesBoard");

  /// A column's root and tappable header, keyed by record id because the visible
  /// name is not unique enough for a finder to use.
  static Key columnRoot(String id) => Key("columnRoot-$id");
  static Key columnHeader(String id) => Key("columnHeader-$id");
  static const fieldNoteTitle = Key("fieldNoteTitle");
  static const fieldNoteText = Key("fieldNoteText");
  static const fieldColumnTitle = Key("fieldColumnTitle");

  /// An expanded card's title and body fields; one card per note means these
  /// keys repeat, so look them up through the card, never bare.
  static const noteCardTitle = Key("noteCardTitle");
  static const noteCardNote = Key("noteCardNote");

  /// A card or column-header control; these are anonymous and a fluent `Tooltip`
  /// is not what `find.byTooltip` matches, so the key is the only handle.
  static const btnAddNote = Key("btnAddNote");
  static const btnNoteTitleSave = Key("btnNoteTitleSave");
  static const btnNoteTextSave = Key("btnNoteTextSave");
  static const btnNoteDelete = Key("btnNoteDelete");

  static const serverField = Key("serverField");
  static const emailField = Key("emailField");
  static const passwordField = Key("passwordField");
  static const globalActions = Key("globalActions");

  /// One shell action, by stable id; the icons are anonymous and a fluent
  /// `Tooltip` is not what `find.byTooltip` matches.
  static Key globalAction(String id) => Key("globalAction-$id");

  static const bottomNav = Key("bottomNav");
  static const bottomNavMore = Key("bottomNavMore");
  static Key bottomNavButton(String identifier) =>
      Key("bottomNavButton-$identifier");

  /// The count/amount pill a nav destination shows beside its label.
  static Key navBadge(String identifier) => Key("navBadge-$identifier");

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

  static const fieldAppointmentFollowUp = Key("fieldAppointmentFollowUp");
  static const fieldAppointmentFollowUpDate =
      Key("fieldAppointmentFollowUpDate");

  /// The day's row: the day itself and what the visit is for.
  static const fieldFollowUpNote = Key("fieldFollowUpNote");

  static const followUpSave = Key("followUpSave");
  static const followUpCancel = Key("followUpCancel");

  static const followUpCollapse = Key("followUpCollapse");
  static const clearFollowUp = Key("clearFollowUp");
  static Key followUpPreset(String label) => Key("followUpPreset-$label");

  static const chartFollowUpDot = Key("chartFollowUpDot");
  static const bookFollowUp = Key("bookFollowUp");
  static const followUpBand = Key("followUpBand");
  static Key followUpAvatar(String patientID) =>
      Key("followUpAvatar-$patientID");

  /// A patient's row in the day's unfolded follow-up sheet.
  static Key followUpRow(String patientID) => Key("followUpRow-$patientID");

  static const followUpRemove = Key("followUpRemove");

  /// The day's follow-up band as a sheet: the band's own handle that unfolds it.
  static const followUpsBandToggle = Key("followUpsBandToggle");
  static const followUpsOverdueDivider = Key("followUpsOverdueDivider");

  /// The day's names, numbers and notes, as text the clinic can select or copy.
  static const followUpsCopyContacts = Key("followUpsCopyContacts");
  static const followUpContactsText = Key("followUpContactsText");

  static const patientFollowUpBar = Key("patientFollowUpBar");
  static const patientFollowUpSet = Key("patientFollowUpSet");

  static const followUpSummaryCard = Key("followUpSummaryCard");
  static const followUpSummarySet = Key("followUpSummarySet");
  static const followUpPatientLink = Key("followUpPatientLink");

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

  static const appointmentInfoBadges = Key("appointmentInfoBadges");

  static Key appointmentIndicator(String kind) =>
      Key("appointmentIndicator-$kind");

  /// The day cell for one date; the selected day carries [calendarSelected]
  /// instead, so a test can tap a cell by date and still ask what is selected.
  static Key calendarDay(DateTime day) =>
      Key("calendarDay-${day.year}-${day.month}-${day.day}");

  /// The day's count badge; `table_calendar` draws markers as a sibling of the
  /// day, so it cannot be found through [calendarDay].
  static Key calendarDayCount(DateTime day) =>
      Key("calendarDayCount-${day.year}-${day.month}-${day.day}");

  /// One tooth, by ISO notation; teeth are anonymous SVG paths, so the key is
  /// the only handle. `selected` says whether the tooth carries a condition.
  static Key tooth(String iso, {required bool selected}) =>
      Key("tooth-iso-$iso-${selected ? "selected" : "not-selected"}");

  /// The chrome every row panel shares.
  static const panelSave = Key("panelSave");
  static const panelClose = Key("panelClose");
  static const panelArchive = Key("panelArchive");
  static const panelMinimize = Key("panelMinimize");

  static Key windowToggle(String id) => Key("windowToggle-$id");

  static const visitBand = Key("visitBand");

  /// The band's tail, drawn under the card it hangs from.
  static const visitBandTail = Key("visitBandTail");

  /// The record's own compact editor, inside the band.
  static const visitContent = Key("visitContent");
  static const visitState = Key("visitState");
  static const visitSave = Key("visitSave");
  static const visitDetach = Key("visitDetach");
  static const visitMarkedCompleted = Key("visitMarkedCompleted");
  static const visitUnsavedCount = Key("visitUnsavedCount");

  /// The band footer's "move to the visit that still has unsaved work" action.
  static const visitMoveToVisit = Key("visitMoveToVisit");

  static const patientReadOnly = Key("patientReadOnly");

  /// The band footer's archive/restore action; close is [visitDetach].
  static const visitDelete = Key("visitDelete");

  /// The one tool in the visit band's dock: operative details.
  static Key visitBandWindow(String id) => Key("visitBandWindow-$id");

  static const visitBandAttachments = Key("visitBandAttachments");
  static const visitChartAttachments = Key("visitChartAttachments");

  /// The visit scope bar's "new visit" button — beside the visits it joins.
  static const chartAddAppointment = Key("chartAddAppointment");

  /// One attachment chip; [owner] names the frame it is drawn on, since a visit
  /// and its patient both offer a `gallery`.
  static Key attachmentToggle(String id, {String? owner}) => Key(
        owner == null ? "attachmentToggle-$id" : "attachmentToggle-$owner-$id",
      );

  static Key workspaceWindowToggle(String id) =>
      Key("workspaceWindowToggle-$id");

  static const windowSave = Key("windowSave");
  static const windowClose = Key("windowClose");

  static Key windowSaveFooter(String id) => Key("windowSaveFooter-$id");

  static const windowHeaderClose = Key("windowHeaderClose");

  static const windowOpenRecord = Key("windowOpenRecord");

  static const unsavedDot = Key("unsavedDot");

  static const closeAllWindows = Key("closeAllWindows");

  /// List screens (patients, labworks, expenses, accounts, archived).
  static const listSearch = Key("listSearch");
  static const showMore = Key("showMore");

  static const btnNewPatient = Key("btnNewPatient");
  static const btnNewAppointment = Key("btnNewAppointment");
  static const btnNewLabwork = Key("btnNewLabwork");

  /// The create sheets: fields first, then the record — no draft is opened for
  /// them to fill in.
  static const fieldNewPatientName = Key("fieldNewPatientName");
  static const fieldNewPatientPhone = Key("fieldNewPatientPhone");
  static const btnCreatePatient = Key("btnCreatePatient");
  static const fieldNewAppointmentPatient = Key("fieldNewAppointmentPatient");
  static const fieldNewAppointmentDate = Key("fieldNewAppointmentDate");
  static const fieldNewAppointmentTime = Key("fieldNewAppointmentTime");
  static const fieldNewAppointmentNotes = Key("fieldNewAppointmentNotes");
  static const btnCreateAppointment = Key("btnCreateAppointment");

  /// One dashboard square and its count, by stable id; the visible labels are
  /// localized.
  static Key dashboardSquare(String id) => Key("dashboardSquare-$id");
  static Key dashboardCount(String id) => Key("dashboardCount-$id");

  static const btnAddOrder = Key("btnAddOrder");
  static const fieldOrderCost = Key("fieldOrderCost");
  static const fieldOrderPaid = Key("fieldOrderPaid");
  static const orderMenu = Key("orderMenu");

  static const editSupplierName = Key("editSupplierName");
  static const expenseSummaryDue = Key("expenseSummaryDue");
  static const expenseSummaryPaid = Key("expenseSummaryPaid");

  /// The expenses screen's primary action (it opens the supplier dialog).
  static const btnNewSupplier = Key("btnNewSupplier");

  static const btnAddLabwork = Key("btnAddLabwork");
  static const btnRemoveLabwork = Key("btnRemoveLabwork");

  /// Delete for a visit standing on its own (no band) and from its chart footer;
  /// the band's is [visitDelete].
  static const operativeDeleteVisit = Key("operativeDeleteVisit");
  static const chartDeleteVisit = Key("chartDeleteVisit");

  /// The X-ray link (DICOM) screen; a pending card is keyed by its
  /// `DicomPendingImport.selectionKey`.
  static const dicomScreen = Key("dicomScreen");
  static const dicomScanButton = Key("dicomScanButton");
  static const dicomAutoImportToggle = Key("dicomAutoImportToggle");
  static const dicomApprove = Key("dicomApprove");
  static const dicomChangeMatch = Key("dicomChangeMatch");
  static Key dicomPendingCard(String key) => Key("dicomPendingCard-$key");
}
