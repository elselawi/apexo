import 'en.dart';

class El implements En {
  @override
  Direction $direction = Direction.ltr;
  @override
  String $name = "Ελληνικά";
  @override
  String $code = "el";

  @override
  Map<String, String> dictionary = {
    // common
    "cancel": "Άκυρο",
    "close": "Κλείσιμο",
    "save": "Αποθήκευση",
    "reset": "Επαναφορά",
    "continue": "Συνέχεια",
    "add": "Προσθήκη",
    "edit": "Επεξεργασία",
    "delete": "Σβήσε",
    "deletedItems": "Διαγραμμένα",
    "deleted": "Διαγράφηκε",
    "archive": "Αρχειοθέτηση",
    "restore": "Επαναφορά",
    "logout": "Αποσύνδεση",
    "VoiceInput": "Φωνητική εισαγωγή",
    "noResultsFound": "Δεν βρέθηκαν αποτελέσματα",
    "startTyping": "Ξεκινήστε να πληκτρολογείτε",
    "home": "Αρχική",
    "calendar": "Ημερολόγιο",
    "gettingImages": "Λήψη εικόνων",
    "more": "Περισσότερα",
    "howToUse": "Οδηγίες χρήσης",

    // new
    "newPatient": "Νέος ασθενής",
    "newAppointment": "Νέο ραντεβού",
    "newLabwork": "Νέα εργαστηριακή εργασία",
    "newNote": "Νέα σημείωση",
    "newUser": "Νέος χρήστης",
    "newAdmin": "Νέος διαχειριστής",

    // screens
    "settings": "Ρυθμίσεις",
    "dashboard": "Πίνακας ελέγχου",
    "appointments": "Ραντεβού",
    "patients": "Ασθενείς",
    "doctors": "Ιατροί",
    "labworks": "Εργαστηριακές εργασίες",
    "insights": "Στατιστικά",

    // dashboard
    "admin": "Διαχειριστής",
    "payments": "Πληρωμές",
    "appointmentsToday": "Ραντεβού σήμερα",
    "patientsToday": "Ασθενείς σήμερα",
    "newPatientsToday": "Νέοι ασθενείς σήμερα",
    "paymentsMadeToday": "Πληρωμές σήμερα",
    "modeAdmin": "λειτουργία διαχειριστή",
    "modeUser": "λειτουργία χρήστη",
    "modeOffline": "λειτουργία εκτός σύνδεσης",
    "onceConnectionIsStable":
        "Μόλις η σύνδεσή σας σταθεροποιηθεί, μπορείτε να χρησιμοποιήσετε το κουμπί στην επάνω δεξιά γωνία για επανασύνδεση.",
    "unRestrictedAccess": "απεριόριστη πρόσβαση στην εφαρμογή",
    "restrictedAccess":
        "περιορισμένη πρόσβαση σε ορισμένες οθόνες, όπως ορίζεται από τον διαχειριστή",
    "youAreCurrentlyIn": "Βρίσκεστε αυτή τη στιγμή σε",
    "mode": "λειτουργία",
    "youHave": "Έχετε",
    "hello": "Γεια σας",

    // datatable
    "archiveSelected": "Αρχειοθέτηση επιλεγμένων",
    "searchPlaceholder": "Αναζήτηση...",
    "showHideArchived": "Εμφάνιση/Απόκρυψη αρχειοθετημένων",
    "showing": "Εμφάνιση",
    "showMore": "Εμφάνιση περισσότερων",
    "by": "Κατά",
    "byName": "Κατά όνομα",
    "noItemsFound": "Δεν βρέθηκαν στοιχεία",
    "filter": "Φίλτρο",

    // doctors
    "doctor": "Ιατρός",
    "pastAppointments": "Προηγούμενα ραντεβού",
    "upcomingAppointments": "Επερχόμενα ραντεβού",
    "viewAllAppointments": "Προβολή όλων των ραντεβού",
    "otherAppointments": "Άλλα ραντεβού",
    "addAppointment": "Προσθήκη ραντεβού",

    // days and months
    "monday": "Δευτέρα",
    "tuesday": "Τρίτη",
    "wednesday": "Τετάρτη",
    "thursday": "Πέμπτη",
    "friday": "Παρασκευή",
    "saturday": "Σάββατο",
    "sunday": "Κυριακή",

    // appointment card
    "appointment": "Ραντεβού",
    "patient": "Ασθενής",
    "photos": "Φωτογραφίες",
    "pre-opNotes": "Προεγχειρητικές σημειώσεις",
    "post-opNotes": "Μετεγχειρητικές σημειώσεις",
    "prescription": "Συνταγή",
    "pay": "Πληρωμή",
    "paid": "Πληρώθηκε",
    "price": "Τιμή",
    "underpaid": "Ανεξόφλητο",
    "overpaid": "Υπερπληρωμένο",
    "fullyPaid": "Εξοφλημένο",
    "includesOtherAppointments":
        "Αυτό το σύνολο περιλαμβάνει και πληρωμές από άλλα ραντεβού.",
    "paymentSummary": "Σύνοψη πληρωμών",
    "after": "Μετά από",
    "days": "ημέρες",
    "day": "ημέρα",
    "isDone": "Το ραντεβού ολοκληρώθηκε",
    "addLabwork": "Προσθήκη εργαστηριακής εργασίας για αυτό το ραντεβού",
    "labworksForThisAppointment": "Εργαστηριακές εργασίες για αυτό το ραντεβού",

    // patients
    "patientDetails": "Στοιχεία ασθενή",
    "age": "Ηλικία",
    "gender": "Φύλο",
    "lastVisit": "Τελευταία επίσκεψη",
    "nextVisit": "Επόμενη επίσκεψη",
    "totalPayments": "Σύνολο πληρωμών",
    "daysAgo": "ημέρες πριν",
    "noVisits": "Καμία επίσκεψη",
    "name": "Όνομα",
    "birthYear": "Έτος γέννησης",
    "phone": "Τηλέφωνο",
    "noValidNumbersFound": "Δεν βρέθηκαν έγκυροι αριθμοί τηλεφώνου",
    "theFollowingPhoneNumbersAreDetected":
        "Εντοπίστηκαν μόνο οι παρακάτω αριθμοί τηλεφώνου",
    "email": "Email",
    "address": "Διεύθυνση",
    "notes": "Σημειώσεις",
    "patientTags": "Ετικέτες ασθενή",
    "male": "Άνδρας",
    "female": "Γυναίκα",
    "noAppointmentsFound":
        "Δεν βρέθηκαν ραντεβού για αυτόν τον ασθενή. Χρησιμοποιήστε το παρακάτω κουμπί για να προσθέσετε νέο ραντεβού.",
    "patientPage": "Ιστοσελίδα ασθενή",
    "patientCanUseTheFollowing":
        "Ο ασθενής μπορεί να χρησιμοποιήσει τον παρακάτω σύνδεσμο για να δει τα ραντεβού, τις πληρωμές και τις φωτογραφίες του.",
    "web": "Web",
    "telegram": "Telegram",
    "printQR": "Εκτύπωση κωδικού QR",
    "dentalNotes": "Οδοντιατρικές σημειώσεις",
    "showPrimary": "Εμφάνιση νεογιλών",
    "showPermanent": "Εμφάνιση μόνιμων",
    "primary": "Νεογιλά",
    "permanent": "Μόνιμα",
    "lower": "Káτω",
    "upper": "Άνω",
    "left": "Αριστερά",
    "right": "Δεξιά",
    "centralIncisor": "Κεντρικός τομέας",
    "lateralIncisor": "Πλάγιος τομέας",
    "canine": "Κυνόδοντας",
    "firstPremolar": "Πρώτος προγόμφιος",
    "secondPremolar": "Δεύτερος προγόμφιος",
    "firstMolar": "Πρώτος γομφίος",
    "secondMolar": "Δεύτερος γομφίος",
    "thirdMolar": "Τρίτος γομφίος",
    "exportSelected": "Εξαγωγή επιλεγμένων",
    "export": "Εξαγωγή",
    "exportImportFeatureExplanation":
        "Για να μεταφέρετε δεδομένα ασθενών και ραντεβού μεταξύ servers ή άλλων εφαρμογών, εξάγετε ένα CSV από τον server προέλευσης και εισάγετέ το στον server ή την εφαρμογή προορισμού.",
    "qrCode": "Κωδικός QR",
    "share": "Κοινοποίηση",

    // communication
    "contact": "Επικοινωνία",
    "sendEmail": "Αποστολή email",
    "whatsapp": "WhatsApp",
    "call": "Κλήση",
    "text": "Μήνυμα",
    "countryCode": "Κωδικός χώρας",
    "countryCode_desc":
        "Επιλέξτε τον προεπιλεγμένο κωδικό χώρας για κλήσεις ή αποστολή μηνυμάτων",

    // treatments
    "treatment": "Θεραπεία",
    "allTreatments": "Όλες οι θεραπείες",
    "extraction": "Εξαγωγή",
    "filling": "Σφράγισμα",
    "pulpotomy": "Πολφοτομή",
    "rCT": "Απονεύρωση",
    "other": "Άλλο",
    "re-RCT": "Επαναπονεύρωση",
    "ortho": "Ορθοδοντική",
    "whitening": "Λεύκανση",
    "clean": "Καθαρισμός",
    "implant": "Εμφύτευμα",
    "surgery": "Χειρουργείο",
    "crown": "Στεφάνη",
    "veneer": "Όψη",
    "bridge": "Γέφυρα",
    "overlay": "Επένθετο",
    "temporary": "Προσωρινό",
    "tap the treatment you have performed to register it to the tooth":
        "Πατήστε τη θεραπεία που εκτελέσατε για να την καταχωρίσετε στο δόντι",
    "tap the condition or history of the tooth to register it":
        "Πατήστε την κατάσταση ή το ιστορικό του δοντιού για να το καταχωρίσετε",
    "missing": "Απόν",
    "caries": "Τερηδόνα",
    "fractured": "Κάταγμα",
    "mobility": "Κινητικότητα",
    "recession": "Ύφεση ούλων",
    "rroot": "Υπολ. ρίζα",
    "rprimary": "Υπολ. νεογιλό",
    "malposition": "Δυσθέση",
    "impacted": "Έγκλειστο",
    "abutment": "Στήριγμα",
    "pontic": "Ενδιάμεσο",

    // calendar (appointments)
    "allDoctors": "Όλοι οι ιατροί",
    "noAppointmentsForThisDay": "Δεν υπάρχουν ραντεβού για αυτή την ημέρα",
    "weekAbbr": "Ε",
    "twoWeeksAbbr": "2Ε",
    "monthAbbr": "Μ",
    "today": "Σήμερα",
    "date": "Ημερομηνία",
    "changeDate": "Αλλαγή ημερομηνίας",
    "changeTime": "Αλλαγή ώρας",
    "time": "Ώρα",
    "preOperativeNotes": "Προεγχειρητικές σημειώσεις",
    "selectDoctors": "Επιλογή ιατρών",
    "selectPatient": "Επιλογή ασθενή",
    "operativeDetails": "Λεπτομέρειες επέμβασης",
    "postOperativeNotes": "Μετεγχειρητικές σημειώσεις",
    "extraInfoPlaceholder": "Επιπλέον πληροφορίες",
    "extraNotesFromAppointments": "Επιπλέον σημειώσεις από ραντεβού:",
    "otherAppointmentsNotes": "Σημειώσεις άλλων ραντεβού:",
    "printPrescription": "Εκτύπωση συνταγής",
    "priceIn": "Τιμή σε",
    "paidIn": "Πληρωμή σε",
    "gallery": "Συλλογή",
    "link": "Σύνδεσμος",
    "upload": "Μεταφόρτωση",
    "camera": "Κάμερα",
    "emptyGallery": "Άδεια συλλογή",
    "noPhotos": "Δεν έχουν μεταφορτωθεί φωτογραφίες ακόμη.",
    "otherPhotos": "Φωτογραφίες από άλλα ραντεβού",
    "draw": "Σχεδίαση",
    "erase": "Διαγραφή",
    "showDrawings": "Εμφάνιση σχεδίων",
    "importingPhotosFromLink": "Εισαγωγή φωτογραφιών από σύνδεσμο",
    "useThisForm":
        "Χρησιμοποιήστε αυτή τη φόρμα για εισαγωγή φωτογραφιών από συνδέσμους κοινοποίησης, όπως Google Photos, ή οποιαδήποτε προσβάσιμη ιστοσελίδα που περιέχει φωτογραφίες που θέλετε να προσθέσετε σε αυτό το ραντεβού.",
    "error": "Σφάλμα",
    "enterLink": "Εισαγάγετε ένα URL που περιέχει φωτογραφίες",
    "import": "Εισαγωγή",

    // labworks
    "laboratory": "Εργαστήριο",
    "month": "μήνας",
    "labwork": "εργασία",
    "orderNotes": "Σημειώσεις παραγγελίας",
    "noSuggestions": "Καμία πρόταση",
    "received": "Η εργασία παραλήφθηκε",
    "showDone": "Εμφάνιση ολοκληρωμένων",
    "waitingForLab": "αναμονή εργαστηρίου",
    "undelivered": "Μη παραδοθέν στον ασθενή",
    "receivedAndDelivered": "Παραλήφθηκε και παραδόθηκε",
    "selectPatientFirst": "Επιλέξτε πρώτα έναν ασθενή",
    "patientHasNoAppointments": "Ο ασθενής δεν έχει ραντεβού",
    "selectAppointment": "Επιλέξτε ένα ραντεβού",
    "areYouSureYouWantTo": "Είστε σίγουροι ότι θέλετε να",
    "youCanRestoreFromDeletedItemsPage":
        "Μπορείτε να το επαναφέρετε από τη σελίδα διαγραμμένων",
    "youWillNotBeAbleToRestore": "Δεν θα μπορείτε να το επαναφέρετε",

    // expenses
    "expense": "Έξοδο",
    "expenses": "Έξοδα",
    "receipt": "Απόδειξη",
    "title": "Τίτλος",
    "cost": "Kόστος",
    "amount": "Ποσό",
    "status": "Κατάσταση",
    "due": "Οφειλόμενο",
    "open": "Άνοιγμα",
    "rename": "Μετονομασία",
    "addSupplier": "Προσθήκη προμηθευτή",
    "items": "Είδη",
    "markAsPaid": "Σήμανση ως πληρωμένο",
    "markAsDue": "Σήμανση ως οφειλόμενο",
    "addOrder": "Προσθήκη παραγγελίας",
    "new": "Νέο",
    "thisMonth": "Αυτόν τον μήνα",
    "addPhoto": "Προσθήκη φωτογραφίας",
    "change": "Αλλαγή",
    "empty": "Κενό",
    "totalDue": "Σύνολο οφειλόμενων",
    "notSet": "Μη ορισμένο",
    "photo": "Φωτογραφία",
    "viewAllOrders": "Προβολή όλων των παραγγελιών",
    "lastOrder": "Τελευταία παραγγελία",
    "supplier": "Προμηθευτής",
    "order": "Παραγγελία",
    "orders": "Παραγγελίες",

    // notes
    "addColumn": "Προσθήκη στήλης",
    "editColumn": "Επεξεργασία στήλης",
    "columnTitle": "Τίτλος στήλης",
    "columnColor": "Χρώμα στήλης",
    "addNote": "Προσθήκη σημείωσης",
    "editNote": "Επεξεργασία σημείωσης",
    "note": "Σημείωση",
    "recurrence": "Επανάληψη",
    "isARecurrenceOfOlderNote": "Είναι επανάληψη παλαιότερης σημείωσης",
    "recurringEvery": "Επαναλαμβάνεται κάθε",
    "recurring": "Επαναλαμβανόμενο",
    "column": "Στήλη",
    "uncategorized": "Χωρίς κατηγορία",
    "relatingToPatient": "Σχετίζεται με ασθενή",
    "assignedTo": "Ανατέθηκε σε",
    "dueDate": "Ημερομηνία λήξης",
    "attachments": "Συνημμένα",
    "deleteAllCompletedNotes": "Διαγραφή όλων των ολοκληρωμένων σημειώσεων",
    "moveTowardsEnd": "Μετακίνηση προς το τέλος",
    "moveTowardsStart": "Μετακίνηση προς την αρχή",
    "item": "Στοιχείο",
    "addAttachment": "Προσθήκη συνημμένου",
    "tapToDownload": "Πατήστε για λήψη",
    "addComment": "Προσθήκη σχολίου",
    "sendComment": "Αποστολή σχολίου",
    "tapToMarkAsPending": "Πατήστε για σήμανση ως εκκρεμές",
    "tapToMarkAsDone": "Πατήστε για σήμανση ως ολοκληρωμένο",
    "archived": "Αρχειοθετημένο",
    "noDeletedItems": "Δεν υπάρχουν διαγραμμένα στοιχεία",
    "overdue": "Εκπρόθεσμο",
    "incoming": "Εισερχόμενα",
    "outgoing": "Εξερχόμενα",
    "pending": "Εκκρεμές",
    "completed": "Ολοκληρωμένο",
    "unassigned": "Μη ανατεθειμένο",
    "comments": "Σχόλια",
    "createdDate": "Ημερομηνία δημιουργίας",
    "changeDueDate": "Αλλαγή ημερομηνίας λήξης",
    "createdBy": "Δημιουργήθηκε από",
    "switchAssignee": "Αλλαγή ανάθεσης",
    "noAssignee": "Χωρίς ανάθεση",
    "sort": "Ταξινόμηση",
    "ascending": "αύξουσα",
    "descending": "φθίνουσα",
    "showAll": "Εμφάνιση όλων",
    "allAccounts": "Όλοι οι λογαριασμοί",

    // stats
    "pickRange": "Επιλογή εύρους",
    "start": "Έναρξη",
    "end": "Λήξη",
    "weeks": "Εβδομάδες",
    "months": "Μήνες",
    "quarters": "Τρίμηνα",
    "years": "Έτη",
    "year": "Έτος",
    "appointmentsPer": "Ραντεβού ανά",
    "paymentsAndExpensesPer": "Πληρωμές και έξοδα ανά",
    "newPatientsPer": "Νέοι ασθενείς ανά",
    "doneMissedPer": "Ολοκληρωμένα & Χαμένα ανά",
    "timeOfDay": "Ώρα ημέρας",
    "dayOfWeek": "Ημέρα εβδομάδας",
    "dayOfMonth": "Ημέρα μήνα",
    "monthOfYear": "Μήνας έτους",
    "patientsGender": "Φύλο ασθενών",
    "total": "Σύνολο",
    "in_Duration_": "σε",
    "acquiredPatientsIn": "Νέοι ασθενείς σε",
    "doneAndMissedAppointmentsIn": "Ολοκληρωμένα και χαμένα ραντεβού σε",
    "distributionOfAppointments": "Κατανομή ραντεβού",
    "maleAndFemalePatients": "Άνδρες και γυναίκες ασθενείς",
    "done": "ολοκληρωμένα",
    "missed": "χαμένα",
    "periodicity": "Περιοδικότητα",

    // settings
    "currency": "Νόμισμα",
    "currency_desc":
        "Κωδικός νομίσματος που θα χρησιμοποιείται σε όλη την εφαρμογή (π.χ. EUR, USD).",
    "phone_desc":
        "Ο αριθμός τηλεφώνου θα εμφανίζεται στις εκτυπώσεις και στην ιστοσελίδα των ασθενών.",
    "prescriptionFooter": "Υποσέλιδο συνταγής",
    "prescriptionFooter_desc":
        "Αυτό το κείμενο θα εμφανίζεται στο κάτω μέρος της συνταγής.",
    "language": "Γλώσσα",
    "language_desc":
        "Η γλώσσα διεπαφής για τα μενού, τα κουμπιά και τις πληροφορίες σε όλη την εφαρμογή.",
    "startingDayOfWeek": "Πρώτη ημέρα της εβδομάδας",
    "startingDayOfWeek_desc": "Η ημέρα από την οποία ξεκινά η εβδομάδα.",
    "dateFormat": "Μορφή ημερομηνίας",
    "dateFormat_desc":
        "Αυτή η μορφή θα χρησιμοποιείται για την εμφάνιση ημερομηνιών όπου ισχύει.",
    "cacheReset": "Επαναφορά προσωρινής μνήμης",
    "cacheReset_desc":
        "Με το παρακάτω κουμπί μπορείτε να διαγράψετε τα τοπικά αποθηκευμένα δεδομένα (εκτός από τις εικόνες). Αυτό μπορεί να λύσει προβλήματα συγχρονισμού αν αντιμετωπίζετε κάποιο.",
    "month/day/year": "Μήνας/Ημέρα/Έτος",
    "day/month/year": "Ημέρα/Μήνας/Έτος",
    "appliesTo": "Ισχύει για",
    "all": "Όλα",
    "you": "εσάς",
    "system": "σύστημα",
    "initialSynchronization": "Αρχικός συγχρονισμός",
    "synchronizing": "Συγχρονισμός",
    "clearingLocalData": "Εκκαθάριση τοπικών δεδομένων",
    "dentalNotation": "Οδοντικός συμβολισμός",
    "dentalNotation_desc": "επιλέξτε το προτιμώμενο σύστημα συμβολισμού",
    "palmer": "Palmer",
    "universal": "Universal",
    "ISO": "ISO",

    // advanced settings: Backups
    "backup": "Αντίγραφο ασφαλείας",
    "backups": "Αντίγραφα ασφαλείας",
    "refresh": "Ανανέωση",
    "download": "Λήψη",
    "createNew": "Δημιουργία νέου",
    "restoreBackup": "Επαναφορά αντιγράφου",
    "restoreBackupWarning1":
        "Η επαναφορά αυτού του αντιγράφου θα αντικαταστήσει όλα τα τρέχοντα δεδομένα της εφαρμογής. Οποιεσδήποτε αλλαγές κάνατε μετά την ημερομηνία αυτού του αντιγράφου",
    "restoreBackupWarning2":
        "θα χαθούν.\n\nΕίστε σίγουροι ότι θέλετε να επαναφέρετε αυτό το αντίγραφο;",
    "sureDeleteBackup":
        "Είστε σίγουροι ότι θέλετε να διαγράψετε αυτό το αντίγραφο",
    "backupDate": "Ημερομηνία αντιγράφου",
    "useTheFollowingLinkToDownloadTheBackup":
        "Χρησιμοποιήστε τον παρακάτω σύνδεσμο για να κατεβάσετε το αντίγραφο",
    "backups_config_title": "Ρύθμιση αντιγράφων ασφαλείας",
    "backups_config_desc":
        "Ρυθμίστε το πρόγραμμα αυτόματων αντιγράφων και τις ρυθμίσεις αποθήκευσης.",
    "backups_auto_enabled": "Ενεργοποίηση αυτόματων αντιγράφων",
    "backups_cron": "Πρόγραμμα (cron)",
    "backups_cron_presets": "Προεπιλογές",
    "backups_cron_hourly": "Κάθε ώρα",
    "backups_cron_6hours": "Κάθε 6 ώρες",
    "backups_cron_12hours": "Κάθε 12 ώρες",
    "backups_cron_daily": "Καθημερινά τα μεσάνυχτα",
    "backups_cron_daily3am": "Καθημερινά στις 3 π.μ.",
    "backups_cron_weekly": "Εβδομαδιαία (Κυρ. μεσάνυχτα)",
    "backups_cron_monthly": "Μηνιαία (1η μεσάνυχτα)",
    "backups_cron_hint":
        "Επιλέξτε ένα προκαθορισμένο πρόγραμμα από τη λίστα. Η έκφραση cron συμπληρώνεται αυτόματα.",
    "backups_max_keep": "Μέγιστα αντίγραφα προς διατήρηση",
    "backups_max_keep_hint":
        "Τα παλαιότερα αντίγραφα θα διαγράφονται όταν υπερβληθεί το όριο",
    "backups_s3_enabled": "Αποθήκευση αντιγράφων σε S3",
    "backups_save_success": "Οι ρυθμίσεις αντιγράφων αποθηκεύτηκαν με επιτυχία",
    "backups_save_fail": "Αποτυχία αποθήκευσης ρυθμίσεων αντιγράφων",

    // Meta settings
    "meta_settings": "Ρυθμίσεις εφαρμογής",
    "meta_info_title": "Γενικές πληροφορίες εφαρμογής",
    "meta_info_desc":
        "Ρυθμίστε το όνομα, το URL και τα στοιχεία επωνυμίας της εφαρμογής σας.",
    "meta_appName": "Όνομα εφαρμογής",
    "meta_appName_hint":
        "Εμφανίζεται στα email και στον τίτλο της οθόνης σύνδεσης",
    "meta_appUrl": "URL εφαρμογής",
    "meta_appUrl_hint": "Χρησιμοποιείται σε email και κοινόχρηστους συνδέσμους",
    "meta_save_success": "Οι ρυθμίσεις της εφαρμογής αποθηκεύτηκαν με επιτυχία",
    "meta_save_fail": "Αποτυχία αποθήκευσης ρυθμίσεων εφαρμογής",

    // Auth settings
    "auth_settings": "Ρυθμίσεις ταυτοποίησης",
    "auth_info_title": "Διάρκεια συνεδρίας",
    "auth_info_desc":
        "Ορίστε για πόσο παραμένουν έγκυρα τα tokens ταυτοποίησης πριν χρειαστεί νέα σύνδεση.",
    "auth_users_duration": "Συνεδρία χρήστη (ημέρες)",
    "auth_users_duration_hint":
        "Σε πόσες ημέρες χρειάζεται να ξανασυνδεθούν οι απλοί χρήστες",
    "auth_superusers_duration": "Συνεδρία διαχειριστή (ημέρες)",
    "auth_superusers_duration_hint":
        "Σε πόσες ημέρες χρειάζεται να ξανασυνδεθούν οι διαχειριστές",
    "auth_save_success": "Οι ρυθμίσεις ταυτοποίησης αποθηκεύτηκαν με επιτυχία",
    "auth_save_fail": "Αποτυχία αποθήκευσης ρυθμίσεων ταυτοποίησης",

    // advanced settings: Admins
    "admins": "Διαχειριστές",
    "validEmailMustBeProvided": "Πρέπει να δοθεί έγκυρο email",
    "password": "Κωδικός πρόσβασης",
    "leaveBlankToKeepUnchanged": "Αφήστε κενό για να παραμείνει αμετάβλητο",
    "updatingPassword": "Ενημέρωση κωδικού",
    "leaveItEmpty":
        "Αφήστε το πεδίο κωδικού κενό αν δεν θέλετε να τον αλλάξετε.",
    "minimumPasswordLength": "Κωδικός τουλάχιστον 10 χαρακτήρων",

    // advanced settings: Users
    "users": "Χρήστες",

    // advanced settings: Permissions
    "permissions": "Δικαιώματα χρηστών",
    "restricted": "Περιορισμένη",
    "personal": "Προσωπική",
    "full": "Πλήρης",
    "view": "Προβολή",
    "local": "τοπικά",
    "canUpload": "Επιτρέπεται η μεταφόρτωση",
    "cantUpload": "Δεν επιτρέπεται η μεταφόρτωση",
    "accounts": "Λογαριασμοί",
    "account": "Λογαριασμός",
    "user": "Χρήστης",
    "operatesOnPatients": "Επεμβαίνει σε ασθενείς",

    // S3 settings
    "s3_settings": "Ρυθμίσεις αποθήκευσης S3",
    "s3_info_title": "Ρύθμιση αποθήκευσης S3",
    "s3_info_desc":
        "Ρυθμίστε την αποθήκευση συμβατή με S3 για μεταφορτώσεις αρχείων και αντίγραφα ασφαλείας.",
    "s3_endpoint": "URL Endpoint",
    "s3_bucket": "Όνομα Bucket",
    "s3_region": "Περιοχή",
    "s3_accessKey": "Access Key",
    "s3_secretKey": "Secret Key",
    "s3_secretKey_hint":
        "Αφήστε κενό για να παραμείνει αμετάβλητο. Το secret access key του S3 σας",
    "s3_enabled": "Ενεργοποίηση αποθήκευσης S3",
    "s3_forcePathStyle": "Force path style",
    "s3_forcePathStyle_hint":
        "Χρήση path-style διευθυνσιοδότησης αντί για subdomain (απαιτείται για Cloudflare R2)",
    "s3_endpoint_hint": "Το URL endpoint του παρόχου S3 σας",
    "s3_bucket_hint": "Το όνομα του S3 bucket σας",
    "s3_region_hint": "Η περιοχή του bucket, ή 'auto' για Cloudflare R2",
    "s3_accessKey_hint": "Το access key ID του S3 σας",
    "s3_test_success": "Η ρύθμιση S3 λειτουργεί σωστά",
    "s3_test_fail": "Ο έλεγχος ρύθμισης S3 απέτυχε",
    "s3_save_success": "Οι ρυθμίσεις S3 αποθηκεύτηκαν με επιτυχία",
    "s3_save_fail": "Αποτυχία αποθήκευσης ρυθμίσεων S3",
    "test": "Έλεγχος",

    // SMTP settings
    "smtp_settings": "Ρυθμίσεις email SMTP",
    "smtp_info_title": "Ρύθμιση email SMTP",
    "smtp_info_desc":
        "Ρυθμίστε το SMTP για αποστολή email (επαναφορά κωδικών, ειδοποιήσεις κ.λπ.).",
    "smtp_host": "Host",
    "smtp_port": "Θύρα",
    "smtp_username": "Όνομα χρήστη",
    "smtp_password": "Κωδικός",
    "smtp_senderName": "Όνομα αποστολέα",
    "smtp_senderEmail": "Email αποστολέα",
    "smtp_tls": "Χρήση TLS",
    "smtp_tls_auto": "Αυτόματο (STARTTLS)",
    "smtp_tls_always": "Πάντα",
    "smtp_tls_hint": "Αυτόματο = STARTTLS (θύρα 587)\n Πάντα = SSL (θύρα 465)",
    "smtp_presets": "Προεπιλογές",
    "smtp_port_blocked_warning":
        "Ορισμένοι cloud πάροχοι (π.χ. DigitalOcean, Hetzner, Google Cloud) μπλοκάρουν εξ ορισμού τις εξερχόμενες θύρες SMTP. Βεβαιωθείτε ότι επιτρέπεται η 587 ή η 465, ή χρησιμοποιήστε διαφορετική θύρα.",
    "smtp_host_hint": "Η διεύθυνση του SMTP server του παρόχου email σας",
    "smtp_port_hint": "587 ή 465",
    "smtp_username_hint": "Συνήθως το πλήρες email σας",
    "smtp_password_hint":
        "Αφήστε κενό για να παραμείνει αμετάβλητο. Χρησιμοποιήστε app-specific κωδικό αν είναι ενεργό το 2FA",
    "smtp_app_passwords": "Κωδικοί εφαρμογών",
    "smtp_senderName_hint": "Το όνομα που εμφανίζεται στο πεδίο Από",
    "smtp_senderEmail_hint": "Το email που εμφανίζεται στο πεδίο Από",
    "smtp_localName": "Τοπικό όνομα HELO/EHLO",
    "smtp_localName_hint":
        "Χρησιμοποιείται στον χαιρετισμό HELO/EHLO, συνήθως το domain σας",
    "smtp_enabled": "Ενεργοποίηση SMTP",
    "smtp_test_success": "Η ρύθμιση SMTP λειτουργεί σωστά",
    "smtp_test_fail": "Ο έλεγχος ρύθμισης SMTP απέτυχε",
    "smtp_save_success": "Οι ρυθμίσεις SMTP αποθηκεύτηκαν με επιτυχία",
    "smtp_save_fail": "Αποτυχία αποθήκευσης ρυθμίσεων SMTP",

    "fail": "Αποτυχία",
    "success": "Επιτυχία",

    // login
    "login": "Σύνδεση",
    "clear": "Εκκαθάριση",
    "resetPassword": "Επαναφορά κωδικού",
    "serverUrl": "URL Server",
    "proceedOffline": "Συνέχεια εκτός σύνδεσης",
    "youLLGet": "Λήψη συνδέσμου επαναφοράς μέσω email",
    "beenSent":
        "Οι οδηγίες επαναφοράς κωδικού στάλθηκαν, ελέγξτε τα εισερχόμενά σας.",

    // static notifications flyout
    "notifications": "Ειδοποιήσεις",
    "enableNotifications": "Ενεργοποίηση ειδοποιήσεων",
    "dueLabworks": "Εκκρεμείς εργαστηριακές εργασίες",
    "undeliveredLabworks": "Μη παραδοθείσες εργαστηριακές εργασίες",
    "outgoingNotes": "Εξερχόμενες σημειώσεις",
    "incomingNotes": "Εισερχόμενες σημειώσεις",
    "appointmentsSetToday": "ραντεβού ορίστηκαν σήμερα",
    "labworksDue": "εργαστηριακές εργασίες σε εκκρεμότητα",
    "labworksNotDelivered": "εργαστηριακές εργασίες μη παραδοθείσες",
    "outgoingPendingNotes": "εξερχόμενες εκκρεμείς σημειώσεις",
    "incomingPendingNotes": "εισερχόμενες εκκρεμείς σημειώσεις",

    // patientSide
    "generateQRLink": "Δημιουργία κωδικού QR",
    "patientSide": "Πλευρά ασθενή",

    // other
    "sureClosePanel":
        "Είστε σίγουροι ότι θέλετε να κλείσετε αυτόν τον πίνακα; Τυχόν μη αποθηκευμένες αλλαγές θα χαθούν.",
    "sure": "Βεβαίως",
    "back": "Πίσω",
    "firstLaunchDialogTitle": "Καλώς ήρθατε στο Apexo",
    "firstLaunchDialogContent":
        "Εγκαταστήσατε με επιτυχία το Apexo. Ωστόσο, για καλύτερη εμπειρία και για πραγματική χρήση, θα χρειαστεί να ρυθμίσετε μερικά πράγματα. Σαρώστε τον παρακάτω κωδικό QR για να ξεκινήσετε.",
    "newVersionDialogTitle": "Διαθέσιμη νέα έκδοση",
    "newVersionDialogContent":
        "Μια νέα έκδοση του Apexo είναι διαθέσιμη. Ενημερώστε στην τελευταία έκδοση για την καλύτερη εμπειρία. Σαρώστε τον παρακάτω κωδικό QR για να ξεκινήσετε.",

    // login required
    "loginRequired": "Απαιτείται σύνδεση",
    "loginRequiredDesc": "Συνδεθείτε για να συνεχίσετε",

    // server help flyout
    "whatIsAServer": "Τι είναι ο server;",
    "helpOnCreatingAServer":
        "Ο server επιτρέπει την ασφαλή αποθήκευση, τη δημιουργία αντιγράφων, τον συγχρονισμό μεταξύ συσκευών και πολλά άλλα.",
    "createNewServer": "Δημιουργία νέου server",

    // errors
    "errors": "Σφάλματα",
    "reconnect": "Επανασύνδεση",
    "uploadingAttachment": "μεταφόρτωση συνημμένου",
    "errorHappenedWhen": "Παρουσιάστηκε σφάλμα κατά",
    "deletingPatientImageFromServer":
        "τη διαγραφή εικόνας ασθενή από τον server",
    "importingRemoteImages": "την εισαγωγή απομακρυσμένων εικόνων",
    "creatingNewAccount": "τη δημιουργία νέου λογαριασμού",
    "updatingAccounts": "την ενημέρωση λογαριασμών",
    "deletingAccount": "τη διαγραφή λογαριασμού",
    "uploadingPatientImageFromCamera":
        "τη μεταφόρτωση εικόνας ασθενή από κάμερα",
    "uploadingPatientImageFromGallery":
        "τη μεταφόρτωση εικόνας ασθενή από συλλογή",
    "deletingOrderImageFromServer":
        "τη διαγραφή εικόνας παραγγελίας από τον server",
    "uploadingOrderImageFromGallery":
        "τη μεταφόρτωση εικόνας παραγγελίας από συλλογή",
    "uploadingOrderImageFromCamera":
        "τη μεταφόρτωση εικόνας παραγγελίας από κάμερα",
    "openingImageFromGrid": "το άνοιγμα εικόνας από το πλέγμα",
    "openingMultipleImagesFromGrid":
        "το άνοιγμα πολλαπλών εικόνων από το πλέγμα",
    "generatingPatientLink": "τη δημιουργία συνδέσμου ασθενή",
    "gettingRemoteImagesList": "τη λήψη λίστας απομακρυσμένων εικόνων",
    "sendingUpdatesToServer": "την αποστολή ενημερώσεων στον server",
    "deletingFile": "τη διαγραφή αρχείου",
    "uploadingFile": "τη μεταφόρτωση αρχείου",

    // AI services
    "ai_services": "Υπηρεσίες AI",
    "ai_services_desc":
        "Ενεργοποιήστε ή απενεργοποιήστε λειτουργίες που βασίζονται σε AI, όπως σάρωση αποδείξεων, φωνητικές σημειώσεις και εξαγωγή οδοντιατρικού ιστορικού.",
    "on": "Ενεργό",
    "off": "Ανενεργό",
    "sameAsAppLanguage": "Ίδια με τη γλώσσα της εφαρμογής",
    "audioTranscriptionLocale": "Γλώσσα απομαγνητοφώνησης ήχου",
    "audioTranscriptionLocale_desc":
        "Από προεπιλογή, οι απομαγνητοφωνήσεις ήχου μεταφράζονται στην τρέχουσα γλώσσα της εφαρμογής. Μπορείτε να επιλέξετε μια διαφορετική γλώσσα αν χρειάζεται.",
    "no_training_privacy_info":
        "Όταν ενεργοποιείτε αυτές τις λειτουργίες, τα αρχεία σας επεξεργάζονται ιδιωτικά. Δεν τα αποθηκεύουμε ποτέ μετά την επεξεργασία — διαβάζονται μόνο στη μνήμη για το αίτημά σας (ως ροή bytes) και απορρίπτονται αμέσως μετά. Τα δεδομένα σας δεν χρησιμοποιούνται ποτέ για εκπαίδευση AI.",

    // Receipt scanner
    "scanReceipt": "Σάρωση απόδειξης",
    "readFromPhoto": "Ανάγνωση από φωτογραφία",
    "readingItemsFromPhoto": "ανάγνωση στοιχείων από φωτογραφία",
    "receiptScanFailed": "Η σάρωση της απόδειξης απέτυχε",
    "testing": "Έλεγχος σύνδεσης...",
    "unknown": "Άγνωστο",
    "unidentified": "Μη αναγνωρισμένο",

    // Dental history recording
    "VoiceAutoFill": "Αυτόματη συμπλήρωση με φωνή",
    "dentalHistoryVoiceAutoFillHint":
        "Πείτε αριθμούς και καταστάσεις δοντιών φυσικά για να ενημερωθεί αυτόματα ο χάρτης του ασθενούς.",
    "postOperativeVoiceAutoFillHint":
        "Συνοψίστε την επίσκεψη. Πείτε την καταγραφή σας, τις μετεγχειρητικές σημειώσεις, τις συνταγές, τις χρεώσεις ή τις εργαστηριακές εργασίες για αυτόματη συμπλήρωση κάθε φόρμας.",
    "transcribingYourAudio": "Απομαγνητοφώνηση του ήχου σας...",
    "recording": "Γίνεται εγγραφή",
    "paused": "Σε παύση",
    "processingDentalHistory": "επεξεργασία ήχου οδοντιατρικού ιστορικού",
    "processingPostOpNotes": "επεξεργασία ήχου μετεγχειρητικών σημειώσεων",
  };
}
