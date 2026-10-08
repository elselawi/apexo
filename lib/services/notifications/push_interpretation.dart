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

import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/utils/logger.dart';

/// The reading of a payload: the notification's title and body, as the OS
/// notification and the in-app list both want them.
extension PushDataDisplay on PushData {
  /// The title and body to show for this payload, in the app's language, with
  /// the record's readable identifier appended to the body.
  List<String> displayTuple() {
    final interpretation = _interpret();
    final code = locale.s.$code;
    final lang = code == "en"
        ? _Langs.en
        : code == "ar"
            ? _Langs.ar
            : _Langs.es;
    final tuple = [..._translations[lang]![interpretation]!];
    tuple[1] = "${tuple[1]}: $readableIdentifier";
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

  PushInterpretation _interpret() {
    if (isCreation && store == "appointments") {
      return PushInterpretation.newAppointmentForYou;
    }

    if (isCreation && store == "notes") {
      return PushInterpretation.newNoteForYou;
    }

    if (isUpdate && store == "appointments") {
      if (updatedFields.contains("date")) {
        final (oldDate, newDate) = _valsTuple("date");
        // `date` travels as minutes since the epoch (`Appointments.toWire`),
        // so this is an integer comparison, not a chronological one, and both
        // sides must be present before there is a direction to report.
        if (oldDate is int && newDate is int) {
          return oldDate > newDate
              ? PushInterpretation.appointmentDateHasBeenMovedEarlier
              : PushInterpretation.appointmentDateHasBeenMovedLater;
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
        if (newOperators is List &&
            newOperators.contains(login.currentAccountID)) {
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
        if (val == login.currentAccountID) {
          return PushInterpretation.aNewNoteHasBeenAssignedToYou;
        } else {
          return PushInterpretation.assigneeOnYourNoteHasChanged;
        }
      }
      if (updatedFields.contains("dueDate")) {
        final (oldDue, newDue) = _valsTuple("dueDate");
        // `dueDate` travels as hours since the epoch (`Notes.toWire`).
        if (oldDue is int && newDue is int) {
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

enum _Langs { en, es, ar }

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
  }
};
