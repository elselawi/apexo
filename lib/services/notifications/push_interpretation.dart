/// What a push payload *means*, and how it reads in each language.
///
/// `push_data.dart` is the wire shape; this is the presentation of it — which
/// interpretation a payload calls for, and the title/body pair each
/// interpretation has in every language the app ships.
///
/// All of it is an extension on the payload rather than members of it, so the
/// payload itself stays a plain wire object. The cost is that a call site must
/// **import this file** to use `displayTuple()`: an extension member is not
/// brought into scope by the type alone.
///
/// ---------------------------------------------------------------------------
///  !!!! IMPORTANT !!!!
/// `web/fcm/push_data.js` mirrors `_interpret()` and its translations so the web
/// app and its service worker read a push the same way this file does. The two
/// must agree — the payload's own fields are mirrored in `push_data.dart`.
/// ---------------------------------------------------------------------------
library;

import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Resolves the active recipient ID (staff account or patient portal ID).
String _activeAccountID() {
  if (login.currentAccountID.isNotEmpty) return login.currentAccountID;
  if (patientSide.patientID.isNotEmpty) return patientSide.patientID;
  return "";
}

/// The reading of a payload: the notification's title and body, as the OS
/// notification and the in-app list both want them.
extension PushDataDisplay on PushData {
  /// The title and body to show for this payload, in the app's language, with
  /// the record's readable identifier appended to the body.
  List<String> displayTuple() {
    final interpretation = interpret();
    final lang = _langForCode(locale.s.$code);
    final tuple = [
      ...(_translations[lang]?[interpretation] ??
          _translations[_Langs.en]![interpretation]!)
    ];
    final identifier = readableIdentifier.trim();
    if (identifier.isNotEmpty) {
      tuple[1] = "${tuple[1]}: $readableIdentifier";
    }
    return tuple;
  }

  /// The old and new value of [field], as the payload carries them.
  ///
  /// Both are `null` when the payload does not carry the value. This is not a
  /// defensive nicety: `updatedFields`, `oldVals` and `newVals` are three
  /// independent lists on the wire, and this reads a payload a *remote* sender
  /// produced, so a short list or a missing before-side must degrade to
  /// "unknown" rather than throw.
  (Object?, Object?) _valsTuple(String field) {
    final i = updatedFields.indexOf(field);
    if (i < 0) return (null, null);
    return (
      i < oldVals.length ? oldVals[i] : null,
      i < newVals.length ? newVals[i] : null,
    );
  }

  /// Resolves what [this] payload means for the active recipient.
  @visibleForTesting
  PushInterpretation interpret() => _interpret();

  PushInterpretation _interpret() {
    if (isCreation && store == "appointments") {
      return PushInterpretation.newAppointmentForYou;
    }

    if (isCreation && store == "notes") {
      return PushInterpretation.newNoteForYou;
    }

    final currentAccount = _activeAccountID();

    if (isUpdate && store == "appointments") {
      if (updatedFields.contains("date")) {
        final (oldDate, newDate) = _valsTuple("date");
        // `date` travels as minutes since the epoch (`Appointments.toWire`),
        // so this is an integer comparison, not a chronological one, and both
        // sides must be present before there is a direction to report.
        if (oldDate is num && newDate is num) {
          if (oldDate > newDate) {
            return PushInterpretation.appointmentDateHasBeenMovedEarlier;
          } else if (oldDate < newDate) {
            return PushInterpretation.appointmentDateHasBeenMovedLater;
          }
        }
      }
      if (updatedFields.contains("isDone")) {
        final vals = _valsTuple("isDone");
        if (vals.$2 == true) {
          return PushInterpretation.appointmentIsNowDone;
        } else {
          return PushInterpretation.appointmentStatusBeenChanged;
        }
      }
      if (updatedFields.contains("archived")) {
        final vals = _valsTuple("archived");
        if (vals.$2 == true) {
          return PushInterpretation.appointmentHasBeenCancelled;
        } else {
          return PushInterpretation.appointmentStatusBeenChanged;
        }
      }
      if (updatedFields.contains("operatorsIDs")) {
        final (_, newOperators) = _valsTuple("operatorsIDs");
        // `List`, not `List<String>`: a payload that round-tripped through JSON
        // holds a `List<dynamic>`, which is not a `List<String>`.
        if (currentAccount.isNotEmpty &&
            newOperators is List &&
            newOperators.contains(currentAccount)) {
          return PushInterpretation.appointmentHasBeenAssignedToYou;
        } else {
          return PushInterpretation.appointmentStatusBeenChanged;
        }
      }
    }

    if (isUpdate && store == "notes") {
      if (updatedFields.contains("comments")) {
        return PushInterpretation.newCommentAddedToYourNote;
      }
      if (updatedFields.contains("attachments")) {
        return PushInterpretation.newAttachmentsAddedToYourNote;
      }
      if (updatedFields.contains("done")) {
        final vals = _valsTuple("done");
        if (vals.$2 == true) {
          return PushInterpretation.noteHasBeenMarkedAsDone;
        } else {
          return PushInterpretation.noteHasBeenMarkedAsPending;
        }
      }
      if (updatedFields.contains("assignedTo")) {
        final (_, val) = _valsTuple("assignedTo");
        if (currentAccount.isNotEmpty && val == currentAccount) {
          return PushInterpretation.aNewNoteHasBeenAssignedToYou;
        } else {
          return PushInterpretation.assigneeOnYourNoteHasChanged;
        }
      }
      if (updatedFields.contains("dueDate")) {
        final (oldDue, newDue) = _valsTuple("dueDate");
        // `dueDate` travels as hours since the epoch (`Notes.toWire`).
        if (oldDue is num && newDue is num) {
          if (oldDue > newDue) {
            return PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier;
          } else if (oldDue < newDue) {
            return PushInterpretation.dueDateOnYourNoteHasBeenMovedLater;
          }
        }
      }
      if (updatedFields.contains("archived")) {
        final vals = _valsTuple("archived");
        if (vals.$2 == true) {
          return PushInterpretation.yourNoteHasBeenArchived;
        } else {
          return PushInterpretation.yourNoteHasBeenUnarchived;
        }
      }
    }

    // Nothing matched. For a store we *do* notify about, an update that reached
    // this point is malformed — a field list or value list that is absent, the
    // wrong type, or shorter than the field list it indexes. The wording below
    // degrades to the generic "new notification", which is the right *display*
    // but must not hide a sender-side regression, so it is reported once.
    if (isUpdate && (store == 'appointments' || store == 'notes')) {
      _reportUninterpretable();
    }
    return PushInterpretation.newNotification;
  }

  /// Reports (once per datum) that a payload could not be interpreted.
  void _reportUninterpretable() {
    if (uninterpretableReported) return;
    uninterpretableReported = true;
    logger(
      'Push payload could not be interpreted — store "$store", '
      'isCreation=$isCreation, isUpdate=$isUpdate, '
      'updatedFields=$updatedFields, oldVals=$oldVals, newVals=$newVals. '
      'Falling back to the generic notification.',
      null,
      3,
    );
  }
}

enum PushInterpretation {
  // creation
  newAppointmentForYou,
  newNoteForYou,
  newNotification,
  // appointment update
  appointmentDateHasBeenMovedEarlier,
  appointmentDateHasBeenMovedLater,
  appointmentIsNowDone,
  appointmentHasBeenCancelled,
  appointmentStatusBeenChanged,
  appointmentHasBeenAssignedToYou,
  // notes update
  newCommentAddedToYourNote,
  noteHasBeenMarkedAsDone,
  noteHasBeenMarkedAsPending,
  newAttachmentsAddedToYourNote,
  aNewNoteHasBeenAssignedToYou,
  assigneeOnYourNoteHasChanged,
  dueDateOnYourNoteHasBeenMovedEarlier,
  dueDateOnYourNoteHasBeenMovedLater,
  yourNoteHasBeenArchived,
  yourNoteHasBeenUnarchived,
}

enum _Langs { en, ar, es, el, fa, ku, fr, tr, it, ur }

_Langs _langForCode(String code) {
  for (final lang in _Langs.values) {
    if (lang.name == code) return lang;
  }
  return _Langs.en;
}

/// Supported language codes for push notification translations.
@visibleForTesting
List<String> get supportedPushLanguageCodes =>
    _Langs.values.map((l) => l.name).toList(growable: false);

/// Returns the translation pair `[title, body]` for [langCode] and
/// [interpretation], falling back to English if [langCode] is unknown.
@visibleForTesting
List<String> pushTranslationFor(
  String langCode,
  PushInterpretation interpretation,
) {
  final lang = _langForCode(langCode);
  return [
    ...(_translations[lang]?[interpretation] ??
        _translations[_Langs.en]![interpretation]!)
  ];
}

final Map<_Langs, Map<PushInterpretation, List<String>>> _translations = {
  _Langs.en: {
    PushInterpretation.newNotification: [
      "Notifications",
      "You have a new notification"
    ],
    PushInterpretation.newAppointmentForYou: [
      "Appointments",
      "You have a new appointment"
    ],
    PushInterpretation.newNoteForYou: ["Notes", "You have a new note"],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "Your appointment",
      "Your appointments has been moved earlier"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "Your appointment",
      "Your appointments has been moved later"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "Your appointment",
      "Your appointment is now done"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "Your appointment",
      "Your appointment has been cancelled"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "Your appointment",
      "Your appointment status has been changed"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "Appointments",
      "An appointment has been assigned to you"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "Your note",
      "A new comment has been added to your note"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "Your note",
      "Your note has been marked as done"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "Your note",
      "Your note has been marked as pending"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "Your note",
      "New attachments have been added to your note"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "Notes",
      "A new note has been assigned to you"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "Your note",
      "The assignee on your note has changed"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Your note",
      "The due date on your note has been moved earlier"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "Your note",
      "The due date on your note has been moved later"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "Your note",
      "Your note has been archived"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "Your note",
      "Your note has been unarchived"
    ],
  },
  _Langs.ar: {
    PushInterpretation.newNotification: ["الإشعارات", "لديك إشعار جديد"],
    PushInterpretation.newAppointmentForYou: ["المواعيد", "لديك موعد جديد"],
    PushInterpretation.newNoteForYou: ["الملاحظات", "لديك ملاحظة جديدة"],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "موعدك",
      "تم نقل موعدك إلى وقت أبكر"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "موعدك",
      "تم نقل موعدك إلى وقت لاحق"
    ],
    PushInterpretation.appointmentIsNowDone: ["موعدك", "تم إنجاز موعدك"],
    PushInterpretation.appointmentHasBeenCancelled: ["موعدك", "تم إلغاء موعدك"],
    PushInterpretation.appointmentStatusBeenChanged: [
      "موعدك",
      "تم تغيير حالة موعدك"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "المواعيد",
      "تم تعيين موعد لك"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "ملاحظتك",
      "تم إضافة تعليق جديد إلى ملاحظتك"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "ملاحظتك",
      "تم تأشير ملاحظتك كمنجزة"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "ملاحظتك",
      "تم تأشير ملاحظتك كمعلقة"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "ملاحظتك",
      "تم إضافة مرفقات جديدة إلى ملاحظتك"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "الملاحظات",
      "تم تعيين ملاحظة جديدة لك"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "ملاحظتك",
      "تم تغيير المسؤول عن ملاحظتك"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "ملاحظتك",
      "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت أبكر"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "ملاحظتك",
      "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت لاحق"
    ],
    PushInterpretation.yourNoteHasBeenArchived: ["ملاحظتك", "تم أرشفة ملاحظتك"],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "ملاحظتك",
      "تم إلغاء أرشفة ملاحظتك"
    ],
  },
  _Langs.es: {
    PushInterpretation.newNotification: [
      "Notificaciones",
      "Tienes una nueva notificación"
    ],
    PushInterpretation.newAppointmentForYou: ["Citas", "Tienes una nueva cita"],
    PushInterpretation.newNoteForYou: ["Notas", "Tienes una nueva nota"],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "Tu cita",
      "Tu cita ha sido movida a una fecha anterior"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "Tu cita",
      "Tu cita ha sido movida a una fecha posterior"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "Tu cita",
      "Tu cita ha sido completada"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "Tu cita",
      "Tu cita ha sido cancelada"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "Tu cita",
      "El estado de tu cita ha sido cambiado"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "Citas",
      "Una cita ha sido asignada a ti"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "Tu nota",
      "Se ha añadido un nuevo comentario a tu nota"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "Tu nota",
      "Tu nota ha sido marcada como completada"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "Tu nota",
      "Tu nota ha sido marcada como pendiente"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "Tu nota",
      "Se han añadido nuevos archivos adjuntos a tu nota"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "Notas",
      "Se te ha asignado una nueva nota"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "Tu nota",
      "El responsable de tu nota ha cambiado"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Tu nota",
      "La fecha de vencimiento de tu nota ha sido movida a una fecha anterior"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "Tu nota",
      "La fecha de vencimiento de tu nota ha sido movida a una fecha posterior"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "Tu nota",
      "Tu nota ha sido archivada"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "Tu nota",
      "Tu nota ha sido desarchivada"
    ],
  },
  _Langs.el: {
    PushInterpretation.newNotification: [
      "Ειδοποιήσεις",
      "Έχετε μια νέα ειδοποίηση"
    ],
    PushInterpretation.newAppointmentForYou: [
      "Ραντεβού",
      "Έχετε ένα νέο ραντεβού"
    ],
    PushInterpretation.newNoteForYou: [
      "Σημειώσεις",
      "Έχετε μια νέα σημείωση"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "Το ραντεβού σας",
      "Το ραντεβού σας μεταφέρθηκε νωρίτερα"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "Το ραντεβού σας",
      "Το ραντεβού σας μεταφέρθηκε αργότερα"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "Το ραντεβού σας",
      "Το ραντεβού σας ολοκληρώθηκε"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "Το ραντεβού σας",
      "Το ραντεβού σας ακυρώθηκε"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "Το ραντεβού σας",
      "Η κατάσταση του ραντεβού σας άλλαξε"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "Ραντεβού",
      "Σας ανατέθηκε ένα ραντεβού"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "Η σημείωσή σας",
      "Προστέθηκε νέο σχόλιο στη σημείωσή σας"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "Η σημείωσή σας",
      "Η σημείωσή σας σημειώθηκε ως ολοκληρωμένη"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "Η σημείωσή σας",
      "Η σημείωσή σας σημειώθηκε ως εκκρεμής"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "Η σημείωσή σας",
      "Προστέθηκαν νέα συνημμένα στη σημείωσή σας"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "Σημειώσεις",
      "Σας ανατέθηκε μια νέα σημείωση"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "Η σημείωσή σας",
      "Ο υπεύθυνος της σημείωσής σας άλλαξε"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Η σημείωσή σας",
      "Η ημερομηνία λήξης της σημείωσής σας μεταφέρθηκε νωρίτερα"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "Η σημείωσή σας",
      "Η ημερομηνία λήξης της σημείωσής σας μεταφέρθηκε αργότερα"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "Η σημείωσή σας",
      "Η σημείωσή σας αρχειοθετήθηκε"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "Η σημείωσή σας",
      "Η σημείωσή σας επανήλθε από το αρχείο"
    ],
  },
  _Langs.fa: {
    PushInterpretation.newNotification: [
      "اعلان‌ها",
      "شما یک اعلان جدید دارید"
    ],
    PushInterpretation.newAppointmentForYou: [
      "نوبت‌ها",
      "شما یک نوبت جدید دارید"
    ],
    PushInterpretation.newNoteForYou: [
      "یادداشت‌ها",
      "شما یک یادداشت جدید دارید"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "نوبت شما",
      "نوبت شما به زمان زودتری منتقل شد"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "نوبت شما",
      "نوبت شما به زمان دیرتری منتقل شد"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "نوبت شما",
      "نوبت شما انجام شد"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "نوبت شما",
      "نوبت شما لغو شد"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "نوبت شما",
      "وضعیت نوبت شما تغییر کرد"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "نوبت‌ها",
      "یک نوبت به شما اختصاص داده شد"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "یادداشت شما",
      "نظر جدیدی به یادداشت شما اضافه شد"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "یادداشت شما",
      "یادداشت شما به عنوان انجام‌شده علامت‌گذاری شد"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "یادداشت شما",
      "یادداشت شما به عنوان در انتظار علامت‌گذاری شد"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "یادداشت شما",
      "پیوست‌های جدیدی به یادداشت شما اضافه شد"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "یادداشت‌ها",
      "یک یادداشت جدید به شما اختصاص داده شد"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "یادداشت شما",
      "مسئول یادداشت شما تغییر کرد"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "یادداشت شما",
      "تاریخ سررسید یادداشت شما به زمان زودتری منتقل شد"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "یادداشت شما",
      "تاریخ سررسید یادداشت شما به زمان دیرتری منتقل شد"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "یادداشت شما",
      "یادداشت شما بایگانی شد"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "یادداشت شما",
      "یادداشت شما از بایگانی خارج شد"
    ],
  },
  _Langs.ku: {
    PushInterpretation.newNotification: [
      "ئاگادارکردنەوەکان",
      "ئاگادارکردنەوەیەکی نوێت هەیە"
    ],
    PushInterpretation.newAppointmentForYou: [
      "مەوعیدەکان",
      "مەوعیدێکی نوێت هەیە"
    ],
    PushInterpretation.newNoteForYou: [
      "تێبینییەکان",
      "تێبینییەکی نوێت هەیە"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "مەوعیدەکەت",
      "مەوعیدەکەت بۆ کاتێکی زووتر گواسترایەوە"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "مەوعیدەکەت",
      "مەوعیدەکەت بۆ کاتێکی درەنگتر گواسترایەوە"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "مەوعیدەکەت",
      "مەوعیدەکەت تەواو بوو"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "مەوعیدەکەت",
      "مەوعیدەکەت هەڵوەشێنرایەوە"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "مەوعیدەکەت",
      "دۆخی مەوعیدەکەت گۆڕا"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "مەوعیدەکان",
      "مەوعیدێک بۆ تۆ دیاری کرا"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "تێبینییەکەت",
      "لێدوانێکی نوێ زیاد کرا بۆ تێبینییەکەت"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "تێبینییەکەت",
      "تێبینییەکەت وەک تەواوبوو نیشانە کرا"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "تێبینییەکەت",
      "تێبینییەکەت وەک چاوەڕوانکراو نیشانە کرا"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "تێبینییەکەت",
      "هاوپێچی نوێ زیاد کرا بۆ تێبینییەکەت"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "تێبینییەکان",
      "تێبینییەکی نوێ بۆ تۆ دیاری کرا"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "تێبینییەکەت",
      "بەرپرسی تێبینییەکەت گۆڕا"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "تێبینییەکەت",
      "بەرواری کۆتایی تێبینییەکەت بۆ کاتێکی زووتر گواسترایەوە"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "تێبینییەکەت",
      "بەرواری کۆتایی تێبینییەکەت بۆ کاتێکی درەنگتر گواسترایەوە"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "تێبینییەکەت",
      "تێبینییەکەت ئەرشیف کرا"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "تێبینییەکەت",
      "تێبینییەکەت لە ئەرشیف دەرهێنرا"
    ],
  },
  _Langs.fr: {
    PushInterpretation.newNotification: [
      "Notifications",
      "Vous avez une nouvelle notification"
    ],
    PushInterpretation.newAppointmentForYou: [
      "Rendez-vous",
      "Vous avez un nouveau rendez-vous"
    ],
    PushInterpretation.newNoteForYou: [
      "Notes",
      "Vous avez une nouvelle note"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "Votre rendez-vous",
      "Votre rendez-vous a été avancé"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "Votre rendez-vous",
      "Votre rendez-vous a été reporté"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "Votre rendez-vous",
      "Votre rendez-vous est maintenant terminé"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "Votre rendez-vous",
      "Votre rendez-vous a été annulé"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "Votre rendez-vous",
      "Le statut de votre rendez-vous a changé"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "Rendez-vous",
      "Un rendez-vous vous a été attribué"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "Votre note",
      "Un nouveau commentaire a été ajouté à votre note"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "Votre note",
      "Votre note a été marquée comme terminée"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "Votre note",
      "Votre note a été marquée comme en attente"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "Votre note",
      "De nouvelles pièces jointes ont été ajoutées à votre note"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "Notes",
      "Une nouvelle note vous a été attribuée"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "Votre note",
      "Le responsable de votre note a changé"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Votre note",
      "La date d'échéance de votre note a été avancée"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "Votre note",
      "La date d'échéance de votre note a été reportée"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "Votre note",
      "Votre note a été archivée"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "Votre note",
      "Votre note a été désarchivée"
    ],
  },
  _Langs.tr: {
    PushInterpretation.newNotification: [
      "Bildirimler",
      "Yeni bir bildiriminiz var"
    ],
    PushInterpretation.newAppointmentForYou: [
      "Randevular",
      "Yeni bir randevunuz var"
    ],
    PushInterpretation.newNoteForYou: [
      "Notlar",
      "Yeni bir notunuz var"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "Randevunuz",
      "Randevunuz daha erken bir tarihe alındı"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "Randevunuz",
      "Randevunuz daha ileri bir tarihe ertelendi"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "Randevunuz",
      "Randevunuz tamamlandı"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "Randevunuz",
      "Randevunuz iptal edildi"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "Randevunuz",
      "Randevu durumunuz değiştirildi"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "Randevular",
      "Size bir randevu atandı"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "Notunuz",
      "Notunuza yeni bir yorum eklendi"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "Notunuz",
      "Notunuz tamamlandı olarak işaretlendi"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "Notunuz",
      "Notunuz beklemede olarak işaretlendi"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "Notunuz",
      "Notunuza yeni ekler eklendi"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "Notlar",
      "Size yeni bir not atandı"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "Notunuz",
      "Notunuzun sorumlusu değişti"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Notunuz",
      "Notunuzun son tarihi daha erkene alındı"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "Notunuz",
      "Notunuzun son tarihi daha ileriye ertelendi"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "Notunuz",
      "Notunuz arşivlendi"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "Notunuz",
      "Notunuz arşivden çıkarıldı"
    ],
  },
  _Langs.it: {
    PushInterpretation.newNotification: [
      "Notifiche",
      "Hai una nuova notifica"
    ],
    PushInterpretation.newAppointmentForYou: [
      "Appuntamenti",
      "Hai un nuovo appuntamento"
    ],
    PushInterpretation.newNoteForYou: [
      "Note",
      "Hai una nuova nota"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "Il tuo appuntamento",
      "Il tuo appuntamento è stato anticipato"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "Il tuo appuntamento",
      "Il tuo appuntamento è stato posticipato"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "Il tuo appuntamento",
      "Il tuo appuntamento è completato"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "Il tuo appuntamento",
      "Il tuo appuntamento è stato annullato"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "Il tuo appuntamento",
      "Lo stato del tuo appuntamento è stato modificato"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "Appuntamenti",
      "Ti è stato assegnato un appuntamento"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "La tua nota",
      "È stato aggiunto un nuovo commento alla tua nota"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "La tua nota",
      "La tua nota è stata contrassegnata come completata"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "La tua nota",
      "La tua nota è stata contrassegnata come in attesa"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "La tua nota",
      "Sono stati aggiunti nuovi allegati alla tua nota"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "Note",
      "Ti è stata assegnata una nuova nota"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "La tua nota",
      "Il responsabile della tua nota è cambiato"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "La tua nota",
      "La data di scadenza della tua nota è stata anticipata"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "La tua nota",
      "La data di scadenza della tua nota è stata posticipata"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "La tua nota",
      "La tua nota è stata archiviata"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "La tua nota",
      "La tua nota è stata ripristinata dall'archivio"
    ],
  },
  _Langs.ur: {
    PushInterpretation.newNotification: [
      "اطلاعات",
      "آپ کے لیے ایک نئی اطلاع ہے"
    ],
    PushInterpretation.newAppointmentForYou: [
      "اپائنٹمنٹس",
      "آپ کی ایک نئی اپائنٹمنٹ ہے"
    ],
    PushInterpretation.newNoteForYou: [
      "نوٹس",
      "آپ کے لیے ایک نیا نوٹ ہے"
    ],
    PushInterpretation.appointmentDateHasBeenMovedEarlier: [
      "آپ کی اپائنٹمنٹ",
      "آپ کی اپائنٹمنٹ کا وقت پہلے کر دیا گیا ہے"
    ],
    PushInterpretation.appointmentDateHasBeenMovedLater: [
      "آپ کی اپائنٹمنٹ",
      "آپ کی اپائنٹمنٹ کا وقت مؤخر کر دیا گیا ہے"
    ],
    PushInterpretation.appointmentIsNowDone: [
      "آپ کی اپائنٹمنٹ",
      "آپ کی اپائنٹمنٹ مکمل ہو گئی ہے"
    ],
    PushInterpretation.appointmentHasBeenCancelled: [
      "آپ کی اپائنٹمنٹ",
      "آپ کی اپائنٹمنٹ منسوخ کر دی گئی ہے"
    ],
    PushInterpretation.appointmentStatusBeenChanged: [
      "آپ کی اپائنٹمنٹ",
      "آپ کی اپائنٹمنٹ کی صورتحال تبدیل کر دی گئی ہے"
    ],
    PushInterpretation.appointmentHasBeenAssignedToYou: [
      "اپائنٹمنٹس",
      "آپ کو ایک اپائنٹمنٹ تفویض کی گئی ہے"
    ],
    PushInterpretation.newCommentAddedToYourNote: [
      "آپ کا نوٹ",
      "آپ کے نوٹ میں ایک نیا تبصرہ شامل کیا گیا ہے"
    ],
    PushInterpretation.noteHasBeenMarkedAsDone: [
      "آپ کا نوٹ",
      "آپ کے نوٹ کو مکمل کے طور پر نشان زد کر دیا گیا ہے"
    ],
    PushInterpretation.noteHasBeenMarkedAsPending: [
      "آپ کا نوٹ",
      "آپ کے نوٹ کو زیر التواء کے طور پر نشان زد کر دیا گیا ہے"
    ],
    PushInterpretation.newAttachmentsAddedToYourNote: [
      "آپ کا نوٹ",
      "آپ کے نوٹ میں نئے منسلکات شامل کیے گئے ہیں"
    ],
    PushInterpretation.aNewNoteHasBeenAssignedToYou: [
      "نوٹس",
      "آپ کو ایک نیا نوٹ تفویض کیا گیا ہے"
    ],
    PushInterpretation.assigneeOnYourNoteHasChanged: [
      "آپ کا نوٹ",
      "آپ کے نوٹ کا ذمہ دار تبدیل ہو گیا ہے"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "آپ کا نوٹ",
      "آپ کے نوٹ کی مقررہ تاریخ پہلے کر دی گئی ہے"
    ],
    PushInterpretation.dueDateOnYourNoteHasBeenMovedLater: [
      "آپ کا نوٹ",
      "آپ کے نوٹ کی مقررہ تاریخ مؤخر کر دی گئی ہے"
    ],
    PushInterpretation.yourNoteHasBeenArchived: [
      "آپ کا نوٹ",
      "آپ کا نوٹ آرکائیو کر دیا گیا ہے"
    ],
    PushInterpretation.yourNoteHasBeenUnarchived: [
      "آپ کا نوٹ",
      "آپ کا نوٹ آرکائیو سے نکال دیا گیا ہے"
    ],
  },
};
