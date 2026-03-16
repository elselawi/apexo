import 'package:apexo/services/localization/locale.dart';

/// ---------------------------------------------------------------------------
///  !!!! IMPORTANT !!!!
/// when editing this file you must also edit the fcm/push_data.js file
/// since data can be generated here and consumed there by the web app
/// ---------------------------------------------------------------------------
///

/// This class is used to represent the data that is sent to the user when a push notification is received
/// It is used to display the notification to the user in a human-readable format
/// It is also used to navigate to the correct screen when the user clicks on the notification
class PushData {
  String store;
  String id;
  String readableIdentifier;
  String targetID;
  bool isCreation;
  bool isUpdate;
  List<String> updatedFields;
  List<dynamic> oldVals;
  List<dynamic> newVals;

  PushData({
    required this.store,
    required this.id,
    required this.readableIdentifier,
    required this.isCreation,
    required this.isUpdate,
    required this.updatedFields,
    required this.oldVals,
    required this.newVals,
    required this.targetID,
  });

  List<String> displayTuple() {
    final interpetation = _interpet();
    final code = locale.s.$code;
    final lang = code == "en"
        ? _Langs.en
        : code == "ar"
            ? _Langs.ar
            : _Langs.es;
    final tuple = _translations[lang]![interpetation]!;
    tuple[1] = "${tuple[1]}: $readableIdentifier";
    return tuple;
  }

  (dynamic, dynamic) _valsTuple(String field) {
    final i = updatedFields.indexOf(field);
    return (oldVals[i], newVals[i]);
  }

  PushInterpetation _interpet() {
    if (isCreation && store == "appointments") {
      return PushInterpetation.newAppointmentForYou;
    }

    if (isCreation && store == "notes") {
      return PushInterpetation.newNoteForYou;
    }

    if (isUpdate && store == "appointments") {
      if (updatedFields.contains("date")) {
        final vals = _valsTuple("date");
        if (vals.$1 > vals.$2) {
          return PushInterpetation.appointmentDateHasBeenMovedEarlier;
        } else {
          return PushInterpetation.appointmentDateHasBeenMovedLater;
        }
      }
      if (updatedFields.contains("isDone")) {
        final vals = _valsTuple("isDone");
        if (vals.$2 == true) {
          return PushInterpetation.appointmentIsNowDone;
        } else {
          return PushInterpetation.appointmentStatusBeenChanged;
        }
      }
      if (updatedFields.contains("archived")) {
        final vals = _valsTuple("archived");
        if (vals.$2 == true) {
          return PushInterpetation.appointmentHasBeenCancelled;
        } else {
          return PushInterpetation.appointmentStatusBeenChanged;
        }
      }
      if (updatedFields.contains("operatorsIDs")) {
        final newOperators = newVals[updatedFields.indexOf("operatorsIDs")];
        if (newOperators.contains(targetID)) {
          return PushInterpetation.appointmentHasBeenAssignedToYou;
        } else {
          return PushInterpetation.appointmentStatusBeenChanged;
        }
      }
    }

    if (isUpdate && store == "notes") {
      if (updatedFields.contains("comments")) {
        return PushInterpetation.newCommentAddedToYourNote;
      }
      if (updatedFields.contains("attachments")) {
        return PushInterpetation.newAttachmentsAddedToYourNote;
      }
      if (updatedFields.contains("done")) {
        final vals = _valsTuple("done");
        if (vals.$2 == true) {
          return PushInterpetation.noteHasBeenMarkedAsDone;
        } else {
          return PushInterpetation.noteHasBeenMarkedAsPending;
        }
      }
      if (updatedFields.contains("assignedTo")) {
        final val = newVals[updatedFields.indexOf("assignedTo")];
        if (val == targetID) {
          return PushInterpetation.aNewNoteHasBeenAssignedToYou;
        } else {
          return PushInterpetation.assigneeOnYourNoteHasChanged;
        }
      }
      if (updatedFields.contains("dueDate")) {
        final vals = _valsTuple("dueDate");
        if (vals.$1 > vals.$2) {
          return PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier;
        } else if (vals.$1 < vals.$2) {
          return PushInterpetation.dueDateOnYourNoteHasBeenMovedLater;
        }
      }
      if (updatedFields.contains("archived")) {
        final vals = _valsTuple("archived");
        if (vals.$2 == true) {
          return PushInterpetation.yourNoteHasBeenArchived;
        } else {
          return PushInterpetation.yourNoteHasBeenUnarchived;
        }
      }
    }

    return PushInterpetation.newNotification;
  }

  Map<String, dynamic> toJson() {
    return {
      "store": store,
      "id": id,
      "readableIdentifier": readableIdentifier,
      "isCreation": isCreation,
      "isUpdate": isUpdate,
      "updatedFields": updatedFields,
      "oldVals": oldVals,
      "newVals": newVals,
      "targetID": targetID
    };
  }

  factory PushData.fromJson(Map<String, dynamic> json) {
    return PushData(
      store: json["store"],
      id: json["id"],
      readableIdentifier: json["readableIdentifier"],
      isCreation: json["isCreation"],
      isUpdate: json["isUpdate"],
      updatedFields: List<String>.from(json["updatedFields"]),
      oldVals: List<dynamic>.from(json["oldVals"]),
      newVals: List<dynamic>.from(json["newVals"]),
      targetID: json["targetID"],
    );
  }
}

enum PushInterpetation {
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

final Map<_Langs, Map<PushInterpetation, List<String>>> _translations = {
  _Langs.en: {
    PushInterpetation.newNotification: [
      "Notifications",
      "You have a new notification"
    ],
    PushInterpetation.newAppointmentForYou: [
      "Appointments",
      "You have a new appointment"
    ],
    PushInterpetation.newNoteForYou: ["Notes", "You have a new note"],
    PushInterpetation.appointmentDateHasBeenMovedEarlier: [
      "Your appointment",
      "Your appointments has been moved earlier"
    ],
    PushInterpetation.appointmentDateHasBeenMovedLater: [
      "Your appointment",
      "Your appointments has been moved later"
    ],
    PushInterpetation.appointmentIsNowDone: [
      "Your appointment",
      "Your appointment is now done"
    ],
    PushInterpetation.appointmentHasBeenCancelled: [
      "Your appointment",
      "Your appointment has been cancelled"
    ],
    PushInterpetation.appointmentStatusBeenChanged: [
      "Your appointment",
      "Your appointment status has been changed"
    ],
    PushInterpetation.appointmentHasBeenAssignedToYou: [
      "Appointments",
      "An appointment has been assigned to you"
    ],
    PushInterpetation.newCommentAddedToYourNote: [
      "Your note",
      "A new comment has been added to your note"
    ],
    PushInterpetation.noteHasBeenMarkedAsDone: [
      "Your note",
      "Your note has been marked as done"
    ],
    PushInterpetation.noteHasBeenMarkedAsPending: [
      "Your note",
      "Your note has been marked as pending"
    ],
    PushInterpetation.newAttachmentsAddedToYourNote: [
      "Your note",
      "New attachments have been added to your note"
    ],
    PushInterpetation.aNewNoteHasBeenAssignedToYou: [
      "Notes",
      "A new note has been assigned to you"
    ],
    PushInterpetation.assigneeOnYourNoteHasChanged: [
      "Your note",
      "The assignee on your note has changed"
    ],
    PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Your note",
      "The due date on your note has been moved earlier"
    ],
    PushInterpetation.dueDateOnYourNoteHasBeenMovedLater: [
      "Your note",
      "The due date on your note has been moved later"
    ],
    PushInterpetation.yourNoteHasBeenArchived: [
      "Your note",
      "Your note has been archived"
    ],
    PushInterpetation.yourNoteHasBeenUnarchived: [
      "Your note",
      "Your note has been unarchived"
    ],
  },
  _Langs.ar: {
    PushInterpetation.newNotification: ["الإشعارات", "لديك إشعار جديد"],
    PushInterpetation.newAppointmentForYou: ["المواعيد", "لديك موعد جديد"],
    PushInterpetation.newNoteForYou: ["الملاحظات", "لديك ملاحظة جديدة"],
    PushInterpetation.appointmentDateHasBeenMovedEarlier: [
      "موعدك",
      "تم نقل موعدك إلى وقت أبكر"
    ],
    PushInterpetation.appointmentDateHasBeenMovedLater: [
      "موعدك",
      "تم نقل موعدك إلى وقت لاحق"
    ],
    PushInterpetation.appointmentIsNowDone: ["موعدك", "تم إنجاز موعدك"],
    PushInterpetation.appointmentHasBeenCancelled: ["موعدك", "تم إلغاء موعدك"],
    PushInterpetation.appointmentStatusBeenChanged: [
      "موعدك",
      "تم تغيير حالة موعدك"
    ],
    PushInterpetation.appointmentHasBeenAssignedToYou: [
      "المواعيد",
      "تم تعيين موعد لك"
    ],
    PushInterpetation.newCommentAddedToYourNote: [
      "ملاحظتك",
      "تم إضافة تعليق جديد إلى ملاحظتك"
    ],
    PushInterpetation.noteHasBeenMarkedAsDone: [
      "ملاحظتك",
      "تم تأشير ملاحظتك كمنجزة"
    ],
    PushInterpetation.noteHasBeenMarkedAsPending: [
      "ملاحظتك",
      "تم تأشير ملاحظتك كمعلقة"
    ],
    PushInterpetation.newAttachmentsAddedToYourNote: [
      "ملاحظتك",
      "تم إضافة مرفقات جديدة إلى ملاحظتك"
    ],
    PushInterpetation.aNewNoteHasBeenAssignedToYou: [
      "الملاحظات",
      "تم تعيين ملاحظة جديدة لك"
    ],
    PushInterpetation.assigneeOnYourNoteHasChanged: [
      "ملاحظتك",
      "تم تغيير المسؤول عن ملاحظتك"
    ],
    PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "ملاحظتك",
      "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت أبكر"
    ],
    PushInterpetation.dueDateOnYourNoteHasBeenMovedLater: [
      "ملاحظتك",
      "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت لاحق"
    ],
    PushInterpetation.yourNoteHasBeenArchived: ["ملاحظتك", "تم أرشفة ملاحظتك"],
    PushInterpetation.yourNoteHasBeenUnarchived: [
      "ملاحظتك",
      "تم إلغاء أرشفة ملاحظتك"
    ],
  },
  _Langs.es: {
    PushInterpetation.newNotification: [
      "Notificaciones",
      "Tienes una nueva notificación"
    ],
    PushInterpetation.newAppointmentForYou: ["Citas", "Tienes una nueva cita"],
    PushInterpetation.newNoteForYou: ["Notas", "Tienes una nueva nota"],
    PushInterpetation.appointmentDateHasBeenMovedEarlier: [
      "Tu cita",
      "Tu cita ha sido movida a una fecha anterior"
    ],
    PushInterpetation.appointmentDateHasBeenMovedLater: [
      "Tu cita",
      "Tu cita ha sido movida a una fecha posterior"
    ],
    PushInterpetation.appointmentIsNowDone: [
      "Tu cita",
      "Tu cita ha sido completada"
    ],
    PushInterpetation.appointmentHasBeenCancelled: [
      "Tu cita",
      "Tu cita ha sido cancelada"
    ],
    PushInterpetation.appointmentStatusBeenChanged: [
      "Tu cita",
      "El estado de tu cita ha sido cambiado"
    ],
    PushInterpetation.appointmentHasBeenAssignedToYou: [
      "Citas",
      "Una cita ha sido asignada a ti"
    ],
    PushInterpetation.newCommentAddedToYourNote: [
      "Tu nota",
      "Se ha añadido un nuevo comentario a tu nota"
    ],
    PushInterpetation.noteHasBeenMarkedAsDone: [
      "Tu nota",
      "Tu nota ha sido marcada como completada"
    ],
    PushInterpetation.noteHasBeenMarkedAsPending: [
      "Tu nota",
      "Tu nota ha sido marcada como pendiente"
    ],
    PushInterpetation.newAttachmentsAddedToYourNote: [
      "Tu nota",
      "Se han añadido nuevos archivos adjuntos a tu nota"
    ],
    PushInterpetation.aNewNoteHasBeenAssignedToYou: [
      "Notas",
      "Se te ha asignado una nueva nota"
    ],
    PushInterpetation.assigneeOnYourNoteHasChanged: [
      "Tu nota",
      "El responsable de tu nota ha cambiado"
    ],
    PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier: [
      "Tu nota",
      "La fecha de vencimiento de tu nota ha sido movida a una fecha anterior"
    ],
    PushInterpetation.dueDateOnYourNoteHasBeenMovedLater: [
      "Tu nota",
      "La fecha de vencimiento de tu nota ha sido movida a una fecha posterior"
    ],
    PushInterpetation.yourNoteHasBeenArchived: [
      "Tu nota",
      "Tu nota ha sido archivada"
    ],
    PushInterpetation.yourNoteHasBeenUnarchived: [
      "Tu nota",
      "Tu nota ha sido desarchivada"
    ],
  }
};
