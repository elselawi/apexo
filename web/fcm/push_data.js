/**
 * The web's reading of a push payload.
 *
 * This one file mirrors *two* Dart files, because the web app only ever
 * **displays** a payload — nothing here produces one, and JavaScript has no
 * extension members to hang a method on a class from another file:
 *
 *   * `lib/services/notifications/push_data.dart` — the JSON field names and
 *     `fromJson`.
 *   * `lib/services/notifications/push_interpretation.dart` — `_interpret()`,
 *     `displayTuple()` and the translations, *including their fallbacks*: a
 *     payload the Dart side would call uninterpretable must read as the generic
 *     notice here too, or the same push says two different things on two
 *     clients.
 *
 * Deliberately absent, because there is no producer on this side:
 * `PushData.fromChange`, `notifiableFields` and `sameNotifiableValue` (see
 * `lib/services/notifications/notifiable_fields.dart`). A field added, renamed
 * or removed in the Dart payload has to be added, renamed or removed here.
 */

/**
 * Mocking the Enums as Objects
 */
const PushInterpretation = {
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
        targetIDs,
    }) {
        this.store = store;
        this.id = id;
        this.readableIdentifier = readableIdentifier;
        this.isCreation = isCreation;
        this.isUpdate = isUpdate;
        this.updatedFields = updatedFields;
        this.oldVals = oldVals;
        this.newVals = newVals;
        this.targetIDs = targetIDs;

        // Whether an uninterpretable payload has already been reported for this
        // datum. `displayTuple()` is called again for the same payload — the
        // notification click handler re-reads it — so the diagnosis is reported
        // once and not once per call. Mirrors `PushData.uninterpretableReported`.
        this.uninterpretableReported = false;
    }

    displayTuple() {
        const interpretation = this._interpret();
        const code = self.lang || "en";

        const lang = code === "en" ? Langs.en : code === "ar" ? Langs.ar : Langs.es;

        // Shallow copy to prevent mutating the shared translation map
        const tuple = [...translations[lang][interpretation]];
        tuple[1] = `${tuple[1]}: ${this.readableIdentifier}`;
        return tuple;
    }

    /**
     * Returns [oldVal, newVal].
     *
     * Both are `null` when the payload does not carry the value. This is not a
     * defensive nicety: `updatedFields`, `oldVals` and `newVals` are three
     * independent lists on the wire, and this reads a payload a *remote* sender
     * produced, so a short list or a missing before-side must degrade to
     * "unknown" rather than throw or — worse — report a direction that is not
     * there.
     */
    _valsTuple(field) {
        const i = this.updatedFields.indexOf(field);
        if (i < 0) return [null, null];
        return [
            i < this.oldVals.length ? this.oldVals[i] : null,
            i < this.newVals.length ? this.newVals[i] : null,
        ];
    }

    _interpret() {
        if (this.isCreation && this.store === "appointments") {
            return PushInterpretation.newAppointmentForYou;
        }

        if (this.isCreation && this.store === "notes") {
            return PushInterpretation.newNoteForYou;
        }

        if (this.isUpdate && this.store === "appointments") {
            if (this.updatedFields.includes("date")) {
                const [oldDate, newDate] = this._valsTuple("date");
                // `date` travels as minutes since the epoch (`Appointments.toWire`),
                // so this is an integer comparison, not a chronological one, and
                // both sides must be present before there is a direction to
                // report.
                if (Number.isInteger(oldDate) && Number.isInteger(newDate)) {
                    return oldDate > newDate
                        ? PushInterpretation.appointmentDateHasBeenMovedEarlier
                        : PushInterpretation.appointmentDateHasBeenMovedLater;
                }
            }
            if (this.updatedFields.includes("isDone")) {
                const [, newVal] = this._valsTuple("isDone");
                return newVal === true
                    ? PushInterpretation.appointmentIsNowDone
                    : PushInterpretation.appointmentStatusBeenChanged;
            }
            if (this.updatedFields.includes("archived")) {
                const [, newVal] = this._valsTuple("archived");
                return newVal === true
                    ? PushInterpretation.appointmentHasBeenCancelled
                    : PushInterpretation.appointmentStatusBeenChanged;
            }
            if (this.updatedFields.includes("operatorsIDs")) {
                const [, newOperators] = this._valsTuple("operatorsIDs");
                // An array, not a string list: a payload that round-tripped
                // through JSON holds an array of anything, and a payload that
                // carries no array at all must not throw.
                if (
                    Array.isArray(newOperators) &&
                    newOperators.includes(self.currentAccountID)
                ) {
                    return PushInterpretation.appointmentHasBeenAssignedToYou;
                } else {
                    return PushInterpretation.appointmentStatusBeenChanged;
                }
            }
        }

        if (this.isUpdate && this.store === "notes") {
            if (this.updatedFields.includes("comments")) {
                return PushInterpretation.newCommentAddedToYourNote;
            }
            if (this.updatedFields.includes("attachments")) {
                return PushInterpretation.newAttachmentsAddedToYourNote;
            }
            if (this.updatedFields.includes("done")) {
                const [, newVal] = this._valsTuple("done");
                return newVal === true
                    ? PushInterpretation.noteHasBeenMarkedAsDone
                    : PushInterpretation.noteHasBeenMarkedAsPending;
            }
            if (this.updatedFields.includes("assignedTo")) {
                const [, val] = this._valsTuple("assignedTo");
                return val === self.currentAccountID
                    ? PushInterpretation.aNewNoteHasBeenAssignedToYou
                    : PushInterpretation.assigneeOnYourNoteHasChanged;
            }
            if (this.updatedFields.includes("dueDate")) {
                const [oldDue, newDue] = this._valsTuple("dueDate");
                // `dueDate` travels as hours since the epoch (`Notes.toWire`).
                if (Number.isInteger(oldDue) && Number.isInteger(newDue)) {
                    if (oldDue > newDue)
                        return PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier;
                    if (oldDue < newDue)
                        return PushInterpretation.dueDateOnYourNoteHasBeenMovedLater;
                }
            }
            if (this.updatedFields.includes("archived")) {
                const [, newVal] = this._valsTuple("archived");
                return newVal === true
                    ? PushInterpretation.yourNoteHasBeenArchived
                    : PushInterpretation.yourNoteHasBeenUnarchived;
            }
        }

        // Nothing matched. For a store we *do* notify about, an update that
        // reached this point is malformed — a field list or value list that is
        // absent, the wrong type, or shorter than the field list it indexes. The
        // wording below degrades to the generic "new notification", which is the
        // right *display* but must not hide a sender-side regression, so it is
        // reported once.
        if (
            this.isUpdate &&
            (this.store === "appointments" || this.store === "notes")
        ) {
            this._reportUninterpretable();
        }
        return PushInterpretation.newNotification;
    }

    /**
     * Reports (once per datum) that a payload could not be interpreted.
     */
    _reportUninterpretable() {
        if (this.uninterpretableReported) return;
        this.uninterpretableReported = true;
        console.warn(
            `Push payload could not be interpreted — store "${this.store}", ` +
            `isCreation=${this.isCreation}, isUpdate=${this.isUpdate}, ` +
            `updatedFields=${JSON.stringify(this.updatedFields)}, ` +
            `oldVals=${JSON.stringify(this.oldVals)}, ` +
            `newVals=${JSON.stringify(this.newVals)}. ` +
            `Falling back to the generic notification.`
        );
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
            targetIDs: this.targetIDs,
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
            targetIDs: Array.from(json.targetIDs),
        });
    }
}
/**
 * Translations Map
 */
const translations = {
    [Langs.en]: {
        [PushInterpretation.newNotification]: ["Notifications", "You have a new notification"],
        [PushInterpretation.newAppointmentForYou]: ["Appointments", "You have a new appointment"],
        [PushInterpretation.newNoteForYou]: ["Notes", "You have a new note"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["Your appointment", "Your appointments has been moved earlier"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["Your appointment", "Your appointments has been moved later"],
        [PushInterpretation.appointmentIsNowDone]: ["Your appointment", "Your appointment is now done"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["Your appointment", "Your appointment has been cancelled"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["Your appointment", "Your appointment status has been changed"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["Appointments", "An appointment has been assigned to you"],
        [PushInterpretation.newCommentAddedToYourNote]: ["Your note", "A new comment has been added to your note"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["Your note", "Your note has been marked as done"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["Your note", "Your note has been marked as pending"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["Your note", "New attachments have been added to your note"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["Notes", "A new note has been assigned to you"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["Your note", "The assignee on your note has changed"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Your note", "The due date on your note has been moved earlier"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["Your note", "The due date on your note has been moved later"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["Your note", "Your note has been archived"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["Your note", "Your note has been unarchived"],
    },
    [Langs.ar]: {
        [PushInterpretation.newNotification]: ["الإشعارات", "لديك إشعار جديد"],
        [PushInterpretation.newAppointmentForYou]: ["المواعيد", "لديك موعد جديد"],
        [PushInterpretation.newNoteForYou]: ["الملاحظات", "لديك ملاحظة جديدة"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["موعدك", "تم نقل موعدك إلى وقت أبكر"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["موعدك", "تم نقل موعدك إلى وقت لاحق"],
        [PushInterpretation.appointmentIsNowDone]: ["موعدك", "تم إنجاز موعدك"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["موعدك", "تم إلغاء موعدك"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["موعدك", "تم تغيير حالة موعدك"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["المواعيد", "تم تعيين موعد لك"],
        [PushInterpretation.newCommentAddedToYourNote]: ["ملاحظتك", "تم إضافة تعليق جديد إلى ملاحظتك"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["ملاحظتك", "تم تأشير ملاحظتك كمنجزة"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["ملاحظتك", "تم تأشير ملاحظتك كمعلقة"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["ملاحظتك", "تم إضافة مرفقات جديدة إلى ملاحظتك"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["الملاحظات", "تم تعيين ملاحظة جديدة لك"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["ملاحظتك", "تم تغيير المسؤول عن ملاحظتك"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["ملاحظتك", "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت أبكر"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["ملاحظتك", "تم نقل تاريخ الاستحقاق لملاحظتك إلى وقت لاحق"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["ملاحظتك", "تم أرشفة ملاحظتك"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["ملاحظتك", "تم إلغاء أرشفة ملاحظتك"],
    },
    [Langs.es]: {
        [PushInterpretation.newNotification]: ["Notificaciones", "Tienes una nueva notificación"],
        [PushInterpretation.newAppointmentForYou]: ["Citas", "Tienes una nueva cita"],
        [PushInterpretation.newNoteForYou]: ["Notas", "Tienes una nueva nota"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["Tu cita", "Tu cita ha sido movida a una fecha anterior"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["Tu cita", "Tu cita ha sido movida a una fecha posterior"],
        [PushInterpretation.appointmentIsNowDone]: ["Tu cita", "Tu cita ha sido completada"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["Tu cita", "Tu cita ha sido cancelada"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["Tu cita", "El estado de tu cita ha sido cambiado"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["Citas", "Una cita ha sido asignada a ti"],
        [PushInterpretation.newCommentAddedToYourNote]: ["Tu nota", "Se ha añadido un nuevo comentario a tu nota"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["Tu nota", "Tu nota ha sido marcada como completada"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["Tu nota", "Tu nota ha sido marcada como pendiente"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["Tu nota", "Se han añadido nuevos archivos adjuntos a tu nota"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["Notas", "Se te ha asignado una nueva nota"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["Tu nota", "El responsable de tu nota ha cambiado"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Tu nota", "La fecha de vencimiento de tu nota ha sido movida a una fecha anterior"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["Tu nota", "La fecha de vencimiento de tu nota ha sido movida a una fecha posterior"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["Tu nota", "Tu nota ha sido archivada"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["Tu nota", "Tu nota ha sido desarchivada"],
    }
};
