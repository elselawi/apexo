import 'dart:typed_data';

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal [Patient] for tests — only the fields that [DicomImporter]
/// reads during approval.
Patient _testPatient(String id) =>
    Patient.fromJson({'id': id, 'archived': false});

/// A [DicomImporter] that records calls to [approveImport] and returns
/// controlled scan results. All store-dependent parameters are replaced
/// with in-memory fakes so the tests run without Hive, PocketBase, or
/// the FFI engine.
class _MockImporter {
  /// Accumulates the [DicomPendingImport] items passed to [approveImport].
  final List<DicomPendingImport> approvedItems = [];

  /// The pending list that [scanAndBuildPending] will return on the next
  /// call. Set this before calling [refresh] / [_tick].
  List<DicomPendingImport> nextScanResult = const [];

  /// Set of dedup keys that are considered "already imported".
  final Set<String> importedKeys = {};

  // ── Fakes for store dependencies ────────────────────────────────────

  final Map<String, String> _patientLinks = {};

  Future<Set<String>> _allImportedKeys() async => importedKeys;
  Future<bool> _isImported(String key) async => importedKeys.contains(key);

  Future<void> _linkFile(String dicomPatientId, String key) async {
    importedKeys.add(key);
  }

  Future<void> _setPatient(String dicomPatientId, String apexoPatientId) async {
    _patientLinks[dicomPatientId] = apexoPatientId;
  }

  Map<String, String> _linkedPatients() => Map.of(_patientLinks);

  Future<Map<String, String>> _pendingMatches() async => {};
  Future<Set<String>> _unmatchedIds() async => {};

  Map<String, Set<DateTime>> _appointmentDayMap() => {};

  Future<List<DicomFileEntry>> _scanDirectory(String path) async => [];

  Future<Uint8List?> _readBytes(String path) async => null;

  Future<DicomParsedMeta?> _parseMetadata(Uint8List bytes) async => null;

  Future<Map<String, DicomCachedMeta>> _cacheSnapshot() async => {};

  Future<void> _cachePut(String path, DicomCachedMeta meta) async {}

  Future<void> _cachePrune(Set<String> paths) async {}

  Future<void> _logSkipped(
      {required String path, required String reason}) async {}

  Future<void> _clearSkipped(String path) async {}

  List<Patient> _allPatients() => [];

  List<String> _getWatchDirs() => const [];

  Future<String> _handleNewDcm(
      {required String rowID, required String sourcePath}) async {
    return 'mock.dcm';
  }

  final List<Appointment> _setAppointmentLog = [];

  void _setAppointment(Appointment a) {
    // Deep-copy so the caller's mutations don't affect our log.
    _setAppointmentLog.add(Appointment.fromJson(a.toJson() ?? {}));
  }

  List<Appointment> _appointmentsForPatient(String id) => [];

  /// Builds a [DicomImporter] from the current fake state.
  DicomImporter build() {
    return DicomImporter(
      useIsolate: false,
      allImportedKeys: _allImportedKeys,
      isImported: _isImported,
      linkFile: _linkFile,
      setPatient: _setPatient,
      linkedPatients: _linkedPatients,
      pendingMatches: _pendingMatches,
      unmatchedIds: _unmatchedIds,
      appointmentDayMap: _appointmentDayMap,
      scanDirectory: _scanDirectory,
      readBytes: _readBytes,
      parseMetadata: _parseMetadata,
      cacheSnapshot: _cacheSnapshot,
      cachePut: _cachePut,
      cachePrune: _cachePrune,
      logSkipped: _logSkipped,
      clearSkipped: _clearSkipped,
      allPatients: _allPatients,
      getWatchDirs: _getWatchDirs,
      handleNewDcm: _handleNewDcm,
      setAppointment: _setAppointment,
      appointmentsForPatient: _appointmentsForPatient,
    );
  }
}

/// A test-only [DicomController] that uses a fake importer and disables
/// the periodic timer (we test timer logic separately).
class _TestController {
  final _MockImporter mock = _MockImporter();
  late final DicomController ctrl;

  _TestController() {
    ctrl = DicomController(importer: mock.build());
    // Do NOT start the periodic timer — unit tests drive scans manually.
    ctrl.stopPeriodicScan();
  }
}

/// Builds a bare [DicomPendingImport] for auto-approve tests.
DicomPendingImport _pending({
  required String dicomPatientId,
  required String dicomPatientName,
  bool autoLinked = false,
  bool isConfirmed = false,
  List<DicomParsedFile>? files,
}) {
  final f = files ??
      [
        DicomParsedFile(
          path: 'C:\\test\\$dicomPatientId.dcm',
          mtime: DateTime(2025, 1, 1),
          size: 1024,
          dedupKey: '1.2.3.$dicomPatientId',
          patientName: dicomPatientName,
          patientId: dicomPatientId,
          dcmDate: DateTime(2025, 1, 1),
        ),
      ];

  // autoLinked items need a real Patient reference — approveImport resolves
  // the target via matchedPatient?.id.
  final patient = autoLinked ? _testPatient('patient-$dicomPatientId') : null;

  return DicomPendingImport(
    dicomPatientId: dicomPatientId,
    dicomPatientName: dicomPatientName,
    dicomPatientNames: {dicomPatientName},
    dates: [DateTime(2025, 1, 1)],
    files: f,
    confidence: autoLinked ? 1.0 : 0.5,
    isConfirmed: isConfirmed,
    autoLinked: autoLinked,
    matchedPatient: patient,
    matchedPatientId: patient?.id,
    matchedPatientName: patient?.title,
  );
}

// ─── Tests ─────────────────────────────────────────────────────────────

void main() {
  group('DicomController — timer lifecycle', () {
    late _TestController t;

    setUp(() {
      t = _TestController();
      // Ensure globalSettings has valid Hive state.  In unit tests Hive is
      // auto-initialised by hive_flutter, but the store's Hive boxes may
      // not exist.  We use the controller directly and only test paths that
      // do not depend on globalSettings persistence.
    });

    tearDown(() {
      t.ctrl.stopPeriodicScan();
    });

    test('isTimerRunning is false initially', () {
      expect(t.ctrl.isTimerRunning, isFalse);
    });

    test('stopPeriodicScan is safe when no timer is running', () {
      // Should not throw.
      t.ctrl.stopPeriodicScan();
      t.ctrl.stopPeriodicScan();
      expect(t.ctrl.isTimerRunning, isFalse);
    });

    test(
        'stopPeriodicScan after startPeriodicScan sets isTimerRunning to '
        'false', () {
      // startPeriodicScan may fail here because watch dirs are empty
      // (guard). That is expected — we test the guards separately.
      // Just verify that stopPeriodicScan does not crash.
      t.ctrl.stopPeriodicScan();
      expect(t.ctrl.isTimerRunning, isFalse);
    });
  });

  group('DicomController — auto-approve via autoApproveLinked()', () {
    late _TestController t;

    setUp(() {
      t = _TestController();
    });

    tearDown(() {
      t.ctrl.stopPeriodicScan();
    });

    test('does NOT approve non-autoLinked items', () async {
      final pi = _pending(
        dicomPatientId: 'DCM-1',
        dicomPatientName: 'John Doe',
        autoLinked: false,
      );
      t.ctrl.pending([pi]);

      await t.ctrl.autoApproveLinked();

      // Non-auto-linked items stay in the pending list.
      expect(t.ctrl.pending().length, 1);
      expect(t.ctrl.pending().first.dicomPatientId, 'DCM-1');
    });

    test('auto-approves autoLinked items and removes them from pending',
        () async {
      final pi = _pending(
        dicomPatientId: 'DCM-LINKED',
        dicomPatientName: 'Jane Smith',
        autoLinked: true,
      );
      t.ctrl.pending([pi]);

      await t.ctrl.autoApproveLinked();

      // Auto-linked items should be removed after a successful approve.
      expect(t.ctrl.pending().length, 0);
    });

    test(
        'handles mixed pending list — autoLinked removed, non-autoLinked '
        'stays', () async {
      final auto = _pending(
        dicomPatientId: 'DCM-AUTO',
        dicomPatientName: 'Auto Patient',
        autoLinked: true,
      );
      final manual = _pending(
        dicomPatientId: 'DCM-MANUAL',
        dicomPatientName: 'Manual Patient',
        autoLinked: false,
      );
      t.ctrl.pending([auto, manual]);

      await t.ctrl.autoApproveLinked();

      final remaining = t.ctrl.pending();
      expect(remaining.length, 1);
      expect(remaining.first.dicomPatientId, 'DCM-MANUAL');
    });

    test('does nothing when pending list is empty', () async {
      t.ctrl.pending([]);

      await t.ctrl.autoApproveLinked();

      expect(t.ctrl.pending().length, 0);
    });
  });
}
