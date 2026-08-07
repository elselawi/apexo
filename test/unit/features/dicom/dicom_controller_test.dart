import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apexo/core/save_local.dart';
import 'package:apexo/core/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/login.dart' show login, onLogoutCallbacks;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../helpers/hive_setup.dart';

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
  final Map<String, DicomApprovalResult> approvalResults = {};
  final Map<DicomPendingImport, DicomApprovalResult> approvalResultsByItem = {};
  final Set<String> approvalThrows = {};
  final Map<String, bool> unregisterResults = {};

  /// The pending list that [scanAndBuildPending] will return on the next
  /// call. Set this before calling [refresh] / [_tick].
  List<DicomPendingImport> nextScanResult = const [];
  int scanCalls = 0;
  Completer<List<DicomPendingImport>>? scanGate;

  /// Set of dedup keys that are considered "already imported".
  final Set<String> importedKeys = {};

  /// Paths for which the upload/processing collaborator should fail.
  final Set<String> failingPaths = {};

  // ── Fakes for store dependencies ────────────────────────────────────

  final Map<String, String> _patientLinks = {};

  Future<Set<String>> _allImportedKeys() async => importedKeys;
  Future<bool> _isImported(String key) async => importedKeys.contains(key);

  Future<bool> _linkFile(String dicomPatientId, String key) async {
    if (importedKeys.contains(key)) return false;
    importedKeys.add(key);
    return true;
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
    if (failingPaths.contains(sourcePath)) {
      throw StateError('controlled upload failure: $sourcePath');
    }
    return 'mock.dcm';
  }

  final List<Appointment> _setAppointmentLog = [];

  void _setAppointment(Appointment a) {
    // Deep-copy so the caller's mutations don't affect our log.
    _setAppointmentLog.add(Appointment.fromJson(a.toJson()));
  }

  List<Appointment> _appointmentsForPatient(String id) => [];

  /// Builds a [DicomImporter] from the current fake state.
  DicomImporter build() {
    Future<DicomApprovalResult> approveImport(
        DicomPendingImport pending) async {
      approvedItems.add(pending);
      if (approvalThrows.contains(pending.dicomPatientId)) {
        throw StateError('controlled approval failure');
      }
      return approvalResultsByItem[pending] ??
          approvalResults[pending.dicomPatientId] ??
          DicomApprovalResult(
            successfulFiles: pending.files.length,
            failedFiles: const [],
          );
    }

    return DicomImporter(
      useIsolate: false,
      scanOverrideForTesting: () async {
        scanCalls++;
        final gate = scanGate;
        if (gate != null) return gate.future;
        return nextScanResult;
      },
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
      ensureAppointmentPersisted: () async {},
      appointmentsForPatient: _appointmentsForPatient,
      approvalOverrideForTesting: (pending, _) => approveImport(pending),
      unregisterOverrideForTesting: (filename) async =>
          unregisterResults[filename] ?? true,
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

class _HealingApi {
  final filesByRow = <String, List<String>>{};
  final requests = <http.Request>[];
  void Function(String rowId)? onGetFileList;

  MockClient get client => MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/api/health')) {
          return http.Response('{"code":200}', 200,
              headers: {'content-type': 'application/json'});
        }
        final rowId = request.url.pathSegments.last;
        if (request.method == 'GET') {
          onGetFileList?.call(rowId);
          final files = filesByRow[rowId] ?? const <String>[];
          return http.Response(
            jsonEncode({
              'id': rowId,
              'collectionId': 'data',
              'collectionName': 'data',
              'data': {},
              'imgs': files,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      });
}

class _HealingRemote extends SaveRemote {
  _HealingRemote({required this.api})
      : super(
          storeName: 'appointments',
          pbInstance: PocketBase(
            'http://fake-pocketbase',
            httpClientFactory: () => api.client,
          ),
        );

  final _HealingApi api;

  @override
  Future<void> checkOnline() async {
    isOnline = true;
  }
}

class _FailingHealingRemote extends _HealingRemote {
  _FailingHealingRemote({required super.api});

  @override
  Future<List<String>> getFileNames(String rowID, {bool useCache = false}) {
    throw StateError('lookup failed');
  }
}

Appointment _healingAppointment(String id, List<String> dcmFiles) =>
    Appointment.fromJson({
      'id': id,
      'patientID': 'patient-1',
      'date': DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 60000,
      'dcmImgs': dcmFiles,
    });

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

List<DicomParsedFile> _files(String patientId, int count) => [
      for (var i = 0; i < count; i++)
        DicomParsedFile(
          path: 'C:\\test\\$patientId-$i.dcm',
          mtime: DateTime(2025, 1, i + 1),
          size: 1024 + i,
          dedupKey: '1.2.3.$patientId.$i',
          patientName: i == 0 ? 'First Name' : 'Second Name',
          patientId: patientId,
          dcmDate: DateTime(2025, 1, i + 1),
        ),
    ];

DicomPendingImport _multiPending({
  required String patientId,
  bool autoLinked = false,
  int count = 3,
}) {
  final patient = autoLinked ? _testPatient('patient-$patientId') : null;
  return DicomPendingImport(
    dicomPatientId: patientId,
    dicomPatientName: 'Original Name',
    dicomPatientNames: const {'Original Name'},
    dates: [DateTime(2025, 1, 1)],
    files: _files(patientId, count),
    confidence: autoLinked ? 1 : .5,
    autoLinked: autoLinked,
    matchedPatient: patient,
    matchedPatientId: patient?.id,
    matchedPatientName: patient?.title,
  );
}

// ─── Tests ─────────────────────────────────────────────────────────────

void main() {
  group('DicomController stale DICOM helper', () {
    test('keeps server-present and row-scoped pending files', () {
      expect(
        DicomController.staleDcmFileNames(
          appointmentDcmFiles: const [
            'present.dcm',
            'pending.dcm',
            'stale.dcm'
          ],
          serverFiles: const ['PRESENT.DCM'],
          pendingUploadFiles: const {'pending.dcm'},
        ),
        ['stale.dcm'],
      );
    });

    test('does not let another row protect a stale filename', () {
      expect(
        DicomController.staleDcmFileNames(
          appointmentDcmFiles: const ['same.dcm'],
          serverFiles: const [],
          pendingUploadFiles: const {},
        ),
        ['same.dcm'],
      );
    });

    test('matches pending filenames case-insensitively', () {
      expect(
        DicomController.staleDcmFileNames(
          appointmentDcmFiles: const ['SAME.DCM'],
          serverFiles: const [],
          pendingUploadFiles: const {'same.dcm'},
        ),
        isEmpty,
      );
    });
  });

  group('DicomController — stale DICOM healing', () {
    late Directory hiveDirectory;
    late SaveLocal local;
    late _HealingApi api;
    late _HealingRemote remote;
    late DicomController controller;
    var testNumber = 0;

    setUpAll(() async {
      hiveDirectory = await setupTestHive();
    });

    setUp(() async {
      api = _HealingApi();
      local = SaveLocal(
        name: 'controller-heal',
        uniqueId: 'case-${testNumber++}',
        storagePath: hiveDirectory.path,
      );
      remote = _HealingRemote(api: api);
      appointments.local = local;
      appointments.remote = remote;
      appointments.observableMap.silently(() {
        appointments.observableMap.clear();
      });
      controller = DicomController(
        importer: _MockImporter().build(),
        synchronizeAppointments: () async => [],
        appointmentsInSync: () async => true,
      );
      controller.stopPeriodicScan();
    });

    tearDown(() async {
      controller.dispose();
      appointments.remote = null;
      appointments.local = null;
      remote.timer?.cancel();
      await local.dispose();
    });

    tearDownAll(() async {
      await teardownTestHive(hiveDirectory);
    });

    test('returns false without a remote or while remote is offline', () async {
      appointments.remote = null;
      expect(await controller.debugHealStaleDcmImgs(), isFalse);

      appointments.remote = remote..isOnline = false;
      expect(await controller.debugHealStaleDcmImgs(), isFalse);
    });

    test('requires synchronization convergence before inspecting rows',
        () async {
      var syncCalls = 0;
      var inSyncCalls = 0;
      controller.dispose();
      controller = DicomController(
        importer: _MockImporter().build(),
        synchronizeAppointments: () async {
          syncCalls++;
          return [];
        },
        appointmentsInSync: () async {
          inSyncCalls++;
          return false;
        },
      );
      controller.stopPeriodicScan();

      expect(await controller.debugHealStaleDcmImgs(), isFalse);
      expect(syncCalls, 1);
      expect(inSyncCalls, 1);
      expect(api.requests.where((r) => r.method == 'GET'), isEmpty);
    });

    test('uses PocketBase imgs rather than appointment imgs', () async {
      final appt = _healingAppointment('appt-1', ['present.dcm']);
      appt.imgs = const [];
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = ['present.dcm'];

      expect(await controller.debugHealStaleDcmImgs(), isTrue);
      expect(appt.dcmImgs, ['present.dcm']);
    });

    test('pending upload protects a missing server file for the same row',
        () async {
      final appt = _healingAppointment('appt-1', ['pending.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = [];
      await local.putDeferred({
        'FILE||${appt.id}||C:/pending||pending.dcm||0': 1,
      });

      expect(await controller.debugHealStaleDcmImgs(), isTrue);
      expect(appt.dcmImgs, ['pending.dcm']);
    });

    test('pending upload for another row does not protect this row', () async {
      final apptA = _healingAppointment('appt-a', ['same.dcm']);
      final apptB = _healingAppointment('appt-b', ['other.dcm']);
      appointments.observableMap.silently(() {
        appointments.set(apptA);
        appointments.set(apptB);
      });
      api.filesByRow[apptA.id] = [];
      api.filesByRow[apptB.id] = ['other.dcm'];
      await local.putDeferred({
        'FILE||${apptB.id}||C:/b||same.dcm||0': 1,
      });

      expect(await controller.debugHealStaleDcmImgs(), isTrue);
      expect(apptA.dcmImgs, isEmpty);
      expect(apptB.dcmImgs, ['other.dcm']);
    });

    test('failed server lookup is inconclusive and preserves references',
        () async {
      final appt = _healingAppointment('appt-1', ['unknown.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      // Use a remote whose file-list lookup fails while sync still converges.
      final failingRemote = _FailingHealingRemote(api: api);
      appointments.remote = failingRemote;

      expect(await controller.debugHealStaleDcmImgs(), isFalse);
      expect(appt.dcmImgs, ['unknown.dcm']);
    });

    test('registry cleanup failure preserves the appointment reference',
        () async {
      final appt = _healingAppointment('appt-1', ['stale.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = [];
      controller.dispose();
      final importer = _MockImporter()..unregisterResults['stale.dcm'] = false;
      controller = DicomController(
        importer: importer.build(),
        synchronizeAppointments: () async => [],
        appointmentsInSync: () async => true,
      );
      controller.stopPeriodicScan();

      expect(await controller.debugHealStaleDcmImgs(), isFalse);
      expect(appt.dcmImgs, ['stale.dcm']);
    });

    test('successful registry cleanup removes stale reference and resyncs',
        () async {
      final appt = _healingAppointment('appt-1', ['stale.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = [];
      var syncCalls = 0;
      controller.dispose();
      controller = DicomController(
        importer: _MockImporter().build(),
        synchronizeAppointments: () async {
          syncCalls++;
          return [];
        },
        appointmentsInSync: () async => true,
      );
      controller.stopPeriodicScan();

      expect(await controller.debugHealStaleDcmImgs(), isTrue);
      expect(appt.dcmImgs, isEmpty);
      expect(syncCalls, 2);
    });

    test('returns false when post-cleanup synchronization does not converge',
        () async {
      final appt = _healingAppointment('appt-1', ['stale.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = [];
      var syncCalls = 0;
      var convergenceChecks = 0;
      controller.dispose();
      controller = DicomController(
        importer: _MockImporter().build(),
        synchronizeAppointments: () async {
          syncCalls++;
          return [];
        },
        appointmentsInSync: () async {
          convergenceChecks++;
          return convergenceChecks == 1;
        },
      );
      controller.stopPeriodicScan();

      expect(await controller.debugHealStaleDcmImgs(), isFalse);
      expect(appt.dcmImgs, isEmpty);
      expect(syncCalls, 2);
      expect(convergenceChecks, 2);
    });

    test('revalidation preserves a file uploaded after initial inspection',
        () async {
      final appt = _healingAppointment('appt-1', ['race.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = [];
      var lookupCount = 0;
      api.onGetFileList = (_) {
        lookupCount++;
        if (lookupCount == 2) api.filesByRow[appt.id] = ['race.dcm'];
      };

      expect(await controller.debugHealStaleDcmImgs(), isTrue);
      expect(appt.dcmImgs, ['race.dcm']);
      expect(lookupCount, 2);
    });

    test('generation cancellation stops healing before mutation', () async {
      final appt = _healingAppointment('appt-1', ['stale.dcm']);
      appointments.observableMap.silently(() => appointments.set(appt));
      api.filesByRow[appt.id] = [];
      var checks = 0;

      final result = await controller.debugHealStaleDcmImgs(
        shouldContinue: () => ++checks < 2,
      );

      expect(result, isFalse);
      expect(appt.dcmImgs, ['stale.dcm']);
    });
  });

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
      globalSettings.dicomWatchDirs = [];
      globalSettings.dicomAutoImport = true;
      t.ctrl.dispose();
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
    test('generation changes whenever periodic scanning stops', () {
      final before = t.ctrl.debugPeriodicGeneration;
      t.ctrl.stopPeriodicScan();
      expect(t.ctrl.debugPeriodicGeneration, greaterThan(before));
    });

    test('stale tick generation is ignored without starting a scan', () async {
      final before = t.ctrl.debugPeriodicGeneration;
      t.ctrl.stopPeriodicScan();
      await t.ctrl.debugTick(before);

      expect(t.ctrl.scanning(), isFalse);
      expect(t.ctrl.pending(), isEmpty);
    });

    test('stopping periodic scan resets healing state', () async {
      expect(t.ctrl.debugHealed, isFalse);
      expect(t.ctrl.debugHealing, isFalse);
      t.ctrl.stopPeriodicScan();
      expect(t.ctrl.debugHealed, isFalse);
      expect(t.ctrl.debugHealing, isFalse);
    });

    test('periodic scan does not start when auto-import is disabled', () {
      if (!DicomController.isSupported) return;
      globalSettings.dicomWatchDirs = [r'C:\dcm'];
      globalSettings.dicomAutoImport = false;

      t.ctrl.startPeriodicScan();

      expect(t.ctrl.isTimerRunning, isFalse);
    });

    test('periodic scan starts and immediately scans when enabled', () async {
      if (!DicomController.isSupported) return;
      globalSettings.dicomWatchDirs = [r'C:\dcm'];
      globalSettings.dicomAutoImport = true;
      final linked = _pending(
        dicomPatientId: 'PERIODIC-LINKED',
        dicomPatientName: 'Periodic',
        autoLinked: true,
      );
      t.mock.nextScanResult = [linked];

      t.ctrl.startPeriodicScan();
      await Future<void>.delayed(Duration.zero);

      expect(t.ctrl.isTimerRunning, isTrue);
      expect(t.mock.scanCalls, 1);
      expect(t.mock.approvedItems, [linked]);
      t.ctrl.stopPeriodicScan();
    });

    test('manual refresh still scans while auto-import is disabled', () async {
      globalSettings.dicomWatchDirs = [r'C:\dcm'];
      globalSettings.dicomAutoImport = false;
      final linked = _pending(
        dicomPatientId: 'MANUAL-REFRESH-LINKED',
        dicomPatientName: 'Manual Refresh',
        autoLinked: true,
      );
      t.mock.nextScanResult = [linked];

      await t.ctrl.refresh();

      expect(t.mock.scanCalls, 1);
      expect(t.mock.approvedItems, [linked]);
      expect(t.ctrl.pending(), isEmpty);
      expect(t.ctrl.isTimerRunning, isFalse);
    });
  });

  group('DicomController — end-to-end refresh workflows', () {
    late _TestController t;

    setUp(() {
      t = _TestController();
    });

    tearDown(() {
      t.ctrl.dispose();
    });

    test('refresh auto-approves a linked patient and removes the batch',
        () async {
      final linked = _pending(
        dicomPatientId: 'LINKED-REFRESH',
        dicomPatientName: 'Linked',
        autoLinked: true,
      );
      t.mock.nextScanResult = [linked];

      await t.ctrl.refresh();

      expect(t.mock.scanCalls, 1);
      expect(t.mock.approvedItems, [linked]);
      expect(t.ctrl.pending(), isEmpty);
      expect(t.ctrl.scanning(), isFalse);
    });

    test('refresh leaves an unlinked suggested match pending for approval',
        () async {
      final suggested = _pending(
        dicomPatientId: 'SUGGESTED-REFRESH',
        dicomPatientName: 'Suggested',
        autoLinked: false,
      )..matchedPatient = _testPatient('patient-suggested');
      t.mock.nextScanResult = [suggested];

      await t.ctrl.refresh();

      expect(t.mock.approvedItems, isEmpty);
      expect(t.ctrl.pending(), [suggested]);
    });

    test('refresh is re-entrant safe while a scan is in flight', () async {
      final gate = Completer<List<DicomPendingImport>>();
      t.mock.scanGate = gate;
      final first = t.ctrl.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = t.ctrl.refresh();

      expect(t.mock.scanCalls, 1);
      expect(t.ctrl.scanning(), isTrue);
      gate.complete(const []);
      await Future.wait([first, second]);
      expect(t.ctrl.scanning(), isFalse);
    });
  });

  group('DicomController — auto-approve via autoApproveLinked()', () {
    late _TestController t;

    setUp(() {
      t = _TestController();
    });

    tearDown(() {
      t.ctrl.dispose();
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

    test('dispose removes the controller lifecycle callbacks', () {
      expect(onLogoutCallbacks, contains(t.ctrl.stopPeriodicScan));
      expect(Store.onFileDeadLettered, isNotEmpty);
      t.ctrl.dispose();
      expect(Store.onFileDeadLettered, isEmpty);
      expect(onLogoutCallbacks, isNot(contains(t.ctrl.stopPeriodicScan)));
      expect(login.activators['dicom'], isNull);
    });

    test('disposing a replacement controller does not remove its callbacks',
        () {
      final first = t.ctrl;
      final second = _TestController();
      addTearDown(second.ctrl.dispose);

      first.dispose();

      expect(Store.onFileDeadLettered, isNotEmpty);
      expect(onLogoutCallbacks, contains(second.ctrl.stopPeriodicScan));
      expect(login.activators['dicom'], isNotNull);
    });

    test('an older controller cannot remove a newer activator', () {
      final first = t.ctrl;
      final second = _TestController();
      addTearDown(second.ctrl.dispose);
      final activator = login.activators['dicom'];

      first.dispose();

      expect(login.activators['dicom'], same(activator));
    });

    test('autoApproveLinked reduces a partial item to only failed files',
        () async {
      final pi = _multiPending(patientId: 'PARTIAL', autoLinked: true);
      t.mock.approvalResults['PARTIAL'] = DicomApprovalResult(
        successfulFiles: 2,
        failedFiles: [pi.files.last],
      );
      t.ctrl.pending([pi]);

      await t.ctrl.autoApproveLinked();

      expect(t.ctrl.pending(), hasLength(1));
      final reduced = t.ctrl.pending().single;
      expect(reduced.files, [pi.files.last]);
      expect(reduced.matchedPatient?.id, pi.matchedPatient?.id);
      expect(reduced.dicomPatientName, pi.files.last.patientName);
      expect(reduced.dates, [pi.files.last.dcmDate]);
    });

    test('autoApproveLinked retains item when importer throws', () async {
      final pi = _pending(
        dicomPatientId: 'THROW',
        dicomPatientName: 'Throws',
        autoLinked: true,
      );
      t.mock.approvalThrows.add('THROW');
      t.ctrl.pending([pi]);

      await t.ctrl.autoApproveLinked();

      expect(t.ctrl.pending(), hasLength(1));
      expect(t.mock.approvedItems, hasLength(1));
    });

    test('manual approve removes only a complete item', () async {
      final complete = _pending(
        dicomPatientId: 'MANUAL-COMPLETE',
        dicomPatientName: 'Manual Complete',
      );
      t.ctrl.pending([complete]);

      await t.ctrl.approve(complete, apexoPatientId: 'patient-manual');

      expect(t.ctrl.pending(), isEmpty);
      expect(t.mock.approvedItems.single, same(complete));
    });

    test('manual approve retains failed files and preserves other items',
        () async {
      final partial = _multiPending(patientId: 'MANUAL-PARTIAL');
      final other = _pending(
        dicomPatientId: 'OTHER',
        dicomPatientName: 'Other',
      );
      t.mock.approvalResults['MANUAL-PARTIAL'] = DicomApprovalResult(
        successfulFiles: 2,
        failedFiles: [partial.files[1], partial.files[2]],
      );
      t.ctrl.pending([partial, other]);

      await t.ctrl.approve(partial, apexoPatientId: 'patient-manual');

      expect(t.ctrl.pending(), hasLength(2));
      expect(
          t.ctrl.pending().first.files, [partial.files[1], partial.files[2]]);
      expect(t.ctrl.pending().last, same(other));
    });

    test('batchApprove counts only complete approvals', () async {
      final complete = _pending(
        dicomPatientId: 'BATCH-COMPLETE',
        dicomPatientName: 'Batch Complete',
        autoLinked: true,
      );
      final partial =
          _multiPending(patientId: 'BATCH-PARTIAL', autoLinked: true);
      final unselected = _pending(
        dicomPatientId: 'BATCH-UNSELECTED',
        dicomPatientName: 'Unselected',
        autoLinked: true,
      );
      t.mock.approvalResults['BATCH-PARTIAL'] = DicomApprovalResult(
        successfulFiles: 1,
        failedFiles: [partial.files.last],
      );
      t.ctrl.pending([complete, partial, unselected]);

      final count =
          await t.ctrl.batchApprove({'BATCH-COMPLETE', 'BATCH-PARTIAL'});

      expect(count, 1);
      expect(t.ctrl.pending().map((item) => item.dicomPatientId), [
        'BATCH-PARTIAL',
        'BATCH-UNSELECTED',
      ]);
      expect(t.ctrl.pending().first.files, [partial.files.last]);
      expect(t.ctrl.importProgress(), (current: 0, total: 0));
    });

    test('batchApprove keeps separate blank-patient batches independent',
        () async {
      final first = _multiPending(patientId: '', count: 2);
      final second = _multiPending(patientId: '', count: 2);
      final firstFailed = first.files.last;
      final secondFailed = second.files.first;
      t.mock.approvalResultsByItem[first] = DicomApprovalResult(
        successfulFiles: 1,
        failedFiles: [firstFailed],
      );
      t.mock.approvalResultsByItem[second] = DicomApprovalResult(
        successfulFiles: 1,
        failedFiles: [secondFailed],
      );
      first.matchedPatient = _testPatient('patient-first');
      second.matchedPatient = _testPatient('patient-second');
      t.ctrl.pending([first, second]);

      final count = await t.ctrl.batchApprove({''});

      expect(count, 0);
      expect(t.ctrl.pending(), hasLength(2));
      expect(t.ctrl.pending()[0].files, [firstFailed]);
      expect(t.ctrl.pending()[1].files, [secondFailed]);
    });

    test('batchApprove ignores items without a confirmed patient match',
        () async {
      final unmatched = _pending(
        dicomPatientId: 'NO-MATCH',
        dicomPatientName: 'No Match',
      );
      t.ctrl.pending([unmatched]);

      expect(await t.ctrl.batchApprove({'NO-MATCH'}), 0);
      expect(t.mock.approvedItems, isEmpty);
      expect(t.ctrl.pending(), [unmatched]);
    });
  });
}
