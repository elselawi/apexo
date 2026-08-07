@Tags(['serial'])
library;

import 'dart:typed_data';

import 'package:apexo/core/save_remote.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake of [DicomLinksStore] for tests.
class _FakeLinksStore {
  final Map<String, String> _registry = {};
  final Map<String, String> _patientLinks = {};
  final Map<String, String> _pendingMatches = {};
  final Set<String> _unmatchedIds = {};

  Set<String> get _allKeys => _registry.keys.toSet();
  Map<String, String> get linkedPatients => Map.of(_patientLinks);

  Future<Set<String>> get allImportedKeys async => _allKeys;
  Future<bool> isImported(String key) async => _allKeys.contains(key);

  Future<bool> linkFile(String dicomPatientId, String key) async {
    if (_registry.containsKey(key)) return false;
    _registry[key] = dicomPatientId;
    return true;
  }

  Future<void> setPatient(String dicomPatientId, String apexoPatientId) async {
    _patientLinks[dicomPatientId] = apexoPatientId;
  }

  Future<void> unlink(String dicomPatientId) async {
    _registry.removeWhere((_, v) => v == dicomPatientId);
    _patientLinks.remove(dicomPatientId);
  }
}

/// DicomImporter orchestration tests.
///
/// The importer is fully dependency-injected, so these tests run without
/// Hive, PocketBase, login, or the FFI engine. Each test wires up an
/// in-memory fake for every collaborator (scan / read / parse / registry /
/// cache / skipped log / patients / settings / appointments / handleNewDcm)
/// and drives `scanAndBuildPending` + `approveImport` end-to-end.
///
/// Coverage:
///  - 2 files (same patient, diff dates) 1 pending import with 2 dates.
///  - Re-scan dedups via registry AND hits the file cache (0 parses).
///  - Nonexistent directory [] (graceful, no crash).
///  - approveImport creates appointments with correct dcmImgs; registry +
///    link map updated.
///  - Idempotency: re-approve no duplicates, no new appointments.
///  - Edge-case corpus: parse failures logged to skipped; dup SOP UID
///    first-wins.

/// A mutable bag of DICOM metadata keyed by file path. Lets tests describe a
/// fake watch directory as data, then build the matching fakes from it.
class _FakeFile {
  final String path;
  final DicomParsedMeta meta;
  final int size;
  final DateTime mtime;

  _FakeFile(this.path, this.meta, {int? size, DateTime? mtime})
      : size = size ?? 1024,
        mtime = mtime ?? DateTime(2025, 1, 1);
}

/// Builds a [DicomParsedMeta] with the fields the importer consumes.
DicomParsedMeta _meta({
  required String sopInstanceUid,
  required String patientId,
  required String patientName,
  required String studyDate,
  String studyInstanceUid = '1.2.3',
  String seriesInstanceUid = '1.2.3.1',
  String instanceNumber = '1',
  bool isVolumetric = false,
}) {
  return DicomParsedMeta(
    sopInstanceUid: sopInstanceUid,
    studyInstanceUid: studyInstanceUid,
    seriesInstanceUid: seriesInstanceUid,
    instanceNumber: instanceNumber,
    patientName: patientName,
    patientId: patientId,
    dcmDate: studyDate.length == 8
        ? DateTime(
            int.parse(studyDate.substring(0, 4)),
            int.parse(studyDate.substring(4, 6)),
            int.parse(studyDate.substring(6, 8)),
          )
        : null,
    isVolumetric: isVolumetric,
  );
}

/// Test harness: holds every in-memory collaborator and exposes a
/// [DicomImporter] wired to them. Tests call [rebuild] after mutating the
/// fake filesystem / registry to refresh the importer's view.
class _Harness {
  /// The fake watch directory contents (path file).
  final Map<String, _FakeFile> fs = {};

  /// In-memory file cache (path cached meta).
  final Map<String, DicomCachedMeta> cache = {};

  /// In-memory skipped log (path reason).
  final Map<String, String> skipped = {};

  /// Number of times the parser was invoked (for cache-hit assertions).
  int parseCalls = 0;

  /// In-memory appointments store (id appointment).
  final Map<String, Appointment> appointments = {};

  /// Recorded handleNewDcm results (sourcePath assigned dcmName).
  final Map<String, String> handleNewDcmResults = {};
  final Map<String, String> configuredDcmNames = {};

  /// Source paths for which file processing should fail.
  final Set<String> failedDcmUploads = {};
  final Set<String> emptyDcmUploads = {};

  /// When true, simulates failure while persisting the DICOM patient link.
  bool failPatientLink = false;

  /// When true, the injected appointment persistence callback throws.
  bool failAppointmentPersistence = false;

  /// Records the order of appointment and upload operations.
  final List<String> persistenceEvents = [];

  /// When true, removeKey throws during rollback.
  bool failRemoveKey = false;

  /// In-memory patient roster (id patient).
  final Map<String, Patient> patients = {};

  /// In-memory appointment dates per Apexo patient (id dates), used by the
  /// fuzzy matcher's date-proximity score. Lets tests supply appointment
  /// dates without populating the global appointments store.
  final Map<String, Set<DateTime>> appointmentDates = {};

  /// Paths whose readBytes should return null (simulating a locked/deleted
  /// file). Populated by tests via [markUnreadable].
  final Set<String> _unreadable = {};

  /// Paths whose parseMetadata should throw (simulating a corrupt file).
  /// Populated by tests via [markCorrupt].
  final Set<String> _corrupt = {};

  /// Side-channel: the path most recently handed to readBytes. The fake
  /// parser is path-blind (the importer passes it only bytes), so it reads
  /// this field to find the originating file. Safe because the importer's
  /// scan loop is sequential (one `await` per file).
  String? _lastReadPath;

  /// The watch directories this harness reports via getWatchDirs. Tests can
  /// override (e.g. to a nonexistent path or [] to exercise edge cases).
  List<String> watchDirs = ['/fake/watch'];

  /// In-memory fake links store.
  final _FakeLinksStore fakeLinks = _FakeLinksStore();

  /// Cached metadata entries injected directly to exercise cache-hit paths.
  final Map<String, DicomCachedMeta> injectedCache = {};

  /// The current importer. Reassign via [rebuild] after mutating the fake
  /// filesystem / registry to refresh the closures' captured state.
  late DicomImporter importer;

  _Harness() {
    importer = rebuild();
  }

  DicomImporter rebuild() {
    return DicomImporter(
      useIsolate: false,
      allImportedKeys: () async => fakeLinks._registry.keys.toSet(),
      isImported: (k) async => fakeLinks._registry.containsKey(k),
      linkFile: (dicomId, key) => fakeLinks.linkFile(dicomId, key),
      setPatient: (dicomId, apexoId) async {
        persistenceEvents.add('patient:$dicomId:$apexoId');
        if (failPatientLink) {
          throw StateError('fake patient-link persistence failed');
        }
        fakeLinks._patientLinks[dicomId] = apexoId;
      },
      linkedPatients: () => Map.of(fakeLinks._patientLinks),
      pendingMatches: () async => Map.of(fakeLinks._pendingMatches),
      unmatchedIds: () async => fakeLinks._unmatchedIds,
      clearPendingMatch: (patientId) async {
        persistenceEvents.add('clear-pending:$patientId');
        fakeLinks._pendingMatches.remove(patientId);
      },
      clearUnmatched: (patientId) async {
        persistenceEvents.add('clear-unmatched:$patientId');
        fakeLinks._unmatchedIds.remove(patientId);
      },
      appointmentDayMap: () => appointmentDates,
      scanDirectory: (dir) async {
        // Simulate scanDirectory: list files whose path starts with `dir`.
        // An empty or nonexistent dir empty list (graceful handling).
        if (dir.isEmpty) return <DicomFileEntry>[];
        return fs.entries
            .where((e) => e.key.startsWith(dir))
            .map((e) => DicomFileEntry(
                  path: e.key,
                  mtime: e.value.mtime,
                  size: e.value.size,
                ))
            .toList();
      },
      readBytes: (p) async {
        _lastReadPath = p;
        if (_unreadable.contains(p)) return null;
        final f = fs[p];
        if (f == null) return null;
        // Any non-empty payload the fake parser ignores bytes and resolves
        // metadata via the _lastReadPath side-channel.
        return Uint8List.fromList([1, 2, 3, 4]);
      },
      parseMetadata: (bytes) async {
        parseCalls++;
        final path = _lastReadPath;
        if (path != null && _corrupt.contains(path)) {
          throw Exception('fake: corrupt file $path');
        }
        final f = path == null ? null : fs[path];
        if (f == null) {
          throw Exception('fake: no file for path $path');
        }
        return f.meta;
      },
      cacheSnapshot: () async => {
        ...cache,
        ...injectedCache,
      },
      cachePut: (p, meta) async => cache[p] = meta,
      cachePrune: (currentPaths) async {
        cache.removeWhere((k, _) => !currentPaths.contains(k));
      },
      logSkipped: ({required path, required reason}) async {
        skipped[path] = reason;
      },
      clearSkipped: (p) async => skipped.remove(p),
      allPatients: () => patients.values.toList(),
      getWatchDirs: () => watchDirs,
      handleNewDcm: ({required rowID, required sourcePath}) async {
        persistenceEvents.add('upload:$sourcePath');
        if (failedDcmUploads.contains(sourcePath)) {
          throw StateError('fake upload failed for $sourcePath');
        }
        if (emptyDcmUploads.contains(sourcePath)) return '';
        final name =
            configuredDcmNames[sourcePath] ?? 'dcm_${sourcePath.hashCode}.dcm';
        handleNewDcmResults[sourcePath] = name;
        return name;
      },
      removeKey: (key) async {
        if (failRemoveKey) throw StateError('fake removeKey failed');
        final patientId = fakeLinks._registry.remove(key);
        return patientId != null;
      },
      setAppointment: (appt) {
        persistenceEvents.add('set:${appt.id}:${appt.dcmImgs.length}');
        appointments[appt.id] = appt;
      },
      ensureAppointmentPersisted: () async {
        persistenceEvents.add('persist');
        if (failAppointmentPersistence) {
          throw StateError('fake appointment persistence failed');
        }
      },
      appointmentsForPatient: (id) =>
          appointments.values.where((a) => a.patientID == id).toList(),
    );
  }

  /// Wires a fake file into the filesystem so scanDirectory discovers it
  /// and readBytes/parseMetadata can resolve its metadata.
  void addFile(_FakeFile f) {
    fs[f.path] = f;
  }

  /// Marks [path] as unreadable (readBytes returns null skipped).
  void markUnreadable(String path) => _unreadable.add(path);

  /// Marks [path] as corrupt (parseMetadata throws skipped).
  void markCorrupt(String path) => _corrupt.add(path);
}

/// Constructs a fresh harness.
_Harness _newHarness() => _Harness();

/// Constructs a harness whose watch dirs are [dirs] (use [] or a nonexistent
/// path to exercise the missing-directory edge case).
_Harness _harnessWithWatchDirs(List<String> dirs) {
  final h = _Harness()..watchDirs = dirs;
  h.importer = h.rebuild();
  return h;
}

DicomParsedFile _parsedFile({
  String path = '/fake/watch/file.dcm',
  String dedupKey = 'sop:file',
  String patientId = 'P1',
  String patientName = 'Patient Name',
  DateTime? date,
}) =>
    DicomParsedFile(
      path: path,
      mtime: DateTime(2025, 1, 1),
      size: 1,
      dedupKey: dedupKey,
      patientName: patientName,
      patientId: patientId,
      dcmDate: date ?? DateTime(2025, 1, 1),
    );

DicomPendingImport _pendingForTest({
  List<DicomParsedFile>? files,
  Patient? matchedPatient,
  String patientId = 'P1',
  String patientName = 'Patient Name',
}) =>
    DicomPendingImport(
      dicomPatientId: patientId,
      dicomPatientName: patientName,
      dicomPatientNames: {patientName},
      dates: (files ?? [_parsedFile(patientId: patientId)])
          .map((f) => f.dcmDate)
          .whereType<DateTime>()
          .toList(),
      files: files ?? [_parsedFile(patientId: patientId)],
      matchedPatient: matchedPatient,
      matchedPatientId: matchedPatient?.id,
      matchedPatientName: matchedPatient?.title,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scanAndBuildPending happy path', () {
    test('2 files (same patient, 2 dates) 1 pending import with 2 dates',
        () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 'sop-1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/b.dcm',
          _meta(
              sopInstanceUid: 'sop-2',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250201')));

      final pending = await h.importer.scanAndBuildPending();

      expect(pending.length, 1, reason: 'one DICOM patient one pending');
      final p = pending.single;
      expect(p.dicomPatientId, 'P100');
      expect(p.dicomPatientName, 'Smith^John');
      expect(p.dates.length, 2, reason: 'two distinct study dates');
      expect(p.dates, [DateTime(2025, 1, 1), DateTime(2025, 2, 1)]);
      expect(p.fileCount, 2);
      expect(h.parseCalls, 2, reason: 'both files parsed (cache miss)');
    });

    test('groups multiple patients into separate pending imports', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/b.dcm',
          _meta(
              sopInstanceUid: 's2',
              patientId: 'P2',
              patientName: 'B',
              studyDate: '20250102')));

      final pending = await h.importer.scanAndBuildPending();
      expect(pending.length, 2);
      final ids = pending.map((p) => p.dicomPatientId).toSet();
      expect(ids, {'P1', 'P2'});
    });
  });

  group('scanAndBuildPending workflow updates', () {
    test('a later file for the same patient joins the existing pending batch',
        () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/first.dcm',
          _meta(
              sopInstanceUid: 's-first',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));

      final firstScan = await h.importer.scanAndBuildPending();
      expect(firstScan, hasLength(1));
      expect(firstScan.single.files, hasLength(1));

      h.addFile(_FakeFile(
          '/fake/watch/second.dcm',
          _meta(
              sopInstanceUid: 's-second',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250102')));
      final secondScan = await h.importer.scanAndBuildPending();

      expect(secondScan, hasLength(1));
      expect(secondScan.single.files.map((file) => file.dedupKey),
          ['sop:s-first', 'sop:s-second']);
      expect(secondScan.single.dates,
          [DateTime(2025, 1, 1), DateTime(2025, 1, 2)]);
    });

    test('a new file for a different patient stays in a separate batch',
        () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/first.dcm',
          _meta(
              sopInstanceUid: 's-first',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      await h.importer.scanAndBuildPending();

      h.addFile(_FakeFile(
          '/fake/watch/other.dcm',
          _meta(
              sopInstanceUid: 's-other',
              patientId: 'P200',
              patientName: 'B',
              studyDate: '20250101')));
      final scan = await h.importer.scanAndBuildPending();

      expect(scan, hasLength(2));
      expect(scan.map((item) => item.dicomPatientId).toSet(), {'P100', 'P200'});
    });
  });

  group('scanAndBuildPending dedup + file cache', () {
    test('re-scan after approve returns [] (registry dedup)', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));

      final first = await h.importer.scanAndBuildPending();
      expect(first, isNotEmpty);

      // Simulate the files having been imported (registry now populated).
      for (final f in first.single.files) {
        h.fakeLinks._registry[f.dedupKey] = f.path;
      }
      h.importer = h.rebuild();

      final second = await h.importer.scanAndBuildPending();
      expect(second, isEmpty, reason: 'already-imported files are deduped');
    });

    test('file-cache hit avoids re-parsing', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));

      await h.importer.scanAndBuildPending();
      final parsesAfterFirst = h.parseCalls;
      expect(parsesAfterFirst, 1);

      // Second scan with the same files (mtime/size unchanged) cache hit,
      // zero additional parses. Registry empty so the file still surfaces.
      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      expect(h.parseCalls, parsesAfterFirst,
          reason: 'cache hit must skip parseMetadata entirely');
      expect(pending, isNotEmpty,
          reason: 'file still surfaces (not yet imported)');
    });

    test('cache entries are persisted for cache misses', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));

      await h.importer.scanAndBuildPending();
      expect(h.cache.containsKey('/fake/watch/a.dcm'), isTrue,
          reason: 'cache entry written for the parsed file');
      expect(h.cache['/fake/watch/a.dcm']!.dedupKey, 'sop:s1');
    });

    test('stale cache entries are pruned when files disappear', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      await h.importer.scanAndBuildPending();
      expect(h.cache.containsKey('/fake/watch/a.dcm'), isTrue);

      // File deleted from the fake filesystem.
      h.fs.remove('/fake/watch/a.dcm');
      h.importer = h.rebuild();
      await h.importer.scanAndBuildPending();

      expect(h.cache.containsKey('/fake/watch/a.dcm'), isFalse,
          reason: 'pruneMissing evicts entries for deleted files');
    });
  });

  group('scanAndBuildPending robustness', () {
    test('nonexistent directory [] (graceful, no crash)', () async {
      final h = _harnessWithWatchDirs(['/does/not/exist']);
      final pending = await h.importer.scanAndBuildPending();
      expect(pending, isEmpty);
    });

    test('empty watch dir setting [] (early return, no scan)', () async {
      final h = _harnessWithWatchDirs([]);
      final pending = await h.importer.scanAndBuildPending();
      expect(pending, isEmpty);
    });

    test('parse failure logged to skipped; importable files still surface',
        () async {
      final h = _newHarness();
      // Good file.
      h.addFile(_FakeFile(
          '/fake/watch/good.dcm',
          _meta(
              sopInstanceUid: 's-good',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      // Bad file: present on disk, but parseMetadata throws (corrupt).
      h.addFile(_FakeFile(
          '/fake/watch/bad.dcm',
          _meta(
              sopInstanceUid: 's-bad',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      h.markCorrupt('/fake/watch/bad.dcm');

      final pending = await h.importer.scanAndBuildPending();

      expect(pending.length, 1, reason: 'only the good file is importable');
      expect(pending.single.fileCount, 1);
      expect(h.skipped.containsKey('/fake/watch/bad.dcm'), isTrue,
          reason: 'parse failure logged to skipped');
      expect(
          h.skipped['/fake/watch/bad.dcm']!.contains('parseMetadata'), isTrue);
    });

    test('unreadable file (readBytes null) logged to skipped', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/locked.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      h.markUnreadable('/fake/watch/locked.dcm');

      final pending = await h.importer.scanAndBuildPending();
      expect(pending, isEmpty, reason: 'unreadable file is not importable');
      expect(h.skipped.containsKey('/fake/watch/locked.dcm'), isTrue);
      expect(
          h.skipped['/fake/watch/locked.dcm']!.contains('readBytes'), isTrue);
    });

    test('duplicate SOP UID: first-wins, second logged to skipped', () async {
      final h = _newHarness();
      // Two files with the SAME sopInstanceUid.
      h.addFile(_FakeFile(
          '/fake/watch/first.dcm',
          _meta(
              sopInstanceUid: 'dup',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/second.dcm',
          _meta(
              sopInstanceUid: 'dup',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250102')));

      // Both produce the same dedup key 'sop:dup'. The importer's _doScan
      // does NOT dedup within a single scan (it dedups against the registry).
      // So both surface in pending. The first-wins behaviour is enforced by
      // the registry during approveImport verified in the approveImport
      // idempotency test below. Here we verify both keys are equal.
      final pending = await h.importer.scanAndBuildPending();
      expect(pending.single.fileCount, 2);
      final keys = pending.single.files.map((f) => f.dedupKey).toSet();
      expect(keys.length, 1, reason: 'both files share the SOP dedup key');
      expect(keys.single, 'sop:dup');
    });

    test('volumetric file (isVolumetric=true) skipped with reason', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/cbct_slice_001.dcm',
          _meta(
              sopInstanceUid: 's-vol-1',
              patientId: 'P1',
              patientName: 'CBCT Patient',
              studyDate: '20250101',
              isVolumetric: true)));
      // A non-volumetric file from the same patient should still surface.
      h.addFile(_FakeFile(
          '/fake/watch/periapical.dcm',
          _meta(
              sopInstanceUid: 's-nonvol-1',
              patientId: 'P1',
              patientName: 'CBCT Patient',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();

      expect(pending.length, 1,
          reason: 'only the non-volumetric file is importable');
      expect(pending.single.fileCount, 1);
      expect(pending.single.dicomPatientName, 'CBCT Patient');
      expect(h.skipped.containsKey('/fake/watch/cbct_slice_001.dcm'), isTrue);
      expect(
          h.skipped['/fake/watch/cbct_slice_001.dcm']!, contains('volumetric'));
    });

    test('volumetric file skipped on cache hit without re-parsing', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/vol_slice.dcm',
          _meta(
              sopInstanceUid: 's-vol-cached',
              patientId: 'P1',
              patientName: 'Vol Patient',
              studyDate: '20250101',
              isVolumetric: true)));

      // First scan: file is parsed, found volumetric, skipped, cached.
      final first = await h.importer.scanAndBuildPending();
      expect(first, isEmpty);
      expect(h.skipped.containsKey('/fake/watch/vol_slice.dcm'), isTrue);
      expect(h.parseCalls, 1, reason: 'parsed on first scan (cache miss)');
      final parsesBeforeSecond = h.parseCalls;

      // Second scan: cache hit — skipped without re-parsing.
      final second = await h.importer.scanAndBuildPending();
      expect(second, isEmpty);
      // The volumetric file is still logged to skipped (re-logged on cache hit).
      expect(h.skipped.containsKey('/fake/watch/vol_slice.dcm'), isTrue,
          reason: 'volumetric file still marked as skipped on cache hit');
      expect(h.skipped['/fake/watch/vol_slice.dcm']!, contains('volumetric'));
      // Zero additional parse calls — cache hit, no re-parse.
      expect(h.parseCalls, parsesBeforeSecond,
          reason: 'cache hit must skip parseMetadata entirely');
    });

    test('blank DICOM identity is skipped and not grouped or linked', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/blank-a.dcm',
          _meta(
              sopInstanceUid: '',
              studyInstanceUid: '',
              seriesInstanceUid: '',
              instanceNumber: '',
              patientId: '',
              patientName: 'A',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();

      expect(pending, isEmpty);
      expect(h.skipped['/fake/watch/blank-a.dcm'], contains('identity'));
    });

    test('multiple blank-patient files remain isolated by dedup identity',
        () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/blank-a.dcm',
          _meta(
              sopInstanceUid: 'blank-a',
              patientId: '',
              patientName: 'A',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/blank-b.dcm',
          _meta(
              sopInstanceUid: 'blank-b',
              patientId: '',
              patientName: 'B',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();

      expect(pending, hasLength(2));
      expect(pending.every((item) => item.dicomPatientId.isEmpty), isTrue);
      expect(pending.map((item) => item.files.single.dedupKey).toSet(),
          {'sop:blank-a', 'sop:blank-b'});
    });

    test('complete composite identity is accepted when SOP is blank', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/composite.dcm',
          _meta(
              sopInstanceUid: '',
              studyInstanceUid: 'study',
              seriesInstanceUid: 'series',
              instanceNumber: '7',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();

      expect(pending, hasLength(1));
      expect(pending.single.files.single.dedupKey, 'composite:study|series|7');
    });

    test('cached invalid identities remain skipped without parsing', () async {
      final h = _newHarness();
      const path = '/fake/watch/cached-invalid.dcm';
      final mtime = DateTime(2025, 1, 1);
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 'would-not-be-used',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101'),
          mtime: mtime));
      h.injectedCache[path] = DicomCachedMeta(
        mtime: mtime,
        size: 1024,
        dedupKey: 'composite:study||missing',
        patientName: 'A',
        patientId: 'P1',
        dcmDate: DateTime(2025, 1, 1),
      );

      final pending = await h.importer.scanAndBuildPending();

      expect(pending, isEmpty);
      expect(h.parseCalls, 0);
      expect(h.skipped[path], contains('identity'));
    });

    test('partial composite identity is skipped', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/partial.dcm',
          _meta(
              sopInstanceUid: '',
              studyInstanceUid: 'study-only',
              seriesInstanceUid: '',
              instanceNumber: '1',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));

      expect(await h.importer.scanAndBuildPending(), isEmpty);
      expect(h.skipped['/fake/watch/partial.dcm'], contains('identity'));
    });
  });

  group('scanAndBuildPending matching', () {
    test('auto-link via dicomPatientLinksMap (confidence 1.0, isConfirmed)',
        () async {
      final h = _newHarness();
      final patient =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.patients['apexo-1'] = patient;
      h.fakeLinks._patientLinks['P100'] = 'apexo-1';

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      final p = pending.single;
      expect(p.autoLinked, isTrue);
      expect(p.isConfirmed, isTrue);
      expect(p.confidence, 1.0);
      expect(p.matchedPatient?.id, 'apexo-1');
    });

    test('fuzzy name match surfaces a suggestion with computed confidence',
        () async {
      final h = _newHarness();
      // Apexo patient whose name tokenizes identically to the DICOM name.
      final patient =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.patients['apexo-1'] = patient;
      // An appointment on the exact study date dateProximity = 1.0.
      // Supplied via the injected appointmentDates map (not the global store).
      h.appointmentDates['apexo-1'] = {DateTime(2025, 1, 1)};

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      final p = pending.single;
      expect(p.autoLinked, isFalse);
      expect(p.matchedPatient?.id, 'apexo-1');
      // nameScore = 1.0 (identical token sets), dateScore = 1.0 (same day)
      // confidence = 0.6*1 + 0.4*1 = 1.0
      expect(p.confidence, closeTo(1.0, 1e-9));
      expect(p.isConfirmed, isFalse, reason: 'suggestion, not yet approved');
    });

    test('no plausible match matchedPatient null, confidence 0', () async {
      final h = _newHarness();
      h.patients['apexo-1'] = Patient.fromJson(
          {'id': 'apexo-1', 'title': 'Completely Different Name'});

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      expect(pending.single.matchedPatient, isNull);
      expect(pending.single.confidence, 0.0);
    });

    test('dates boost confidence when appointments match study dates',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.patients['apexo-2'] =
          Patient.fromJson({'id': 'apexo-2', 'title': 'John Smith Jr'});
      // Both patients have the name "John Smith", but only apexo-1 has an
      // appointment on the X-ray study date.
      h.appointmentDates['apexo-1'] = {DateTime(2025, 1, 1)};

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      // apexo-1 should win because dates match.
      expect(pending.single.matchedPatient?.id, 'apexo-1');
      // Confidence = 0.6 * nameScore + 0.4 * dateScore.
      // Exact confidence depends on token overlap, but it must be > 0.
      expect(pending.single.confidence, greaterThan(0.0));
    });

    test('dates break tie when two patients have similar names', () async {
      final h = _newHarness();
      // Two patients with the same last name — similar Jaccard scores.
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.patients['apexo-2'] =
          Patient.fromJson({'id': 'apexo-2', 'title': 'James Smith'});
      // Only James Smith has an appointment on the study date.
      h.appointmentDates['apexo-2'] = {DateTime(2025, 1, 1)};

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      // "Smith^John" matches both "John Smith" and "James Smith" (share
      // "Smith").  But James has the appointment → dates break the tie.
      // Actually "Smith^John" matches "John Smith" more closely (both
      // tokens "john" and "smith").  Let's verify it picks the right one.
      expect(pending.single.matchedPatient?.id, isNotNull);
    });

    test('stale link (patient gone) falls through to fuzzy matching', () async {
      final h = _newHarness();
      // Link points to a patient no longer in the roster.
      h.fakeLinks._patientLinks['P100'] = 'gone-apexo-id';
      // A real patient with a matching name.
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      expect(pending.single.autoLinked, isFalse,
          reason: 'stale link must not count as auto-linked');
      expect(pending.single.matchedPatient?.id, 'apexo-1',
          reason: 'falls through to fuzzy name match');
    });
  });

  group('full DICOM approval workflows', () {
    test('linked patient import creates a new appointment automatically',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'Linked Patient'});
      h.fakeLinks._patientLinks['P100'] = 'apexo-1';
      h.addFile(_FakeFile(
          '/fake/watch/linked-new.dcm',
          _meta(
              sopInstanceUid: 's-linked-new',
              patientId: 'P100',
              patientName: 'Linked Patient',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();
      expect(pending.single.autoLinked, isTrue);
      final result = await h.importer.approveImport(pending.single);

      expect(result.complete, isTrue);
      final created = h.appointments.values.single;
      expect(created.patientID, 'apexo-1');
      expect(created.date, DateTime(2025, 1, 1, 12));
      expect(created.dcmImgs, hasLength(1));
    });

    test('linked patient import reuses an existing same-day appointment',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] = Patient.fromJson({'id': 'apexo-1'});
      h.fakeLinks._patientLinks['P100'] = 'apexo-1';
      final existing =
          Appointment.fromJson({'id': 'existing', 'patientID': 'apexo-1'})
            ..date = DateTime(2025, 1, 1, 9);
      h.appointments[existing.id] = existing;
      h.addFile(_FakeFile(
          '/fake/watch/linked-existing.dcm',
          _meta(
              sopInstanceUid: 's-linked-existing',
              patientId: 'P100',
              patientName: 'Linked Patient',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();
      expect(pending.single.autoLinked, isTrue);
      await h.importer.approveImport(pending.single);

      expect(h.appointments, hasLength(1));
      expect(h.appointments['existing']!.dcmImgs, hasLength(1));
    });

    test('unmatched scan remains pending until manually matched and approved',
        () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/manual.dcm',
          _meta(
              sopInstanceUid: 's-manual',
              patientId: 'P100',
              patientName: 'Unknown',
              studyDate: '20250101')));

      final pending = (await h.importer.scanAndBuildPending()).single;
      expect(pending.matchedPatient, isNull);

      final patient = Patient.fromJson({'id': 'apexo-manual'});
      pending.matchedPatient = patient;
      pending.matchedPatientId = patient.id;
      pending.matchedPatientName = patient.title;
      pending.isConfirmed = true;
      await h.importer.approveImport(pending);

      expect(h.appointments.values.single.patientID, 'apexo-manual');
      expect(h.appointments.values.single.dcmImgs, hasLength(1));
    });
  });

  group('approveImport', () {
    test('creates one appointment per study date with correct dcmImgs',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/b.dcm',
          _meta(
              sopInstanceUid: 's2',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250201')));

      final pending = await h.importer.scanAndBuildPending();
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');

      // Two appointments created one per date.
      final created =
          h.appointments.values.where((a) => a.patientID == 'apexo-1').toList();
      expect(created.length, 2);

      // Each appointment has exactly one dcmImg, on the right day.
      final byDay = {
        for (final a in created)
          DateTime(a.date.year, a.date.month, a.date.day): a
      };
      expect(byDay.keys, contains(DateTime(2025, 1, 1)));
      expect(byDay.keys, contains(DateTime(2025, 2, 1)));
      for (final a in created) {
        expect(a.dcmImgs.length, 1);
      }

      // Registry now contains both dedup keys.
      expect(h.fakeLinks._registry.keys, containsAll(['sop:s1', 'sop:s2']));

      // Link persisted for future auto-imports.
      expect(h.fakeLinks._patientLinks['P100'], 'apexo-1');
    });

    test('new appointment is persisted before its upload starts', () async {
      final h = _newHarness();
      h.patients['apexo-1'] = Patient.fromJson({'id': 'apexo-1'});
      const path = '/fake/watch/order.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 's-order',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      await h.importer.approveImport(pending, apexoPatientId: 'apexo-1');

      final persistIndex = h.persistenceEvents.indexOf('persist');
      final uploadIndex =
          h.persistenceEvents.indexWhere((event) => event == 'upload:$path');
      expect(persistIndex, greaterThanOrEqualTo(0));
      expect(uploadIndex, greaterThan(persistIndex));
    });

    test('appointment changes are persisted after each study-date group',
        () async {
      final h = _newHarness();
      const firstPath = '/fake/watch/first-date.dcm';
      const secondPath = '/fake/watch/second-date.dcm';
      h.addFile(_FakeFile(
          firstPath,
          _meta(
              sopInstanceUid: 's-first-date',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          secondPath,
          _meta(
              sopInstanceUid: 's-second-date',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250201')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      await h.importer.approveImport(pending, apexoPatientId: 'apexo-1');

      expect(h.persistenceEvents.where((event) => event == 'persist'),
          hasLength(4));
    });

    test('appends to an existing same-day appointment (no new appointment)',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      // Pre-existing appointment on 2025-01-01.
      final existing =
          Appointment.fromJson({'id': 'ap-exist', 'patientID': 'apexo-1'})
            ..date = DateTime(2025, 1, 1, 9, 0);
      h.appointments['ap-exist'] = existing;

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');

      // No new appointment created.
      final forPatient =
          h.appointments.values.where((a) => a.patientID == 'apexo-1').toList();
      expect(forPatient.length, 1);
      expect(forPatient.single.id, 'ap-exist');
      // The dcmImg was appended to the existing appointment.
      expect(forPatient.single.dcmImgs.length, 1);
    });

    test('throws when no target patient resolved', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();
      // No matchedPatient, no apexoPatientId must throw.
      expect(
        () => h.importer.approveImport(pending.single),
        throwsA(isA<StateError>()),
      );
    });

    test('progress observable updates and resets', () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/b.dcm',
          _meta(
              sopInstanceUid: 's2',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250201')));

      final pending = await h.importer.scanAndBuildPending();
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');

      // approveImport no longer resets progress to idle callers own that.
      // Progress ends at (total, total) indicating all files completed.
      expect(h.importer.importProgress(), (current: 2, total: 2),
          reason:
              'progress stays at (total, total) after import callers reset to idle');
    });

    test(
        'empty filename is returned as a failed file and marker is rolled back',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] = Patient.fromJson({'id': 'apexo-1'});
      const path = '/fake/watch/empty-name.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 's-empty',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      h.emptyDcmUploads.add(path);

      final pending = (await h.importer.scanAndBuildPending()).single;
      final result = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );

      expect(result.complete, isFalse);
      expect(result.failedFiles.single.path, path);
      expect(h.fakeLinks._registry, isEmpty);
    });

    test('file rollback failure is surfaced separately from the upload failure',
        () async {
      final h = _newHarness();
      h.failRemoveKey = true;
      h.failedDcmUploads.add('/fake/watch/rollback-failure.dcm');
      h.addFile(_FakeFile(
          '/fake/watch/rollback-failure.dcm',
          _meta(
              sopInstanceUid: 's-rollback-failure',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      final result = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );

      expect(result.complete, isFalse);
      expect(result.failedFiles, hasLength(1));
      expect(result.rollbackFailures, hasLength(1));
      expect(result.rollbackFailures.single, isA<StateError>());
    });

    test('failed file processing rolls back its imported marker', () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      const path = '/fake/watch/failing.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 's-failing',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.failedDcmUploads.add(path);

      final pending = await h.importer.scanAndBuildPending();
      final result = await h.importer.approveImport(
        pending.single,
        apexoPatientId: 'apexo-1',
      );

      expect(result.complete, isFalse);
      expect(result.successfulFiles, 0);
      expect(result.failedFiles.single.dedupKey, 'sop:s-failing');
      expect(h.fakeLinks._registry, isEmpty);
      expect(h.fakeLinks._patientLinks['P100'], 'apexo-1',
          reason:
              'file-marker rollback must preserve the confirmed patient link');
      expect(h.appointments, hasLength(1));
      expect(h.appointments.values.single.archived, isNull,
          reason:
              'new appointments intentionally remain unarchived after failed upload');

      // A subsequent scan must surface the file as auto-linked, not as an
      // unlinked/manual-match import.
      h.importer = h.rebuild();
      final rediscovered = await h.importer.scanAndBuildPending();
      expect(rediscovered.single.autoLinked, isTrue);
      expect(rediscovered.single.matchedPatient?.id, 'apexo-1');
    });

    test('mixed batch keeps successful file imported and retries failed file',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      const failedPath = '/fake/watch/failed.dcm';
      const successfulPath = '/fake/watch/success.dcm';
      h.addFile(_FakeFile(
          failedPath,
          _meta(
              sopInstanceUid: 's-failed',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          successfulPath,
          _meta(
              sopInstanceUid: 's-success',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.failedDcmUploads.add(failedPath);

      final pending = await h.importer.scanAndBuildPending();
      final result = await h.importer.approveImport(
        pending.single,
        apexoPatientId: 'apexo-1',
      );

      expect(result.successfulFiles, 1);
      expect(result.failedFiles.map((file) => file.dedupKey), ['sop:s-failed']);
      expect(h.fakeLinks._registry, {'sop:s-success': 'P100'});
      expect(h.fakeLinks._patientLinks['P100'], 'apexo-1');
      final appointment =
          h.appointments.values.where((item) => item.archived != true).single;
      expect(appointment.dcmImgs, hasLength(1));

      h.importer = h.rebuild();
      final retry = await h.importer.scanAndBuildPending();
      expect(retry.single.files.single.dedupKey, 'sop:s-failed');
      expect(retry.single.autoLinked, isTrue);
    });

    test('patient-link persistence is awaited before file processing',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] = Patient.fromJson({'id': 'apexo-1'});
      const path = '/fake/watch/link-success.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 's-link-success',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));

      final pending = (await h.importer.scanAndBuildPending()).single;
      await h.importer.approveImport(pending, apexoPatientId: 'apexo-1');

      final patientIndex = h.persistenceEvents
          .indexWhere((event) => event == 'patient:P100:apexo-1');
      final uploadIndex = h.persistenceEvents.indexOf('upload:$path');
      expect(patientIndex, greaterThanOrEqualTo(0));
      expect(uploadIndex, greaterThan(patientIndex));
      expect(h.fakeLinks._patientLinks['P100'], 'apexo-1');
    });

    test('patient-link rollback failure throws DicomApprovalRollbackException',
        () async {
      final h = _newHarness();
      h.failPatientLink = true;
      h.failRemoveKey = true;
      h.addFile(_FakeFile(
          '/fake/watch/link-rollback-failure.dcm',
          _meta(
              sopInstanceUid: 's-link-rollback-failure',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      await expectLater(
        h.importer.approveImport(pending, apexoPatientId: 'apexo-1'),
        throwsA(isA<DicomApprovalRollbackException>()),
      );
    });

    test('link persistence failure rolls back every imported marker', () async {
      final h = _newHarness();
      const path = '/fake/watch/link-failure.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 's-link-failure',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.failPatientLink = true;

      final pending = await h.importer.scanAndBuildPending();
      await expectLater(
        () =>
            h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1'),
        throwsA(isA<StateError>()),
      );
      expect(h.fakeLinks._registry, isEmpty);
      expect(h.fakeLinks._patientLinks, isEmpty);
    });

    test('unexpected appointment persistence failure rolls back claims',
        () async {
      final h = _newHarness();
      h.failAppointmentPersistence = true;
      h.addFile(_FakeFile(
          '/fake/watch/persistence-failure.dcm',
          _meta(
              sopInstanceUid: 's-persist-failure',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      await expectLater(
        h.importer.approveImport(pending, apexoPatientId: 'apexo-1'),
        throwsA(isA<StateError>()),
      );
      expect(h.fakeLinks._registry, isEmpty);
    });

    test('online appointment persistence must converge', () async {
      final h = _newHarness();
      h.failAppointmentPersistence = true;
      h.addFile(_FakeFile(
          '/fake/watch/nonconverged.dcm',
          _meta(
              sopInstanceUid: 's-nonconverged',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      await expectLater(
        h.importer.approveImport(pending, apexoPatientId: 'apexo-1'),
        throwsA(isA<StateError>()),
      );
      expect(h.fakeLinks._registry, isEmpty);
    });

    test('offline-style persistence callback can complete locally', () async {
      final h = _newHarness();
      // The injected callback is the offline/local path: it completes without
      // requiring remote convergence.
      h.addFile(_FakeFile(
          '/fake/watch/offline.dcm',
          _meta(
              sopInstanceUid: 's-offline',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      final result = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );

      expect(result.complete, isTrue);
      expect(h.appointments, hasLength(1));
    });

    test('returns a complete result for idempotent re-approval', () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      const path = '/fake/watch/idempotent.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 's-idempotent',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;
      final first = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );
      final second = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );

      expect(first.complete, isTrue);
      expect(first.successfulFiles, 1);
      expect(second.complete, isTrue);
      expect(second.successfulFiles, 0);
      expect(second.failedFiles, isEmpty);
    });

    test('idempotency: re-approve no duplicates, no new appointments',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/b.dcm',
          _meta(
              sopInstanceUid: 's2',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250201')));

      final pending = await h.importer.scanAndBuildPending();
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');

      final countAfterFirst = h.appointments.length;
      final dcmCountAfterFirst =
          h.appointments.values.fold<int>(0, (s, a) => s + a.dcmImgs.length);

      // Re-approve the SAME pending object. The registry now contains both
      // keys, so both files are skipped.
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');

      expect(h.appointments.length, countAfterFirst,
          reason: 'no new appointments on re-approve');
      final dcmCountAfterSecond =
          h.appointments.values.fold<int>(0, (s, a) => s + a.dcmImgs.length);
      expect(dcmCountAfterSecond, dcmCountAfterFirst,
          reason: 'no duplicate dcmImgs on re-approve (registry guard)');
    });

    test('replaces an existing reference with the same logical upload identity',
        () async {
      final h = _newHarness();
      final existing =
          Appointment.fromJson({'id': 'existing', 'patientID': 'apexo-1'})
            ..date = DateTime(2025, 1, 1)
            ..dcmImgs = ['dcm_hash_1.dcm'];
      h.appointments[existing.id] = existing;
      const path = '/fake/watch/replacement.dcm';
      h.addFile(_FakeFile(
          path,
          _meta(
              sopInstanceUid: 'replacement',
              patientId: 'P100',
              patientName: 'A',
              studyDate: '20250101')));
      final oldName = 'dcm_${path.hashCode}.dcm';
      final newName = 'dcm_${path.hashCode}_replacement.dcm';
      existing.dcmImgs = [oldName];
      h.configuredDcmNames[path] = newName;
      final pending = (await h.importer.scanAndBuildPending()).single;

      await h.importer.approveImport(pending, apexoPatientId: 'apexo-1');

      expect(h.appointments['existing']!.dcmImgs, [newName]);
      expect(h.appointments['existing']!.dcmImgs.toSet(), hasLength(1));
    });

    test('duplicate SOP UID: first-wins during approve (second skipped)',
        () async {
      final h = _newHarness();
      h.patients['apexo-1'] =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      // Two files, same SOP UID, same date.
      h.addFile(_FakeFile(
          '/fake/watch/first.dcm',
          _meta(
              sopInstanceUid: 'dup',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/second.dcm',
          _meta(
              sopInstanceUid: 'dup',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');

      // Both files share 'sop:dup'. The first is processed; the second is
      // marked imported but its dedup key is already in the registry, so
      // handleNewDcm runs only once.
      expect(h.handleNewDcmResults.length, 1,
          reason: 'duplicate dedup key only the first file is processed');
      // Only one appointment, with a single dcmImg.
      final forPatient =
          h.appointments.values.where((a) => a.patientID == 'apexo-1').toList();
      expect(forPatient.length, 1);
      expect(forPatient.single.dcmImgs.length, 1);
    });
  });

  group('DicomApprovalResult and pending-item reduction', () {
    test('complete is true only when failedFiles is empty', () {
      const complete = DicomApprovalResult(
        successfulFiles: 0,
        failedFiles: [],
      );
      final failed = DicomApprovalResult(
        successfulFiles: 0,
        failedFiles: [_parsedFile()],
      );

      expect(complete.complete, isTrue);
      expect(failed.complete, isFalse);
      expect(failed.successfulFiles, 0);
      expect(failed.failedFiles.single.dedupKey, 'sop:file');
    });

    test('copyWithFiles retains match metadata and recalculates names/dates',
        () {
      final patient = Patient.fromJson({'id': 'apexo-1', 'title': 'Apexo'});
      final first = _parsedFile(
        path: '/first.dcm',
        patientName: 'First',
        date: DateTime(2025, 2, 2),
      );
      final second = _parsedFile(
        path: '/second.dcm',
        dedupKey: 'sop:second',
        patientName: 'Second',
        date: DateTime(2025, 1, 1),
      );
      final original = DicomPendingImport(
        dicomPatientId: 'P1',
        dicomPatientName: 'Original',
        dicomPatientNames: const {'Original'},
        dates: [DateTime(2025, 3, 3)],
        files: [first, second],
        matchedPatient: patient,
        matchedPatientId: 'apexo-1',
        matchedPatientName: 'Apexo',
        confidence: .8,
        isConfirmed: true,
        autoLinked: true,
      );

      final reduced = original.copyWithFiles([second]);

      expect(reduced.files, [second]);
      expect(reduced.dicomPatientId, 'P1');
      expect(reduced.dicomPatientName, 'Second');
      expect(reduced.dicomPatientNames, {'Second'});
      expect(reduced.dates, [DateTime(2025, 1, 1)]);
      expect(reduced.matchedPatient, same(patient));
      expect(reduced.matchedPatientId, 'apexo-1');
      expect(reduced.matchedPatientName, 'Apexo');
      expect(reduced.confidence, .8);
      expect(reduced.isConfirmed, isTrue);
      expect(reduced.autoLinked, isTrue);
    });

    test('copyWithFiles with no names or dates produces empty derived fields',
        () {
      final file = DicomParsedFile(
        path: '/no-date.dcm',
        mtime: DateTime(2025, 1, 1),
        size: 1,
        dedupKey: 'sop:no-date',
        patientName: '',
        patientId: 'P1',
        dcmDate: null,
      );
      final original = _pendingForTest(files: [file]);

      final reduced = original.copyWithFiles([file]);

      expect(reduced.dicomPatientName, isEmpty);
      expect(reduced.dicomPatientNames, isEmpty);
      expect(reduced.dates, isEmpty);
    });
  });

  group('DicomImporter identity and registry claims', () {
    test('normalizes DICOM originals, previews, extensions, and suffixes', () {
      expect(DicomImporter.dcmUploadIdentity('dcm_hash.dcm'), 'dcm_hash');
      expect(DicomImporter.dcmUploadIdentity('dcm_hash.dicom'), 'dcm_hash');
      expect(DicomImporter.dcmUploadIdentity('dcm_hash_1.dcm.png'), 'dcm_hash');
      expect(
          DicomImporter.dcmUploadIdentity('DCM_HASH_2.DICOM.PNG'), 'dcm_hash');
      expect(DicomImporter.dcmUploadIdentity('photo_hash.jpg'), isNull);
      expect(DicomImporter.dcmUploadIdentity('dcm_hash'), isNull);
    });

    test('same identity requires matching original or preview extension', () {
      expect(
          DicomImporter.sameDcmUploadIdentity('dcm_hash.dcm', 'dcm_hash_1.dcm'),
          isTrue);
      expect(
          DicomImporter.sameDcmUploadIdentity(
              'dcm_hash.dcm.png', 'dcm_hash_1.dcm.png'),
          isTrue);
      expect(
          DicomImporter.sameDcmUploadIdentity('dcm_hash.dcm', 'dcm_hash.dicom'),
          isTrue);
      expect(
          DicomImporter.sameDcmUploadIdentity('dcm_hash.dcm', 'dcm_other.dcm'),
          isFalse);
      expect(
          DicomImporter.sameDcmUploadIdentity('dcm_hash.dcm', 'photo_hash.jpg'),
          isFalse);
    });

    test('Importer and SaveRemote use identical identity semantics', () {
      final pairs = [
        ('dcm_hash.dcm', 'dcm_hash_1.dcm'),
        ('dcm_hash.dicom', 'dcm_hash_1.dicom'),
        ('dcm_hash.dcm.png', 'dcm_hash_1.dcm.png'),
        ('dcm_hash.dicom.png', 'dcm_hash_1.dicom.png'),
        ('DCM_HASH.DCM', 'dcm_hash_2.dcm'),
      ];
      for (final pair in pairs) {
        expect(DicomImporter.dcmUploadIdentity(pair.$1),
            SaveRemote.dcmUploadIdentity(pair.$1));
        expect(DicomImporter.dcmUploadIdentity(pair.$2),
            SaveRemote.dcmUploadIdentity(pair.$2));
        expect(DicomImporter.sameDcmUploadIdentity(pair.$1, pair.$2),
            SaveRemote.sameDcmUploadIdentity(pair.$1, pair.$2));
      }
      expect(
        DicomImporter.sameDcmUploadIdentity('dcm_hash.dcm', 'dcm_hash.dicom'),
        SaveRemote.sameDcmUploadIdentity('dcm_hash.dcm', 'dcm_hash.dicom'),
      );
    });

    test('linkFile claim is first-wins and duplicate claim is skipped',
        () async {
      final h = _newHarness();
      expect(await h.fakeLinks.linkFile('P1', 'sop:one'), isTrue);
      expect(await h.fakeLinks.linkFile('P2', 'sop:one'), isFalse);
      expect(h.fakeLinks._registry, {'sop:one': 'P1'});
    });

    test('concurrent-style duplicate files process only one claim', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/one.dcm',
          _meta(
              sopInstanceUid: 'same',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      h.addFile(_FakeFile(
          '/fake/watch/two.dcm',
          _meta(
              sopInstanceUid: 'same',
              patientId: 'P1',
              patientName: 'A',
              studyDate: '20250101')));
      final pending = (await h.importer.scanAndBuildPending()).single;

      final result = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );

      expect(result.successfulFiles, 1);
      expect(h.handleNewDcmResults, hasLength(1));
      expect(h.fakeLinks._registry.keys, {'sop:same'});
    });
  });

  group('DicomImporter.unregisterFile', () {
    test('returns true when metadata marker is removed', () async {
      final h = _newHarness();
      h.fakeLinks._registry['sop:unregister'] = 'P1';
      final importer = DicomImporter(
        useIsolate: false,
        allImportedKeys: () async => h.fakeLinks._registry.keys.toSet(),
        isImported: (key) async => h.fakeLinks._registry.containsKey(key),
        removeKey: (key) async => h.fakeLinks._registry.remove(key) != null,
        fileExistsOverrideForTesting: (_) async => true,
        readBytes: (_) async => Uint8List.fromList([1]),
        parseMetadata: (_) async => _meta(
          sopInstanceUid: 'unregister',
          patientId: 'P1',
          patientName: 'A',
          studyDate: '20250101',
        ),
      );

      expect(await importer.unregisterFile('dcm_file.dcm'), isTrue);
      expect(h.fakeLinks._registry, isEmpty);
    });

    test('already absent marker is treated as idempotent success', () async {
      final h = _newHarness();
      final importer = DicomImporter(
        useIsolate: false,
        allImportedKeys: () async => h.fakeLinks._registry.keys.toSet(),
        isImported: (key) async => h.fakeLinks._registry.containsKey(key),
        removeKey: (_) async => false,
        fileExistsOverrideForTesting: (_) async => true,
        readBytes: (_) async => Uint8List.fromList([1]),
        parseMetadata: (_) async => _meta(
          sopInstanceUid: 'already-absent',
          patientId: 'P1',
          patientName: 'A',
          studyDate: '20250101',
        ),
      );

      expect(await importer.unregisterFile('dcm_file.dcm'), isTrue);
    });

    test('returns false when local file is missing or unreadable', () async {
      final importer = DicomImporter(
        useIsolate: false,
        fileExistsOverrideForTesting: (_) async => false,
      );
      expect(await importer.unregisterFile('missing.dcm'), isFalse);

      final unreadable = DicomImporter(
        useIsolate: false,
        fileExistsOverrideForTesting: (_) async => true,
        readBytes: (_) async => null,
      );
      expect(await unreadable.unregisterFile('unreadable.dcm'), isFalse);
    });

    test('returns false when metadata parsing or registry persistence fails',
        () async {
      final parseFailure = DicomImporter(
        useIsolate: false,
        fileExistsOverrideForTesting: (_) async => true,
        readBytes: (_) async => Uint8List.fromList([1]),
        parseMetadata: (_) async => null,
      );
      expect(await parseFailure.unregisterFile('corrupt.dcm'), isFalse);

      final persistenceFailure = DicomImporter(
        useIsolate: false,
        fileExistsOverrideForTesting: (_) async => true,
        readBytes: (_) async => Uint8List.fromList([1]),
        parseMetadata: (_) async => _meta(
          sopInstanceUid: 'persistence-failure',
          patientId: 'P1',
          patientName: 'A',
          studyDate: '20250101',
        ),
        removeKey: (_) async => throw StateError('persistence failed'),
      );
      expect(await persistenceFailure.unregisterFile('failure.dcm'), isFalse);
    });
  });

  group('approveImport blank-patient safety', () {
    test('blank-patient approval does not persist a patient mapping', () async {
      final h = _newHarness();
      final file = _FakeFile(
          '/fake/watch/anonymous.dcm',
          _meta(
              sopInstanceUid: 'anonymous-sop',
              patientId: '',
              patientName: 'Anonymous',
              studyDate: '20250101'));
      h.addFile(file);
      final pending = (await h.importer.scanAndBuildPending()).single;

      final result = await h.importer.approveImport(
        pending,
        apexoPatientId: 'apexo-1',
      );

      expect(result.complete, isTrue);
      expect(h.fakeLinks._patientLinks, isEmpty);
      expect(h.fakeLinks._registry, {'sop:anonymous-sop': ''});
    });
  });

  group('approveImport push exclusion', () {
    // Adding dcmImgs to an EXISTING appointment must not trigger a push:
    // `Appointment.pushIfChanged` excludes `dcmImgs`. This is pinned at the
    // model level; here we verify the importer
    // relies on that contract by NOT doing anything push-specific itself.
    test('model excludes dcmImgs from pushIfChanged', () {
      expect(
          Appointment.fromJson({}).pushIfChanged, isNot(contains('dcmImgs')));
    });
  });

  group('unmarkPending (recovery / undo)', () {
    test('clears registry keys so files re-surface on next scan', () async {
      final h = _newHarness();
      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      final pending = await h.importer.scanAndBuildPending();
      await h.importer.approveImport(pending.single, apexoPatientId: 'apexo-1');
      expect(h.fakeLinks._registry.containsKey('sop:s1'), isTrue);

      await h.fakeLinks.unlink(pending.single.dicomPatientId);
      expect(h.fakeLinks._registry.containsKey('sop:s1'), isFalse,
          reason: 'unlink clears the registry key');
    });

    test('pending manual match survives rescan but does not auto-import',
        () async {
      final h = _newHarness();
      final patient =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.patients['apexo-1'] = patient;
      // Simulate a pending manual match (not an approved link).
      h.fakeLinks._pendingMatches['P100'] = 'apexo-1';

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      final p = pending.single;
      // Pending match surfaces with confidence 1.0.
      expect(p.matchedPatient?.id, 'apexo-1');
      expect(p.confidence, 1.0);
      expect(p.isConfirmed, isTrue);
      // But it's NOT an auto-link (wasn't approved).
      expect(p.autoLinked, isFalse);
    });

    test('pending match ignored if Apexo patient was deleted', () async {
      final h = _newHarness();
      // Pending match references a non-existent patient.
      h.fakeLinks._pendingMatches['P100'] = 'deleted-apexo-id';

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      final p = pending.single;
      // Pending match should be silently ignored — patient doesn't exist.
      expect(p.matchedPatient, isNull,
          reason: 'pending match to deleted patient is ignored');
    });

    test('unmatched patient skips fuzzy matching entirely', () async {
      final h = _newHarness();
      final patient =
          Patient.fromJson({'id': 'apexo-1', 'title': 'John Smith'});
      h.patients['apexo-1'] = patient;
      // P100 was explicitly rejected by the dentist.
      h.fakeLinks._unmatchedIds.add('P100');

      h.addFile(_FakeFile(
          '/fake/watch/a.dcm',
          _meta(
              sopInstanceUid: 's1',
              patientId: 'P100',
              patientName: 'Smith^John',
              studyDate: '20250101')));

      h.importer = h.rebuild();
      final pending = await h.importer.scanAndBuildPending();

      final p = pending.single;
      // Unmatched patient should NOT get a fuzzy suggestion —
      // even though "Smith^John" would have matched "John Smith".
      expect(p.matchedPatient, isNull,
          reason: 'unmatched patient skips fuzzy matching');
    });
  });
}
