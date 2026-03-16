/**
 * Mocking the Enums as Objects
 */
const PushInterpetation = {
    newAppointmentForYou: "newAppointmentForYou",
    newNoteForYou: "newNoteForYou",
    newNotification: "newNotification",
    appointmentDateHasBeenMovedEarlier: "appointmentDateHasBeenMovedEarlier",
    appointmentDateHasBeenMovedLater: "appointmentDateHasBeenMovedLater",
    appointmentIsNowDone: "appointmentIsNowDone",
    appointmentHasBeenCancelled: "appointmentHasBeenCancelled",
    appointmentStatusBeenChanged: "appointmentStatusBeenChanged",
    appointmentHasBeenAssignedToYou: "appointmentHasBeenAssignedToYou",
    newCommentAddedToYourNote: "newCommentAddedToYourNote",
    noteHasBeenMarkedAsDone: "noteHasBeenMarkedAsDone",
    noteHasBeenMarkedAsPending: "noteHasBeenMarkedAsPending",
    newAttachmentsAddedToYourNote: "newAttachmentsAddedToYourNote",
    aNewNoteHasBeenAssignedToYou: "aNewNoteHasBeenAssignedToYou",
    assigneeOnYourNoteHasChanged: "assigneeOnYourNoteHasChanged",
    dueDateOnYourNoteHasBeenMovedEarlier: "dueDateOnYourNoteHasBeenMovedEarlier",
    dueDateOnYourNoteHasBeenMovedLater: "dueDateOnYourNoteHasBeenMovedLater",
    yourNoteHasBeenArchived: "yourNoteHasBeenArchived",
    yourNoteHasBeenUnarchived: "yourNoteHasBeenUnarchived",
};

const Langs = { en: "en", es: "es", ar: "ar" };

export class PushData {
    constructor({
        store,
        id,
        readableIdentifier,
        isCreation,
        isUpdate,
        updatedFields,
        oldVals,
        newVals,
        targetID,
    }) {
        this.store = store;
        this.id = id;
        this.readableIdentifier = readableIdentifier;
        this.isCreation = isCreation;
        this.isUpdate = isUpdate;
        this.updatedFields = updatedFields;
        this.oldVals = oldVals;
        this.newVals = newVals;
        this.targetID = targetID;
    }

    displayTuple() {
        const interpretation = this._interpret();
        const code = self.lang || "en";

        const lang = code === "en" ? Langs.en : code === "ar" ? Langs.ar : Langs.es;

        // Get a shallow copy of the translation array so we don't mutate the original map
        const tuple = [...translations[lang][interpretation]];
        tuple[1] = `${tuple[1]}: ${this.readableIdentifier}`;
        return tuple;
    }

    /**
     * Returns [oldVal, newVal]
     */
    _valsTuple(field) {
        const i = this.updatedFields.indexOf(field);
        return [this.oldVals[i], this.newVals[i]];
    }

    _interpret() {
        if (this.isCreation && this.store === "appointments") {
            return PushInterpetation.newAppointmentForYou;
        }

        if (this.isCreation && this.store === "notes") {
            return PushInterpetation.newNoteForYou;
        }

        if (this.isUpdate && this.store === "appointments") {
            if (this.updatedFields.includes("date")) {
                const vals = this._valsTuple("date");
                return vals[0] > vals[1]
                    ? PushInterpetation.appointmentDateHasBeenMovedEarlier
                    : PushInterpetation.appointmentDateHasBeenMovedLater;
            }
            if (this.updatedFields.includes("isDone")) {
                const vals = this._valsTuple("isDone");
                return vals[1] === true
                    ? PushInterpetation.appointmentIsNowDone
                    : PushInterpetation.appointmentStatusBeenChanged;
            }
            if (this.updatedFields.includes("archived")) {
                const vals = this._valsTuple("archived");
                return vals[1] === true
                    ? PushInterpetation.appointmentHasBeenCancelled
                    : PushInterpetation.appointmentStatusBeenChanged;
            }
            if (this.updatedFields.includes("operatorsIDs")) {
                const newOperators = this.newVals[this.updatedFields.indexOf("operatorsIDs")];
                return newOperators.includes(this.targetID)
                    ? PushInterpetation.appointmentHasBeenAssignedToYou
                    : PushInterpetation.appointmentStatusBeenChanged;
            }
        }

        if (this.isUpdate && this.store === "notes") {
            if (this.updatedFields.includes("comments")) {
                return PushInterpetation.newCommentAddedToYourNote;
            }
            if (this.updatedFields.includes("attachments")) {
                return PushInterpetation.newAttachmentsAddedToYourNote;
            }
            if (this.updatedFields.includes("done")) {
                const vals = this._valsTuple("done");
                return vals[1] === true
                    ? PushInterpetation.noteHasBeenMarkedAsDone
                    : PushInterpetation.noteHasBeenMarkedAsPending;
            }
            if (this.updatedFields.includes("assignedTo")) {
                const val = this.newVals[this.updatedFields.indexOf("assignedTo")];
                return val === this.targetID
                    ? PushInterpetation.aNewNoteHasBeenAssignedToYou
                    : PushInterpetation.assigneeOnYourNoteHasChanged;
            }
            if (this.updatedFields.includes("dueDate")) {
                const vals = this._valsTuple("dueDate");
                if (vals[0] > vals[1]) return PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier;
                if (vals[0] < vals[1]) return PushInterpetation.dueDateOnYourNoteHasBeenMovedLater;
            }
            if (this.updatedFields.includes("archived")) {
                const vals = this._valsTuple("archived");
                return vals[1] === true
                    ? PushInterpetation.yourNoteHasBeenArchived
                    : PushInterpetation.yourNoteHasBeenUnarchived;
            }
        }

        return PushInterpetation.newNotification;
    }

    toJson() {
        return {
            store: this.store,
            id: this.id,
            readableIdentifier: this.readableIdentifier,
            isCreation: this.isCreation,
            isUpdate: this.isUpdate,
            updatedFields: this.updatedFields,
            oldVals: this.oldVals,
            newVals: this.newVals,
            targetID: this.targetID,
        };
    }

    static fromJson(json) {
        return new PushData({
            store: json.store,
            id: json.id,
            readableIdentifier: json.readableIdentifier,
            isCreation: json.isCreation,
            isUpdate: json.isUpdate,
            updatedFields: Array.from(json.updatedFields),
            oldVals: Array.from(json.oldVals),
            newVals: Array.from(json.newVals),
            targetID: json.targetID,
        });
    }
}

/**
 * Translations Map
 */
const translations = {
    [Langs.en]: {
        [PushInterpetation.newNotification]: ["Notifications", "You have a new notification"],
        [PushInterpetation.newAppointmentForYou]: ["Appointments", "You have a new appointment"],
        [PushInterpetation.newNoteForYou]: ["Notes", "You have a new note"],
        [PushInterpetation.appointmentDateHasBeenMovedEarlier]: ["Your appointment", "Your appointments has been moved earlier"],
        [PushInterpetation.appointmentDateHasBeenMovedLater]: ["Your appointment", "Your appointments has been moved later"],
        [PushInterpetation.appointmentIsNowDone]: ["Your appointment", "Your appointment is now done"],
        [PushInterpetation.appointmentHasBeenCancelled]: ["Your appointment", "Your appointment has been cancelled"],
        [PushInterpetation.appointmentStatusBeenChanged]: ["Your appointment", "Your appointment status has been changed"],
        [PushInterpetation.appointmentHasBeenAssignedToYou]: ["Appointments", "An appointment has been assigned to you"],
        [PushInterpetation.newCommentAddedToYourNote]: ["Your note", "A new comment has been added to your note"],
        [PushInterpetation.noteHasBeenMarkedAsDone]: ["Your note", "Your note has been marked as done"],
        [PushInterpetation.noteHasBeenMarkedAsPending]: ["Your note", "Your note has been marked as pending"],
        [PushInterpetation.newAttachmentsAddedToYourNote]: ["Your note", "New attachments have been added to your note"],
        [PushInterpetation.aNewNoteHasBeenAssignedToYou]: ["Notes", "A new note has been assigned to you"],
        [PushInterpetation.assigneeOnYourNoteHasChanged]: ["Your note", "The assignee on your note has changed"],
        [PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Your note", "The due date on your note has been moved earlier"],
        [PushInterpetation.dueDateOnYourNoteHasBeenMovedLater]: ["Your note", "The due date on your note has been moved later"],
        [PushInterpetation.yourNoteHasBeenArchived]: ["Your note", "Your note has been archived"],
        [PushInterpetation.yourNoteHasBeenUnarchived]: ["Your note", "Your note has been unarchived"],
    },
    [Langs.ar]: {
        [PushInterpetation.newNotification]: ["الإشعارات", "لديك إشعار جديد"],
        [PushInterpetation.newAppointmentForYou]: ["المواعيد", "لديك موعد جديد"],
        [PushInterpetation.newNoteForYou]: ["الملاحظات", "لديك ملاحظة جديدة"],
        [PushInterpetation.appointmentDateHasBeenMovedEarlier]: ["موعدك", "تم نقل موعدك إلى وقت أبكر"],
        [PushInterpetation.appointmentDateHasBeenMovedLater]: ["موعدك", "تم نقل موعدك إلى وقت لاحق"],
        [PushInterpetation.appointmentIsNowDone]: ["موعدك", "تم إنجاز موعدك"],
        [PushInterpetation.appointmentHasBeenCancelled]: ["موعدك", "تم إلغاء موعدك"],
        [PushInterpetation.appointmentStatusBeenChanged]: ["موعدك", "تم تغيير حالة موعدك"],
        [PushInterpetation.appointmentHasBeenAssignedToYou]: ["المواعيد", "تم تعيين موعد لك"],
        [PushInterpetation.newCommentAddedToYourNote]: ["ملاحظتك", "تم إضافة تعليق جديد إلى ملاحظتك"],
        [PushInterpetation.noteHasBeenMarkedAsDone]: ["ملاحظتك", "تم تأشير ملاحظتك كمنجزة"],
        [PushInterpetation.noteHasBeenMarkedAsPending]: ["ملاحظتك", "تم تأشير ملاحظتك كمعلقة"],
        [PushInterpetation.newAttachmentsAddedToYourNote]: ["ملاحظتك", "تم إضافة مرفقات جديدة إلى ملاحظتك"],
        [PushInterpetation.aNewNoteHasBeenAssignedToYou]: ["الملاحظات", "تم تعيين ملاحظة جديدة لك"],
        [PushInterpetation.assigneeOnYourNoteHasChanged]: ["ملاحظتك", "تم تغيير المسؤول عن ملاحظتك"],
        [PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier]: ["ملاحظتك", "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت أبكر"],
        [PushInterpetation.dueDateOnYourNoteHasBeenMovedLater]: ["ملاحظتك", "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت لاحق"],
        [PushInterpetation.yourNoteHasBeenArchived]: ["ملاحظتك", "تم أرشفة ملاحظتك"],
        [PushInterpetation.yourNoteHasBeenUnarchived]: ["ملاحظتك", "تم إلغاء أرشفة ملاحظتك"],
    },
    [Langs.es]: {
        [PushInterpetation.newNotification]: ["Notificaciones", "Tienes una nueva notificación"],
        [PushInterpetation.newAppointmentForYou]: ["Citas", "Tienes una nueva cita"],
        [PushInterpetation.newNoteForYou]: ["Notas", "Tienes una nueva nota"],
        [PushInterpetation.appointmentDateHasBeenMovedEarlier]: ["Tu cita", "Tu cita ha sido movida a una fecha anterior"],
        [PushInterpetation.appointmentDateHasBeenMovedLater]: ["Tu cita", "Tu cita ha sido movida a una fecha posterior"],
        [PushInterpetation.appointmentIsNowDone]: ["Tu cita", "Tu cita ha sido completada"],
        [PushInterpetation.appointmentHasBeenCancelled]: ["Tu cita", "Tu cita ha sido cancelada"],
        [PushInterpetation.appointmentStatusBeenChanged]: ["Tu cita", "El estado de tu cita ha sido cambiado"],
        [PushInterpetation.appointmentHasBeenAssignedToYou]: ["Citas", "Una cita ha sido asignada a ti"],
        [PushInterpetation.newCommentAddedToYourNote]: ["Tu nota", "Se ha añadido un nuevo comentario a tu nota"],
        [PushInterpetation.noteHasBeenMarkedAsDone]: ["Tu nota", "Tu nota ha sido marcada como completada"],
        [PushInterpetation.noteHasBeenMarkedAsPending]: ["Tu nota", "Tu nota ha sido marcada como pendiente"],
        [PushInterpetation.newAttachmentsAddedToYourNote]: ["Tu nota", "Se han añadido nuevos archivos adjuntos a tu nota"],
        [PushInterpetation.aNewNoteHasBeenAssignedToYou]: ["Notas", "Se te ha asignado una nueva nota"],
        [PushInterpetation.assigneeOnYourNoteHasChanged]: ["Tu nota", "El responsable de tu nota ha cambiado"],
        [PushInterpetation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Tu nota", "La fecha de vencimiento de tu nota ha sido movida a una fecha anterior"],
        [PushInterpetation.dueDateOnYourNoteHasBeenMovedLater]: ["Tu nota", "La fecha de vencimiento de tu nota ha sido movida a una fecha posterior"],
        [PushInterpetation.yourNoteHasBeenArchived]: ["Tu nota", "Tu nota ha sido archivada"],
        [PushInterpetation.yourNoteHasBeenUnarchived]: ["Tu nota", "Tu nota ha sido desarchivada"],
    }
};