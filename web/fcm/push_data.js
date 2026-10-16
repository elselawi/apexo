/**
 * The web's reading of a push payload.
 *
 * This one file mirrors *two* Dart files, because the web app only ever
 * **displays** a payload — nothing here produces one, and JavaScript has no
 * extension members to hang a method on a class from another file:
 *
 *   * `lib/core/synchronization/push_data.dart` — the JSON field names and
 *     `fromJson`.
 *   * `lib/services/notifications/push_interpretation.dart` — `_interpret()`,
 *     `displayTuple()` and the translations, *including their fallbacks*: a
 *     payload the Dart side would call uninterpretable must read as the generic
 *     notice here too, or the same push says two different things on two
 *     clients.
 *
 * Deliberately absent, because there is no producer on this side:
 * `PushData.fromChange`. A field added, renamed or removed in the Dart payload
 * has to be added, renamed or removed here.
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

const Langs = {
    en: "en",
    ar: "ar",
    es: "es",
    el: "el",
    fa: "fa",
    ku: "ku",
    fr: "fr",
    tr: "tr",
    it: "it",
    ur: "ur",
};

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
        this.store = typeof store === "string" ? store : "";
        this.id = typeof id === "string" ? id : "";
        this.readableIdentifier = typeof readableIdentifier === "string" ? readableIdentifier : "";
        this.isCreation = Boolean(isCreation);
        this.isUpdate = Boolean(isUpdate);
        this.updatedFields = Array.isArray(updatedFields) ? Array.from(updatedFields) : [];
        this.oldVals = Array.isArray(oldVals) ? Array.from(oldVals) : [];
        this.newVals = Array.isArray(newVals) ? Array.from(newVals) : [];
        this.targetIDs = Array.isArray(targetIDs) ? Array.from(targetIDs) : [];

        // Whether an uninterpretable payload has already been reported for this
        // datum. `displayTuple()` is called again for the same payload — the
        // notification click handler re-reads it — so the diagnosis is reported
        // once and not once per call. Mirrors `PushData.uninterpretableReported`.
        this.uninterpretableReported = false;
    }

    displayTuple() {
        const interpretation = this._interpret();
        const code = self.lang || "en";
        const lang = Object.prototype.hasOwnProperty.call(Langs, code) ? Langs[code] : Langs.en;
        const langMap = translations[lang] || translations[Langs.en];
        const entry = (langMap && langMap[interpretation]) || translations[Langs.en][interpretation];

        // Shallow copy to prevent mutating the shared translation map
        const tuple = [...entry];
        const identifier = typeof this.readableIdentifier === "string" ? this.readableIdentifier.trim() : "";
        if (identifier.length > 0) {
            tuple[1] = `${tuple[1]}: ${this.readableIdentifier}`;
        }
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

        const currentAccount = self.currentAccountID || self.accountId || "";

        if (this.isUpdate && this.store === "appointments") {
            if (this.updatedFields.includes("date")) {
                const [oldDate, newDate] = this._valsTuple("date");
                // `date` travels as minutes since the epoch (`Appointments.toWire`),
                // so this is an integer comparison, not a chronological one, and
                // both sides must be present before there is a direction to
                // report.
                if (typeof oldDate === "number" && Number.isFinite(oldDate) &&
                    typeof newDate === "number" && Number.isFinite(newDate)) {
                    if (oldDate > newDate) {
                        return PushInterpretation.appointmentDateHasBeenMovedEarlier;
                    }
                    if (oldDate < newDate) {
                        return PushInterpretation.appointmentDateHasBeenMovedLater;
                    }
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
                    currentAccount &&
                    Array.isArray(newOperators) &&
                    newOperators.includes(currentAccount)
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
                return currentAccount && val === currentAccount
                    ? PushInterpretation.aNewNoteHasBeenAssignedToYou
                    : PushInterpretation.assigneeOnYourNoteHasChanged;
            }
            if (this.updatedFields.includes("dueDate")) {
                const [oldDue, newDue] = this._valsTuple("dueDate");
                // `dueDate` travels as hours since the epoch (`Notes.toWire`).
                if (typeof oldDue === "number" && Number.isFinite(oldDue) &&
                    typeof newDue === "number" && Number.isFinite(newDue)) {
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
        if (!json || typeof json !== "object") {
            return new PushData({});
        }
        return new PushData({
            store: json.store,
            id: json.id,
            readableIdentifier: json.readableIdentifier,
            isCreation: json.isCreation,
            isUpdate: json.isUpdate,
            updatedFields: Array.isArray(json.updatedFields) ? Array.from(json.updatedFields) : [],
            oldVals: Array.isArray(json.oldVals) ? Array.from(json.oldVals) : [],
            newVals: Array.isArray(json.newVals) ? Array.from(json.newVals) : [],
            targetIDs: Array.isArray(json.targetIDs) ? Array.from(json.targetIDs) : [],
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
    },
    [Langs.el]: {
        [PushInterpretation.newNotification]: ["Ειδοποιήσεις", "Έχετε μια νέα ειδοποίηση"],
        [PushInterpretation.newAppointmentForYou]: ["Ραντεβού", "Έχετε ένα νέο ραντεβού"],
        [PushInterpretation.newNoteForYou]: ["Σημειώσεις", "Έχετε μια νέα σημείωση"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["Το ραντεβού σας", "Το ραντεβού σας μεταφέρθηκε νωρίτερα"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["Το ραντεβού σας", "Το ραντεβού σας μεταφέρθηκε αργότερα"],
        [PushInterpretation.appointmentIsNowDone]: ["Το ραντεβού σας", "Το ραντεβού σας ολοκληρώθηκε"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["Το ραντεβού σας", "Το ραντεβού σας ακυρώθηκε"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["Το ραντεβού σας", "Η κατάσταση του ραντεβού σας άλλαξε"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["Ραντεβού", "Σας ανατέθηκε ένα ραντεβού"],
        [PushInterpretation.newCommentAddedToYourNote]: ["Η σημείωσή σας", "Προστέθηκε νέο σχόλιο στη σημείωσή σας"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["Η σημείωσή σας", "Η σημείωσή σας σημειώθηκε ως ολοκληρωμένη"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["Η σημείωσή σας", "Η σημείωσή σας σημειώθηκε ως εκκρεμής"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["Η σημείωσή σας", "Προστέθηκαν νέα συνημμένα στη σημείωσή σας"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["Σημειώσεις", "Σας ανατέθηκε μια νέα σημείωση"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["Η σημείωσή σας", "Ο υπεύθυνος της σημείωσής σας άλλαξε"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Η σημείωσή σας", "Η ημερομηνία λήξης της σημείωσής σας μεταφέρθηκε νωρίτερα"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["Η σημείωσή σας", "Η ημερομηνία λήξης της σημείωσής σας μεταφέρθηκε αργότερα"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["Η σημείωσή σας", "Η σημείωσή σας αρχειοθετήθηκε"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["Η σημείωσή σας", "Η σημείωσή σας επανήλθε από το αρχείο"],
    },
    [Langs.fa]: {
        [PushInterpretation.newNotification]: ["اعلان‌ها", "شما یک اعلان جدید دارید"],
        [PushInterpretation.newAppointmentForYou]: ["نوبت‌ها", "شما یک نوبت جدید دارید"],
        [PushInterpretation.newNoteForYou]: ["یادداشت‌ها", "شما یک یادداشت جدید دارید"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["نوبت شما", "نوبت شما به زمان زودتری منتقل شد"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["نوبت شما", "نوبت شما به زمان دیرتری منتقل شد"],
        [PushInterpretation.appointmentIsNowDone]: ["نوبت شما", "نوبت شما انجام شد"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["نوبت شما", "نوبت شما لغو شد"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["نوبت شما", "وضعیت نوبت شما تغییر کرد"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["نوبت‌ها", "یک نوبت به شما اختصاص داده شد"],
        [PushInterpretation.newCommentAddedToYourNote]: ["یادداشت شما", "نظر جدیدی به یادداشت شما اضافه شد"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["یادداشت شما", "یادداشت شما به عنوان انجام‌شده علامت‌گذاری شد"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["یادداشت شما", "یادداشت شما به عنوان در انتظار علامت‌گذاری شد"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["یادداشت شما", "پیوست‌های جدیدی به یادداشت شما اضافه شد"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["یادداشت‌ها", "یک یادداشت جدید به شما اختصاص داده شد"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["یادداشت شما", "مسئول یادداشت شما تغییر کرد"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["یادداشت شما", "تاریخ سررسید یادداشت شما به زمان زودتری منتقل شد"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["یادداشت شما", "تاریخ سررسید یادداشت شما به زمان دیرتری منتقل شد"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["یادداشت شما", "یادداشت شما بایگانی شد"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["یادداشت شما", "یادداشت شما از بایگانی خارج شد"],
    },
    [Langs.ku]: {
        [PushInterpretation.newNotification]: ["ئاگادارکردنەوەکان", "ئاگادارکردنەوەیەکی نوێت هەیە"],
        [PushInterpretation.newAppointmentForYou]: ["مەوعیدەکان", "مەوعیدێکی نوێت هەیە"],
        [PushInterpretation.newNoteForYou]: ["تێبینییەکان", "تێبینییەکی نوێت هەیە"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["مەوعیدەکەت", "مەوعیدەکەت بۆ کاتێکی زووتر گواسترایەوە"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["مەوعیدەکەت", "مەوعیدەکەت بۆ کاتێکی درەنگتر گواسترایەوە"],
        [PushInterpretation.appointmentIsNowDone]: ["مەوعیدەکەت", "مەوعیدەکەت تەواو بوو"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["مەوعیدەکەت", "مەوعیدەکەت هەڵوەشێنرایەوە"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["مەوعیدەکەت", "دۆخی مەوعیدەکەت گۆڕا"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["مەوعیدەکان", "مەوعیدێک بۆ تۆ دیاری کرا"],
        [PushInterpretation.newCommentAddedToYourNote]: ["تێبینییەکەت", "لێدوانێکی نوێ زیاد کرا بۆ تێبینییەکەت"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["تێبینییەکەت", "تێبینییەکەت وەک تەواوبوو نیشانە کرا"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["تێبینییەکەت", "تێبینییەکەت وەک چاوەڕوانکراو نیشانە کرا"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["تێبینییەکەت", "هاوپێچی نوێ زیاد کرا بۆ تێبینییەکەت"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["تێبینییەکان", "تێبینییەکی نوێ بۆ تۆ دیاری کرا"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["تێبینییەکەت", "بەرپرسی تێبینییەکەت گۆڕا"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["تێبینییەکەت", "بەرواری کۆتایی تێبینییەکەت بۆ کاتێکی زووتر گواسترایەوە"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["تێبینییەکەت", "بەرواری کۆتایی تێبینییەکەت بۆ کاتێکی درەنگتر گواسترایەوە"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["تێبینییەکەت", "تێبینییەکەت ئەرشیف کرا"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["تێبینییەکەت", "تێبینییەکەت لە ئەرشیف دەرهێنرا"],
    },
    [Langs.fr]: {
        [PushInterpretation.newNotification]: ["Notifications", "Vous avez une nouvelle notification"],
        [PushInterpretation.newAppointmentForYou]: ["Rendez-vous", "Vous avez un nouveau rendez-vous"],
        [PushInterpretation.newNoteForYou]: ["Notes", "Vous avez une nouvelle note"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["Votre rendez-vous", "Votre rendez-vous a été avancé"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["Votre rendez-vous", "Votre rendez-vous a été reporté"],
        [PushInterpretation.appointmentIsNowDone]: ["Votre rendez-vous", "Votre rendez-vous est maintenant terminé"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["Votre rendez-vous", "Votre rendez-vous a été annulé"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["Votre rendez-vous", "Le statut de votre rendez-vous a changé"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["Rendez-vous", "Un rendez-vous vous a été attribué"],
        [PushInterpretation.newCommentAddedToYourNote]: ["Votre note", "Un nouveau commentaire a été ajouté à votre note"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["Votre note", "Votre note a été marquée comme terminée"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["Votre note", "Votre note a été marquée comme en attente"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["Votre note", "De nouvelles pièces jointes ont été ajoutées à votre note"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["Notes", "Une nouvelle note vous a été attribuée"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["Votre note", "Le responsable de votre note a changé"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Votre note", "La date d'échéance de votre note a été avancée"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["Votre note", "La date d'échéance de votre note a été reportée"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["Votre note", "Votre note a été archivée"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["Votre note", "Votre note a été désarchivée"],
    },
    [Langs.tr]: {
        [PushInterpretation.newNotification]: ["Bildirimler", "Yeni bir bildiriminiz var"],
        [PushInterpretation.newAppointmentForYou]: ["Randevular", "Yeni bir randevunuz var"],
        [PushInterpretation.newNoteForYou]: ["Notlar", "Yeni bir notunuz var"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["Randevunuz", "Randevunuz daha erken bir tarihe alındı"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["Randevunuz", "Randevunuz daha ileri bir tarihe ertelendi"],
        [PushInterpretation.appointmentIsNowDone]: ["Randevunuz", "Randevunuz tamamlandı"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["Randevunuz", "Randevunuz iptal edildi"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["Randevunuz", "Randevu durumunuz değiştirildi"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["Randevular", "Size bir randevu atandı"],
        [PushInterpretation.newCommentAddedToYourNote]: ["Notunuz", "Notunuza yeni bir yorum eklendi"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["Notunuz", "Notunuz tamamlandı olarak işaretlendi"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["Notunuz", "Notunuz beklemede olarak işaretlendi"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["Notunuz", "Notunuza yeni ekler eklendi"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["Notlar", "Size yeni bir not atandı"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["Notunuz", "Notunuzun sorumlusu değişti"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["Notunuz", "Notunuzun son tarihi daha erkene alındı"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["Notunuz", "Notunuzun son tarihi daha ileriye ertelendi"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["Notunuz", "Notunuz arşivlendi"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["Notunuz", "Notunuz arşivden çıkarıldı"],
    },
    [Langs.it]: {
        [PushInterpretation.newNotification]: ["Notifiche", "Hai una nuova notifica"],
        [PushInterpretation.newAppointmentForYou]: ["Appuntamenti", "Hai un nuovo appuntamento"],
        [PushInterpretation.newNoteForYou]: ["Note", "Hai una nuova nota"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["Il tuo appuntamento", "Il tuo appuntamento è stato anticipato"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["Il tuo appuntamento", "Il tuo appuntamento è stato posticipato"],
        [PushInterpretation.appointmentIsNowDone]: ["Il tuo appuntamento", "Il tuo appuntamento è completato"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["Il tuo appuntamento", "Il tuo appuntamento è stato annullato"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["Il tuo appuntamento", "Lo stato del tuo appuntamento è stato modificato"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["Appuntamenti", "Ti è stato assegnato un appuntamento"],
        [PushInterpretation.newCommentAddedToYourNote]: ["La tua nota", "È stato aggiunto un nuovo commento alla tua nota"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["La tua nota", "La tua nota è stata contrassegnata come completata"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["La tua nota", "La tua nota è stata contrassegnata come in attesa"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["La tua nota", "Sono stati aggiunti nuovi allegati alla tua nota"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["Note", "Ti è stata assegnata una nuova nota"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["La tua nota", "Il responsabile della tua nota è cambiato"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["La tua nota", "La data di scadenza della tua nota è stata anticipata"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["La tua nota", "La data di scadenza della tua nota è stata posticipata"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["La tua nota", "La tua nota è stata archiviata"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["La tua nota", "La tua nota è stata ripristinata dall'archivio"],
    },
    [Langs.ur]: {
        [PushInterpretation.newNotification]: ["اطلاعات", "آپ کے لیے ایک نئی اطلاع ہے"],
        [PushInterpretation.newAppointmentForYou]: ["اپائنٹمنٹس", "آپ کی ایک نئی اپائنٹمنٹ ہے"],
        [PushInterpretation.newNoteForYou]: ["نوٹس", "آپ کے لیے ایک نیا نوٹ ہے"],
        [PushInterpretation.appointmentDateHasBeenMovedEarlier]: ["آپ کی اپائنٹمنٹ", "آپ کی اپائنٹمنٹ کا وقت پہلے کر دیا گیا ہے"],
        [PushInterpretation.appointmentDateHasBeenMovedLater]: ["آپ کی اپائنٹمنٹ", "آپ کی اپائنٹمنٹ کا وقت مؤخر کر دیا گیا ہے"],
        [PushInterpretation.appointmentIsNowDone]: ["آپ کی اپائنٹمنٹ", "آپ کی اپائنٹمنٹ مکمل ہو گئی ہے"],
        [PushInterpretation.appointmentHasBeenCancelled]: ["آپ کی اپائنٹمنٹ", "آپ کی اپائنٹمنٹ منسوخ کر دی گئی ہے"],
        [PushInterpretation.appointmentStatusBeenChanged]: ["آپ کی اپائنٹمنٹ", "آپ کی اپائنٹمنٹ کی صورتحال تبدیل کر دی گئی ہے"],
        [PushInterpretation.appointmentHasBeenAssignedToYou]: ["اپائنٹمنٹس", "آپ کو ایک اپائنٹمنٹ تفویض کی گئی ہے"],
        [PushInterpretation.newCommentAddedToYourNote]: ["آپ کا نوٹ", "آپ کے نوٹ میں ایک نیا تبصرہ شامل کیا گیا ہے"],
        [PushInterpretation.noteHasBeenMarkedAsDone]: ["آپ کا نوٹ", "آپ کے نوٹ کو مکمل کے طور پر نشان زد کر دیا گیا ہے"],
        [PushInterpretation.noteHasBeenMarkedAsPending]: ["آپ کا نوٹ", "آپ کے نوٹ کو زیر التواء کے طور پر نشان زد کر دیا گیا ہے"],
        [PushInterpretation.newAttachmentsAddedToYourNote]: ["آپ کا نوٹ", "آپ کے نوٹ میں نئے منسلکات شامل کیے گئے ہیں"],
        [PushInterpretation.aNewNoteHasBeenAssignedToYou]: ["نوٹس", "آپ کو ایک نیا نوٹ تفویض کیا گیا ہے"],
        [PushInterpretation.assigneeOnYourNoteHasChanged]: ["آپ کا نوٹ", "آپ کے نوٹ کا ذمہ دار تبدیل ہو گیا ہے"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedEarlier]: ["آپ کا نوٹ", "آپ کے نوٹ کی مقررہ تاریخ پہلے کر دی گئی ہے"],
        [PushInterpretation.dueDateOnYourNoteHasBeenMovedLater]: ["آپ کا نوٹ", "آپ کے نوٹ کی مقررہ تاریخ مؤخر کر دی گئی ہے"],
        [PushInterpretation.yourNoteHasBeenArchived]: ["آپ کا نوٹ", "آپ کا نوٹ آرکائیو کر دیا گیا ہے"],
        [PushInterpretation.yourNoteHasBeenUnarchived]: ["آپ کا نوٹ", "آپ کا نوٹ آرکائیو سے نکال دیا گیا ہے"],
    },
};
