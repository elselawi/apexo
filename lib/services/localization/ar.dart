// ignore_for_file: annotate_overrides

import "en.dart";

class Ar implements En {
  Direction $direction = Direction.rtl;
  String $name = "العربية";
  String $code = "ar";

  Map<String, String> dictionary = {
    // common
    "cancel": "إلغاء",
    "close": "غلق",
    "save": "حفظ",
    "reset": "إعادة تعيين",
    "continue": "استمر",
    "add": "إضافة",
    "edit": "تعديل",
    "delete": "حذف",
    "archive": "أرشفة",
    "restore": "استعادة",
    "logout": "خروج",
    "noResultsFound": "لم يتم العثور على نتائج",
    "home": "الرئيسية",
    "calendar": "الرزنامة",
    "gettingImages": "يتم تحميل الصور",

    // call
    "callLaboratory": "اتصل بالمختبر",
    "callPatient": "اتصل بالمريض",
    "emailDoctor": "ارسال بريد الكتروني",
    "callIssuer": "اتصل بالبائع",

    // screens
    "settings": "إعدادات",
    "dashboard": "الرئيسية",
    "appointments": "مواعيد",
    "patients": "مرضى",
    "doctors": "الاطباء",
    "labworks": "أعمال المختبر",
    "statistics": "إحصائيات",

    // dashboard
    "admin": "مسؤول",
    "fullStats": "إحصائيات كاملة",
    "payments": "مدفوعات",
    "appointmentsToday": "المواعيد اليوم",
    "patientsToday": "المرضى اليوم",
    "newPatientsToday": "مرضى جدد اليوم",
    "paymentsMadeToday": "المدفوعات اليوم",
    "modeAdmin": "مسؤول",
    "modeUser": "مستخدم",
    "modeOffline": "غير متصل",
    "onceConnectionIsStable":
        "عندما يصبح اتصالك مستقرًا، يمكنك استخدام الزر في الزاوية اليمنى العليا لإعادة الاتصال.",
    "unRestrictedAccess": "وصول غير مقيد في التطبيق",
    "restrictedAccess": "وصول مقيد إلى بعض الصفحات كما يحدده المسؤول",
    "youAreCurrentlyIn": "أنت حاليًا في",
    "mode": "الوضع",
    "youHave": "لديك",
    "hello": "مرحبا",

    // datatable
    "archiveSelected": "أرشفة المحدد",
    "searchPlaceholder": "بحث...",
    "showHideArchived": "إظهار/إخفاء المؤرشفة",
    "showing": "يتم إظهار",
    "showMore": "إظهار المزيد",
    "by": "بحسب",
    "byTitle": "بحسب العنوان",
    "byDate": "بحسب التاريخ",
    "noItemsFound": "لم يتم العثور على عناصر",
    "filter": "تصفية",

    // doctors
    "doctor": "طبيب",
    "newDoctor": "طبيب جديد",
    "doctorDetails": "تفاصيل الطبيب",
    "pastAppointments": "المواعيد السابقة",
    "upcomingAppointments": "المواعيد القادمة",
    "doctorName": "اسم الطبيب",
    "doctorEmail": "بريد الطبيب الإلكتروني",
    "dutyDays": "أيام العمل",
    "addAppointment": "إضافة موعد",
    "lockToUsers":
        "يمكن فقط للمستخدمين التاليين الوصول لمعلومات ومواعيد الطبيب وتعديلها",
    "noUpcomingAppointmentsForThisDoctor":
        "لا يوجد مواعيد قادمة مسجلة لهذا الطبيب، استخدم الزر ادناه لتسجيل موعد جديد",

    // days and months
    "monday": "الاثنين",
    "tuesday": "الثلاثاء",
    "wednesday": "الأربعاء",
    "thursday": "الخميس",
    "friday": "الجمعة",
    "saturday": "السبت",
    "sunday": "الأحد",
    "january": "يناير",
    "february": "فبراير",
    "march": "مارس",
    "april": "أبريل",
    "may": "مايو",
    "june": "يونيو",
    "july": "يوليو",
    "august": "أغسطس",
    "september": "سبتمبر",
    "october": "أكتوبر",
    "november": "نوفمبر",
    "december": "ديسمبر",

    // appointment card
    "appointment": "موعد",
    "patient": "مريض",
    "photos": "صور",
    "pre-opNotes": "ملاحظات ما قبل العملية",
    "post-opNotes": "ملاحظات ما بعد العملية",
    "prescription": "وصفة طبية",
    "pay": "دفع",
    "paid": "مدفوع",
    "price": "السعر",
    "underpaid": "دفع ناقص",
    "overpaid": "دفع زائد",
    "fullyPaid": "كامل",
    "includesOtherAppointments":
        "هذا الإجمالي يعكس أيضًا المدفوعات الخاصة بمواعيد أخرى.",
    "paymentSummary": "ملخص الدفع",
    "editingAppointment": "تعديل الموعد",
    "after": "بعد",
    "days": "أيام",
    "day": "يوم",
    "isDone": "تم الانتهاء منه",
    "addLabwork": "إضافة عمل مختبري لهذا الموعد",
    "labworksForThisAppointment": "العمل المختبري الخاص بهذا الموعد",

    // patients
    "patientDetails": "تفاصيل المريض",
    "age": "العمر",
    "gender": "الجنس",
    "last visit": "آخر زيارة",
    "total payments": "إجمالي المدفوعات",
    "daysAgo": "أيام مضت",
    "noVisits": "لا توجد زيارات",
    "addNewPatient": "إضافة مريض جديد",
    "name": "الاسم",
    "birthYear": "سنة الميلاد",
    "phone": "الهاتف",
    "email": "البريد الإلكتروني",
    "address": "العنوان",
    "notes": "ملاحظات",
    "patientTags": "سمات المريض",
    "male": "ذكر",
    "female": "أنثى",
    "noAppointmentsFound":
        "لم يتم العثور على مواعيد لهذا المريض، استخدم الزر أدناه لإضافة موعد جديد.",
    "editPatient": "تعديل المريض",
    "editAppointment": "تعديل الموعد",
    "patientPage": "صفحة ويب المريض",
    "patientCanUseTheFollowing":
        "يمكن للمريض استخدام الرابط التالي للوصول إلى مواعيده ومدفوعاته وصوره.",
    "printQR": "طباعة الرمز",
    "dentalNotes": "الملاحظات السنية",
    "showPrimary": "إظهار اللبني",
    "showPermanent": "إظهار الدائم",
    "primary": "سن لبني",
    "permanent": "سن دائم",
    "lower": "سفلي",
    "upper": "علوي",
    "left": "يسار",
    "right": "يمين",
    "centralIncisor": "قاطع وسطي",
    "lateralIncisor": "قاطع جانبي",
    "canine": "ناب",
    "firstPremolar": "ضاحك أول",
    "secondPremolar": "ضاحك ثاني",
    "firstMolar": "رحاة اولى",
    "secondMolar": "رحاة ثانية",
    "thirdMolar": "رحاة ثالثة",
    "exportSelected": "تصدير المحدد",
    "noPatientsSelected": "لم يتم اختيار أي مرضى",

    // calendar (appointments)
    "allDoctors": "جميع الأطباء",
    "noAppointmentsForThisDay": "لا توجد مواعيد لهذا اليوم",
    "weekAbbr": "أسبوع",
    "twoWeeksAbbr": "أسبوعان",
    "monthAbbr": "شهر",
    "today": "اليوم",
    "newPatient": "مريض جديد",
    "date": "التاريخ",
    "changeDate": "تغيير التاريخ",
    "changeTime": "تغيير الوقت",
    "attention": "انتباه",
    "doctorNotAvailable":
        "قد لا يكون أحد الأطباء المحددين متاحًا في التاريخ المحدد.",
    "time": "الوقت",
    "preOperativeNotes": "ملاحظات ما قبل العملية",
    "selectDoctors": "اختيار الأطباء",
    "selectPatient": "اختيار المريض",
    "operativeDetails": "تفاصيل العملية",
    "postOperativeNotes": "ملاحظات ما بعد العملية",
    "printPrescription": "طباعة الوصفة الطبية",
    "priceIn": "السعر بـ",
    "paidIn": "مدفوع بـ",
    "gallery": "معرض الصور",
    "link": "رابط",
    "upload": "تحميل",
    "camera": "كاميرا",
    "emptyGallery": "معرض فارغ",
    "noPhotos": "لم يتم تحميل أي صور حتى الآن.",
    "importingPhotosFromLink": "استيراد الصور من الرابط",
    "useThisForm":
        "استخدم هذا النموذج لاستيراد الصور من روابط المشاركة، مثل صور جوجل، أو أي صفحة ويب قابلة للوصول تحتوي على صور ترغب في إضافتها إلى هذا الموعد.",
    "error": "خطأ",
    "enterLink": "أدخل عنوان URL الذي يحتوي على صور",
    "import": "استيراد",

    // labworks
    "laboratory": "مختبر",
    "month": "شهر",
    "newLabwork": "عمل مختبر جديد",
    "labwork": "عمل المختبر",
    "labworkTitle": "عنوان عمل المختبر",
    "orderNotes": "ملاحظات الطلب",
    "unpaid": "غير مدفوع",
    "noSuggestions": "لا توجد اقتراحات",
    "received": "تم الاستلام من المختبر",
    "showReceived": "إظهار المستلم",

    // expenses
    "expense": "مصروف",
    "expenses": "مصاريف",
    "receipt": "وصل",
    "title": "العنوان",
    "cost": "التكلفة",
    "issuer": "البائع",
    "amount": "القيمة",
    "amountIn": "المبلغ بـ",
    "status": "الحالة",
    "due": "مستحق",
    "receiptTitle": "عنوان الوصل",
    "receiptNotes": "ملاحظات الوصل",
    "newReceipt": "وصل جديد",
    "receiptTags": "العلامات المرتبطة بالوصل",
    "receiptItems": "عناصر الوصل",
    "specificForDoctors": "خاص للأطباء التاليين",

    // stats
    "pickRange": "اختيار النطاق",
    "start": "بداية",
    "end": "نهاية",
    "weeks": "أسابيع",
    "months": "أشهر",
    "quarters": "ربع سنوي",
    "years": "سنوات",
    "appointmentsPer": "المواعيد بحسب",
    "paymentsAndExpensesPer": "المدفوعات والمصاريف بحسب",
    "newPatientsPer": "المرضى الجدد بحسب",
    "doneMissedPer": "المنجز والمفقود بحسب",
    "timeOfDay": "أوقات اليوم",
    "dayOfWeek": "أيام الاسبوع",
    "dayOfMonth": "أيام الشهر",
    "monthOfYear": "أشهر السنة",
    "patientsGender": "جنس المرضى",
    "total": "المجموع",
    "in_Duration_": "في",
    "acquiredPatientsIn": "المرضى المكتسبون في",
    "doneAndMissedAppointmentsIn": "المواعيد المنجزة والمفقودة في",
    "distributionOfAppointments": "توزيع المواعيد",
    "maleAndFemalePatients": "المرضى الذكور والإناث",
    "done": "منجز",
    "missed": "مفقود",

    // settings
    "currency": "العملة",
    "currency_desc":
        "رمز العملة المستخدم في جميع أنحاء التطبيق (مثل USD، EUR، IQD).",
    "phone_desc": "سيتم عرض رقم الهاتف في الطباعات وصفحة ويب المرضى.",
    "prescriptionFooter": "تذييل الوصفة الطبية",
    "prescriptionFooter_desc":
        "سيتم عرض هذا النص في اسفل الوصفة الطبية، يمكن استخدامه لوضع العنوان او رقم التسجيل النقابي.",
    "language": "اللغة",
    "language_desc":
        "لغة واجهة المستخدم للقوائم والأزرار والمعلومات المستخدمة في التطبيق.",
    "startingDayOfWeek": "يوم بداية الأسبوع",
    "startingDayOfWeek_desc": "اليوم الذي يبدأ فيه الأسبوع.",
    "dateFormat": "تنسيق التاريخ",
    "dateFormat_desc":
        "سيتم استخدام هذا التنسيق لعرض التواريخ حيثما كان ذلك ممكنًا.",
    "cacheReset": "الغاء التخزين المحلي",
    "cacheReset_desc":
        "يمكنك من خلال الزر ادناه الغاء التخزين المحلي للتطبيق - عدا الصور - لحل بعض المشاكل التي قد تواجهك اثناء المزامنة مع الأجهزة الأخرى.",
    "month/day/year": "شهر/يوم/سنة",
    "day/month/year": "يوم/شهر/سنة",
    "appliesTo": "ينطبق على",
    "all": "الكل",
    "you": "أنت",
    "initialSynchronization": "مزامة أولية",
    "synchronizing": "مزامنة مع الخادم",
    "clearingLocalData": "إزالة البيانات المحلية",

    // advanced settings: Backups
    "backups": "النسخ الاحتياطي",
    "refresh": "تحديث",
    "download": "تحميل",
    "createNew": "إنشاء جديد",
    "restoreBackup": "استعادة النسخة الاحتياطية",
    "restoreBackupWarning1":
        "سيتم الكتابة فوق جميع البيانات في التطبيق حاليًا عند استعادة هذا النسخ الاحتياطي. أي تغييرات قمت بها بعد تاريخ هذا النسخ الاحتياطي",
    "restoreBackupWarning2":
        "ستضيع.\n\nهل أنت متأكد من أنك تريد استعادة هذا النسخ الاحتياطي؟",
    "sureDeleteBackup": "هل أنت متأكد من أنك تريد حذف هذا النسخ الاحتياطي",
    "backupDate": "تاريخ النسخ الاحتياطي",
    "useTheFollowingLinkToDownloadTheBackup":
        "استخدم الرابط التالي لتحميل النسخة الاحتياطية",

    // advanced settings: Admins
    "admins": "المسؤولين",
    "accountCreated": "تم إنشاء الحساب",
    "editAdmin": "تعديل المسؤول",
    "validEmailMustBeProvided": "يجب تقديم بريد إلكتروني صالح",
    "password": "كلمة المرور",
    "leaveBlankToKeepUnchanged": "اتركه فارغًا للإبقاء عليه دون تغيير",
    "updatingPassword": "تحديث كلمة المرور",
    "leaveItEmpty": "اترك حقل كلمة المرور فارغًا إذا كنت لا تريد تغييره.",
    "newAdmin": "مسؤول جديد",
    "minimumPasswordLength": "كلمة مرور من 10 أحرف على الأقل",

    // advanced settings: Users
    "users": "المستخدمين",
    "editUser": "تعديل المستخدم",
    "newUser": "مستخدم جديد",

    // advanced settings: Permissions
    "permissions": "أذونات المستخدم",
    "usersCanAccess": "يمكن للمستخدمين الوصول إلى",
    "permissionsNotice":
        "تنطبق الأذونات التالية على المستخدمين المدرجين أعلاه والوصول غير المتصل. ومع ذلك، يتمتع المسؤولون مثلك بوصول غير مقيد في التطبيق، ما لم يكن غير متصل.",

    // advanced settings: prod tests
    "prodTests": "اختبارات الإنتاج",
    "fileStorageTest": "اختبار تخزين الملفات",
    "fileStorageTestDesc":
        "استخدم الزر التالي لاختبار ما إذا كان تخزين S3 يعمل بشكل صحيح.",
    "fileStorageButton": "اختبار إعداد S3",
    "fileStorageFail": "فشل إعداد S3",
    "fileStorageSuccess": "إعداد S3 يعمل بشكل صحيح",
    "emailTest": "اختبار البريد الإلكتروني",
    "emailTestDesc":
        "استخدم الزر التالي لاختبار ما إذا كان خادمك يمكنه إرسال البريد الإلكتروني بشكل صحيح. يجب تسليم بريد إلكتروني يشبه إعادة تعيين كلمة المرور إلى عنوان البريد الإلكتروني المستهدف.",
    "targetEmail": "البريد الإلكتروني المستهدف",
    "emailTestButton": "إرسال بريد إلكتروني تجريبي",
    "emailTestFail": "فشل اختبار البريد الإلكتروني",
    "emailTestSuccess":
        "تم إرسال البريد الإلكتروني بنجاح، يرجى التحقق من بريدك الوارد.",
    "fail": "فشل",
    "success": "نجاح",

    // login
    "login": "تسجيل الدخول",
    "resetPassword": "إعادة تعيين كلمة المرور",
    "serverUrl": "رابط الخادم",
    "proceedOffline": "بدون اتصال",
    "youLLGet": "ستصلك التعليمات عبر بريدك الالكتروني",
    "beenSent":
        "لقد تم ارسال رابط اعادة تعيين كلمة المرور الخاص بك عبر بريدك الالكتروني",

    // other
    "otherNotesPerAppointment":
        "هنالك ملاحظات اخرى مسجلة ضمن مواعيد محددة، تظهر في صفحة المواعيد ولا تظهر هنا.",
    "sureArchiveSelected": "هل انت متأكد من حذف العناصر المحددة؟",
    "sureClosePanel":
        "هل انت متأكد من اغلاق هذه النافذة؟ سيتم الغاء جميع التغييرات التي قمت بها",
    "sure": "متأكد",
    "back": "تراجع",
    "firstLaunchDialogTitle": "تم تنصيب البرنامج بنجاح",
    "firstLaunchDialogContent":
        "يمكنك الان استخدام البرنامج كما تحب. ولكن هنالك بعض الخطوات الاضافية التي يجب ان تتخذها من أجل تجربة مثالية أكثر ومن اجل الحفاظ على بياناتك من الفقدان. قم بمسح الكود التالي من خلال هاتفك لمعرفة المزيد.",
    "newVersionDialogTitle": "هنالك اصدار جديد متاح",
    "newVersionDialogContent":
        "يرجى تحديث التطبيق للحصول على أحدث الميزات والتطويرات الجديدة. قم بمسح الكود التالي لتحميل التحديث الجديد.",
  };
}
