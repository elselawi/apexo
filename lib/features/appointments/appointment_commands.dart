import 'dart:convert';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';

/// The fields a visit's gallery owns: it may change these outside the visit's
/// own Save, and nothing else.
const List<String> kVisitImageFields = <String>['imgs', 'drawings', 'dcmImgs'];

/// Bumped when dictation fills a visit's fields, so the open forms re-read the draft.
final transcriptionEditCounter = ObservableState(0);

/// Whether the post-op record can be read for [appointment].
bool canViewPostOp(Appointment? appointment) =>
    login.perm(Perm.postOp).exact(2) ||
    (login.perm(Perm.postOp).exact(1) &&
        appointment?.operatorsIDs.contains(login.currentAccountID) == true);

/// Whether the user may change the visits operated by [operatorIDs]: admins, full
/// appointment access, or the visit's own operators. Gate for every visit write.
bool canEditAppointments(List<String> operatorIDs) {
  if (login.isAdmin) return true;
  if (login.perm(Perm.appointments).full) return true;
  return operatorIDs.contains(login.currentAccountID);
}

/// Applies [mutate] to the visit's one draft and returns the visit as it now reads.
/// Open visit: only changed fields are stored; no session: the whole copy is.
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

/// The visit as it now reads: its open draft if one is, the stored record otherwise.
/// Controls outside the visit's windows must read it here, not from their own copy.
Appointment? liveAppointment(String id) {
  final session = appointmentSessions.get(id);
  if (session != null && !session.isDisposed) return session.item;
  return appointments.get(id);
}

/// Writes [visit]'s image fields into the stored visit, leaving every other stored
/// field as it is; an unstored visit gets the whole draft.
void writeVisitImages(Appointment visit) {
  // Keep the open session's image fields in step so a reopened panel shows the new photos.
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
      // A field at its model default is absent from `toJson`, so it must be removed
      // from the stored JSON too — otherwise deleting the last photo keeps the list.
      json.remove(field);
    }
  }
  appointments.set(appointments.modeling(json));
}
