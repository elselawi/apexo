import 'dart:typed_data';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ResultImporterHarness {
  final results = <DicomApprovalResult>[];
  final List<DicomPendingImport> approved = [];
  bool shouldFail = false;

  DicomImporter build() {
    Future<bool> linkFile(String _, String __) async => true;
    Future<void> setPatient(String _, String __) async {}
    Future<String> handleNewDcm({
      required String rowID,
      required String sourcePath,
    }) async {
      if (shouldFail) throw StateError('upload failed');
      return 'scan.dcm';
    }

    return DicomImporter(
      useIsolate: false,
      allImportedKeys: () async => {},
      isImported: (_) async => false,
      linkFile: linkFile,
      setPatient: setPatient,
      linkedPatients: () => {},
      pendingMatches: () async => {},
      unmatchedIds: () async => {},
      appointmentDayMap: () => {},
      scanDirectory: (_) async => <DicomFileEntry>[],
      readBytes: (_) async => Uint8List.fromList([1]),
      parseMetadata: (_) async => null,
      cacheSnapshot: () async => <String, DicomCachedMeta>{},
      cachePut: (_, __) async {},
      cachePrune: (_) async {},
      logSkipped: ({required path, required reason}) async {},
      clearSkipped: (_) async {},
      allPatients: () => [
        Patient.fromJson({'id': 'patient-1'})
      ],
      getWatchDirs: () => const <String>[],
      handleNewDcm: handleNewDcm,
      setAppointment: (_) {},
      appointmentsForPatient: (_) => <Appointment>[],
      ensureAppointmentPersisted: () async {},
    );
  }
}

DicomPendingImport _pending({bool autoLinked = true}) {
  final file = DicomParsedFile(
    path: '/fake/scan.dcm',
    mtime: DateTime(2025, 1, 1),
    size: 1,
    dedupKey: 'sop:1',
    patientName: 'Patient',
    patientId: 'P1',
    dcmDate: DateTime(2025, 1, 1),
  );
  return DicomPendingImport(
    dicomPatientId: 'P1',
    dicomPatientName: 'Patient',
    dicomPatientNames: const {'Patient'},
    dates: [DateTime(2025, 1, 1)],
    files: [file],
    autoLinked: autoLinked,
    matchedPatient: Patient.fromJson({'id': 'patient-1'}),
  );
}

void main() {
  test('DicomApprovalResult reports complete and partial outcomes', () {
    const complete = DicomApprovalResult(
      successfulFiles: 2,
      failedFiles: [],
    );
    final file = _pending().files.single;
    final partial = DicomApprovalResult(
      successfulFiles: 1,
      failedFiles: [file],
    );

    expect(complete.complete, isTrue);
    expect(partial.complete, isFalse);
    expect(partial.failedFiles, [file]);
  });

  test('controller keeps a partial auto-linked import retryable', () async {
    final harness = _ResultImporterHarness();
    final controller = DicomController(importer: harness.build());
    addTearDown(controller.dispose);
    final pending = _pending();
    controller.pending([pending]);

    // The injected importer returns a failed result only when its upload
    // collaborator throws. This verifies the controller-level contract by
    // using a pending item that remains in the list after approval failure.
    harness.shouldFail = true;
    await controller.autoApproveLinked();

    expect(controller.pending(), hasLength(1));
    expect(controller.pending().single.files, hasLength(1));
  });
}
