@Tags(['serial'])
library;

import 'dart:typed_data';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';

DicomPendingImport _pending(List<DateTime> dates) {
  return DicomPendingImport(
    dicomPatientId: 'P1',
    dicomPatientName: 'Patient',
    dicomPatientNames: const {'Patient'},
    dates: dates,
    files: [
      for (final d in dates)
        DicomParsedFile(
          path: '/f_${d.toIso8601String()}.dcm',
          mtime: d,
          size: 1,
          dedupKey: 'sop:${d.toIso8601String()}',
          patientName: 'Patient',
          patientId: 'P1',
          dcmDate: d,
        ),
    ],
    matchedPatient: Patient.fromJson({'id': 'p1', 'title': 'Patient'}),
  );
}

void main() {
  setUp(() {
    login.savedPermissions = List.of(Perm.full)..[Perm.appointments] = 1;
    appointments.observableMap.clear();
  });

  tearDown(() {
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
  });

  test('matches when the account may not edit the appointment', () {
    // Receptionist/assistant: personal appointments only, and this visit
    // belongs to someone else.
    appointments.setAll([
      testAppointment(
        id: 'a1',
        patientID: 'p1',
        date: DateTime(2025, 1, 1, 10),
        operatorsIDs: ['someone-else'],
      ),
    ]);

    final ctrl = DicomController();
    addTearDown(ctrl.dispose);

    expect(appointments.docs['a1']!.locked, isTrue);
    expect(appointments.byPatient, isEmpty);

    final pi = _pending([DateTime(2025, 1, 1)]);
    expect(ctrl.matchingDates(pi, 'p1'), hasLength(1));
    expect(ctrl.mismatchingDates(pi, 'p1'), isEmpty);
  });

  test('approval attaches to an existing visit the account may not edit',
      () async {
    appointments.setAll([
      testAppointment(
        id: 'a1',
        patientID: 'p1',
        date: DateTime(2025, 1, 1, 10),
        operatorsIDs: ['someone-else'],
      ),
    ]);

    final saved = <Appointment>[];
    final importer = DicomImporter(
      useIsolate: false,
      allImportedKeys: () async => {},
      isImported: (_) async => false,
      linkFile: (_, __) async => true,
      setPatient: (_, __) async {},
      linkedPatients: () => {},
      pendingMatches: () async => {},
      unmatchedIds: () async => {},
      clearPendingMatch: (_) async {},
      clearUnmatched: (_) async {},
      scanDirectory: (_) async => <DicomFileEntry>[],
      readBytes: (_) async => Uint8List.fromList([1]),
      parseMetadata: (_) async => null,
      cacheSnapshot: () async => <String, DicomCachedMeta>{},
      cachePut: (_, __) async {},
      cachePrune: (_) async {},
      logSkipped: ({required path, required reason}) async {},
      clearSkipped: (_) async {},
      allPatients: () => [
        Patient.fromJson({'id': 'p1', 'title': 'Patient'})
      ],
      getWatchDirs: () => const <String>[],
      handleNewDcm: ({required rowID, required sourcePath}) async => 'scan.dcm',
      setAppointment: saved.add,
      ensureAppointmentPersisted: () async {},
      removeKey: (_) async => true,
    );

    final result =
        await importer.approveImport(_pending([DateTime(2025, 1, 1)]));

    expect(result.complete, isTrue);
    expect(saved, hasLength(1));
    expect(saved.single.id, 'a1');
    expect(saved.single.dcmImgs, ['scan.dcm']);
  });
}
