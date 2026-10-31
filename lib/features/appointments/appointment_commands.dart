import 'dart:convert';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';

/// The fields a visit's gallery owns: the files it uploads and deletes, and the
/// drawings made on them.
///
/// A write outside the visit's own Save may change these and nothing else — a
/// photo upload is not a save of the pre-op notes that happen to be typed into
/// the visit's draft beside it (plan §7.4).
const List<String> kVisitImageFields = <String>['imgs', 'drawings', 'dcmImgs'];

/// Bumped whenever dictation fills a visit's fields, so the open forms re-read
/// the draft they are editing.
final transcriptionEditCounter = ObservableState(0);

/// Whether the post-op record can be read for [appointment].
bool canViewPostOp(Appointment? appointment) =>
    login.perm(Perm.postOp).exact(2) ||
    (login.perm(Perm.postOp).exact(1) &&
        appointment?.operatorsIDs.contains(login.currentAccountID) == true);

/// Whether the user may change the visits operated by [operatorIDs].
///
/// An admin, whoever has full access to visits, and the visits' own operators
/// may; nobody else may. The gate for everything that writes to a visit — the
/// post-op record, its labwork order, its gallery — so that one rule cannot be
/// applied more loosely in one place than in another.
bool canEditAppointments(List<String> operatorIDs) {
  if (login.isAdmin) return true;
  if (login.perm(Perm.appointments).full) return true;
  return operatorIDs.contains(login.currentAccountID);
}

/// Applies [mutate] to the visit's **one** draft and returns the visit as it now
/// reads.
///
/// Every local change to a visit goes through here — a calendar drag, a done
/// checkbox, a labwork toggle, a tooth from the chart — so that a control
/// outside the visit's windows and a form inside them are the same edit
/// (plan §2.6a):
///
/// * If the visit is open, [mutate] runs on the session's draft — which is what
///   the user is looking at — and **the fields it changed are stored at once**
///   (`AppointmentSession.writeThrough`). The controls that call this read the
///   record from the store, so a draft-only change would look like no change at
///   all: a ticked box left unticked, a dragged visit snapping back. Storing only
///   what the mutation touched leaves the rest of the draft (half-typed notes,
///   teeth) unsaved, for the visit's own Save.
/// * If nothing is open, [mutate] runs on a copy that is written to the store at
///   once — there is no draft to disagree with.
///
/// Writing the whole draft is safe in the second case only: with no session open
/// there is no other draft of this visit to undo.
Appointment appointmentCommand(
  String id,
  void Function(Appointment appointment) mutate,
) {
  final session = appointmentSessions.get(id);
  if (session != null && !session.isDisposed) {
    session.writeThrough(mutate);
    return session.item;
  }
  final stored = appointments.get(id);
  if (stored == null) {
    throw StateError('Appointment $id is not stored');
  }
  final copy = Appointment.fromJson(
    jsonDecode(jsonEncode(stored.toJson())) as Map<String, dynamic>,
  );
  mutate(copy);
  appointments.set(appointments.modeling(copy.toJson()));
  return copy;
}

/// The visit as it reads **now**: its open draft if one is, the stored record
/// otherwise.
///
/// A control that names a visit from outside its own windows must read it
/// through here. The [Appointment] such a control was built with is the copy its
/// surface was laid out from; an edit made through [appointmentCommand] — a tick
/// in an operators list, a calendar drag — reaches the draft and the store, and
/// that copy is left saying what it said before.
Appointment? liveAppointment(String id) {
  final session = appointmentSessions.get(id);
  if (session != null && !session.isDisposed) return session.item;
  return appointments.get(id);
}

/// Writes the image fields [visit] carries into the visit as it is stored,
/// leaving every other stored field exactly as it is.
///
/// This is the gallery's write, not the visit's: the rest of the draft — the
/// notes, the price, the teeth — stays unsaved until the visit's own Save runs,
/// so an upload can neither store nor acknowledge work it did not do.
///
/// A visit that is not stored at all has no record to keep anything of: the
/// whole draft goes in, because the gallery that calls this only opens for a
/// stored visit (`PanelWindow.onlyIfSaved`).
void writeVisitImages(Appointment visit) {
  // A session's draft is the visit the user is looking at: keep its image fields
  // in step with the ones just written, so the panel that reopens does not show
  // the photos as they were before the upload.
  final session = appointmentSessions.get(visit.id);
  if (session != null &&
      !session.isDisposed &&
      !identical(session.item, visit)) {
    session.item
      ..imgs = List<String>.of(visit.imgs)
      ..drawings = Map<String, String>.of(visit.drawings)
      ..dcmImgs = List<String>.of(visit.dcmImgs);
    session.markFieldsSaved(kVisitImageFields);
  }

  final stored = appointments.get(visit.id);
  final json = stored == null
      ? visit.toJson()
      : jsonDecode(jsonEncode(stored.toJson())) as Map<String, dynamic>;
  final current = visit.toJson();
  for (final field in kVisitImageFields) {
    if (current.containsKey(field)) {
      json[field] = current[field];
    } else {
      // A field back at its model's default is absent from `toJson`, so writing
      // it back means dropping the key — otherwise deleting the last photo
      // would leave the stored list in place.
      json.remove(field);
    }
  }
  appointments.set(appointments.modeling(json));
}
