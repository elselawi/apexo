@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_gallery.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

/// The gallery adds no record of its own: it is exactly the union of both image
/// lists, each visit once, newest first.
void main() {
  late List<int> originalPerms;

  setUp(() {
    originalPerms = login.savedPermissions;
    // The store filters visits by permission, so full perms are needed to see them.
    login.savedPermissions = Perm.full;
    appointments.observableMap.clear();
  });

  tearDown(() {
    login.savedPermissions = originalPerms;
    appointments.observableMap.clear();
  });

  test('the gallery lists the union of photos and X-rays, without duplicates',
      () {
    final patient = testPatient(id: 'gallery-patient');
    final photos = testAppointment(
      id: 'visit-photos',
      patientID: patient.id,
      date: DateTime(2026, 1, 10),
      imgs: ['photo.png'],
    );
    final xrays = testAppointment(
      id: 'visit-xrays',
      patientID: patient.id,
      date: DateTime(2026, 1, 11),
      dcmImgs: ['xray.dcm'],
    );
    // Both lists name this one: it is one visit, so one group.
    final both = testAppointment(
      id: 'visit-both',
      patientID: patient.id,
      date: DateTime(2026, 1, 12),
      imgs: ['before.png'],
      dcmImgs: ['before.dcm'],
    );
    final withoutFiles = testAppointment(
      id: 'visit-without-files',
      patientID: patient.id,
      date: DateTime(2026, 1, 13),
      postOpNotes: 'nothing to show',
    );
    appointments.setAll([photos, xrays, both, withoutFiles]);
    appointments.set(testAppointment(
      id: 'other-patient-visit',
      patientID: 'another-patient',
      date: DateTime(2026, 1, 14),
      imgs: ['someone-else.png'],
    ));

    final visits = patientGalleryVisits(patient);
    final ids = visits.map((visit) => visit.id).toList();

    expect(
      ids.toSet(),
      {
        ...patient.appointmentsWithImages.map((visit) => visit.id),
        ...patient.appointmentsWithDcmImgs.map((visit) => visit.id),
      },
      reason: 'the gallery is the union of both image lists',
    );
    expect(ids.toSet().length, ids.length, reason: 'no visit is listed twice');
    expect(ids, ['visit-both', 'visit-xrays', 'visit-photos'],
        reason: 'newest visit first, and a visit without files is not a group');
  });

  test('the gallery is empty for a patient whose visits hold no files', () {
    final patient = testPatient(id: 'gallery-empty-patient');
    appointments.set(testAppointment(
      id: 'visit-text-only',
      patientID: patient.id,
      preOpNotes: 'consultation only',
    ));

    expect(patientGalleryVisits(patient), isEmpty);
  });
}
