import 'dart:async';
import 'dart:isolate';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_matched_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_unmatched_store.dart';
import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:apexo/services/dicom/dicom_helpers.dart' as dcm_helpers;
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/dicom/dicom_normalize.dart';
import 'package:apexo/services/dicom/dicom_skipped.dart';
import 'package:apexo/utils/imgs.dart' as imgs;
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:flutter/foundation.dart';

/// Extracts the last path component for debug logging.
String _shortName(String path) => path.split(RegExp(r'[/\\]')).last;

// --------------- Data classes ------------------

class DicomParsedFile {
  const DicomParsedFile({
    required this.path,
    required this.mtime,
    required this.size,
    required this.dedupKey,
    required this.patientName,
    required this.patientId,
    required this.dcmDate,
  });
  final String path;
  final DateTime mtime;
  final int size;
  final String dedupKey;
  final String patientName;
  final String patientId;
  final DateTime? dcmDate;

  /// Study date, else the file's mtime — never epoch, which would bury an
  /// undated X-ray decades in the past.
  DateTime get effectiveDate => dcmDate ?? mtime;

  @override
  String toString() =>
      'DicomParsedFile(path: $path, dedupKey: $dedupKey, patientId: $patientId, '
      'dcmDate: $dcmDate)';
}

class DicomParsedMeta {
  const DicomParsedMeta({
    required this.sopInstanceUid,
    required this.studyInstanceUid,
    required this.seriesInstanceUid,
    required this.instanceNumber,
    required this.patientName,
    required this.patientId,
    required this.dcmDate,
    this.isVolumetric = false,
  });

  factory DicomParsedMeta.fromDicomMetadata(DicomMetadata m) => DicomParsedMeta(
        sopInstanceUid: m.sopInstanceUid,
        studyInstanceUid: m.studyInstanceUid,
        seriesInstanceUid: m.seriesInstanceUid,
        instanceNumber: m.instanceNumber,
        patientName: m.patientName,
        patientId: m.patientId,
        dcmDate: m.bestDate,
        isVolumetric: m.isVolumetric,
      );
  final String sopInstanceUid;
  final String studyInstanceUid;
  final String seriesInstanceUid;
  final String instanceNumber;
  final String patientName;
  final String patientId;
  final DateTime? dcmDate;
  final bool isVolumetric;

  String get dedupKey => dedupKeyFromValues(
        sopInstanceUid: sopInstanceUid,
        studyInstanceUid: studyInstanceUid,
        seriesInstanceUid: seriesInstanceUid,
        instanceNumber: instanceNumber,
      );
}

class DicomPendingImport {
  DicomPendingImport({
    required this.dicomPatientId,
    required this.dicomPatientName,
    required this.dicomPatientNames,
    required this.dates,
    required this.files,
    this.matchedPatient,
    this.matchedPatientId,
    this.matchedPatientName,
    this.confidence = 0.0,
    this.isConfirmed = false,
    this.autoLinked = false,
  });
  final String dicomPatientId;
  final String dicomPatientName;
  final Set<String> dicomPatientNames;
  final List<DateTime> dates;
  final List<DicomParsedFile> files;
  Patient? matchedPatient;
  String? matchedPatientId;
  String? matchedPatientName;
  double confidence;
  bool isConfirmed;
  final bool autoLinked;

  int get fileCount => files.length;

  /// Identity for selection and persisted hints. Anonymous batches fall back
  /// to the first file's dedup key so they don't all share the empty string.
  String get selectionKey => dicomPatientId.isNotEmpty
      ? dicomPatientId
      : (files.isNotEmpty ? 'anonymous:${files.first.dedupKey}' : 'anonymous');

  DicomPendingImport copyWithFiles(List<DicomParsedFile> nextFiles) {
    final nextNames = nextFiles
        .map((file) => file.patientName)
        .where((name) => name.isNotEmpty)
        .toSet();
    final nextDates = nextFiles
        .map((file) => file.dcmDate)
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort();
    final nextName = nextNames.isNotEmpty ? nextNames.first : '';
    final nextMatched = matchedPatient;
    return DicomPendingImport(
      dicomPatientId: dicomPatientId,
      dicomPatientName: nextName,
      dicomPatientNames: nextNames,
      dates: nextDates,
      files: nextFiles,
      matchedPatient: nextMatched,
      matchedPatientId: nextMatched?.id ?? matchedPatientId,
      matchedPatientName: nextMatched?.title ?? matchedPatientName,
      confidence: confidence,
      isConfirmed: isConfirmed,
      autoLinked: autoLinked,
    );
  }
}

/// Outcome of one approval attempt; already-imported files count as success,
/// so re-approving is idempotent.
class DicomApprovalResult {
  const DicomApprovalResult({
    required this.successfulFiles,
    required this.failedFiles,
    this.rollbackFailures = const [],
  });
  final int successfulFiles;
  final List<DicomParsedFile> failedFiles;
  final List<Object> rollbackFailures;

  bool get complete => failedFiles.isEmpty && rollbackFailures.isEmpty;
}

class DicomApprovalRollbackException implements Exception {
  const DicomApprovalRollbackException({
    required this.cause,
    required this.rollbackFailures,
  });
  final Object cause;
  final List<Object> rollbackFailures;

  @override
  String toString() =>
      'DicomApprovalRollbackException: ${rollbackFailures.length} '
      'rollback failure(s); cause: $cause';
}

// --------------- Isolate message types ----------------------

class _ScanMessage {
  const _ScanMessage(
    this.watchDir,
    this.importedKeys,
    this.cacheSnapshot,
    this.patientSnapshots,
    this.links,
    this.pendingMatches,
    this.unmatchedIds,
    this.appointmentDayMap,
    this.resultPort,
    this.cancelSignalPort,
  );
  final String watchDir;
  final Set<String> importedKeys;
  final Map<String, DicomCachedMeta> cacheSnapshot;
  final List<_PatientSnapshot> patientSnapshots;
  final Map<String, String> links;
  final Map<String, String> pendingMatches;
  final Set<String> unmatchedIds;
  final Map<String, Set<DateTime>> appointmentDayMap;
  final SendPort resultPort;
  final SendPort? cancelSignalPort;
}

class _PatientSnapshot {
  const _PatientSnapshot(this.id, this.title);
  final String id;
  final String title;
}

class DicomSkippedRecord {
  const DicomSkippedRecord(this.path, this.reason);
  final String path;
  final String reason;
}

class _ScanResult {
  const _ScanResult({
    required this.parsed,
    required this.newCacheEntries,
    required this.allScannedPaths,
    required this.skipped,
    this.scanDirMs = 0,
    this.parseLoopMs = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.perFileMs = const {},
    this.pending = const [],
  });
  final List<DicomParsedFile> parsed;
  final Map<String, DicomCachedMeta> newCacheEntries;
  final Set<String> allScannedPaths;
  final List<DicomSkippedRecord> skipped;
  final int scanDirMs;
  final int parseLoopMs;
  final int cacheHits;
  final int cacheMisses;
  final Map<String, int> perFileMs;
  final List<DicomPendingImport> pending;
}

/// Minimum confidence to surface a fuzzy suggestion.
const double _suggestionThreshold = 0.4;

// --------------- Scan phase ---------------------

enum ScanPhase {
  idle,
  snapshotting,
  listingDir,
  scanningFiles,
  persisting,
  matching,
}

// --------------- Import phase ---------------------

/// Import phases. `syncing` is separate because the final server sync can
/// block for seconds after the last file has uploaded.
enum ImportPhase { idle, uploading, syncing }

// --------------- Core scan + parse + match ------------------------------------------------------------------

Future<_ScanResult> _doScan({
  required String watchDir,
  required Set<String> importedKeys,
  required Map<String, DicomCachedMeta> cacheSnapshot,
  required List<_PatientSnapshot> patientSnapshots,
  required Map<String, String> links,
  required Map<String, String> pendingMatches,
  required Set<String> unmatchedIds,
  required Map<String, Set<DateTime>> appointmentDayMap,
  required Future<List<DicomFileEntry>> Function(String) scanFn,
  required Future<Uint8List?> Function(String) readFn,
  required Future<DicomParsedMeta?> Function(Uint8List) parseFn,
  void Function(int current, int total, String path, bool cacheHit)?
      onFileProgress,
  bool Function()? shouldCancel,
}) async {
  final parsed = <DicomParsedFile>[];
  final newCacheEntries = <String, DicomCachedMeta>{};
  final allScannedPaths = <String>{};
  final skipped = <DicomSkippedRecord>[];

  final scanDirSw = Stopwatch()..start();
  List<DicomFileEntry> entries;
  try {
    entries = await scanFn(watchDir);
  } catch (e, s) {
    logger('DicomImporter.scan: scanDirectory threw for "$watchDir": $e', s, 2);
    return const _ScanResult(
        parsed: [], newCacheEntries: {}, allScannedPaths: {}, skipped: []);
  }
  scanDirSw.stop();

  final totalEntries = entries.length;

  final parseLoopSw = Stopwatch()..start();
  var cacheHits = 0;
  var cacheMisses = 0;
  var idx = 0;
  final perFileMs = <String, int>{};

  for (final entry in entries) {
    idx++;
    allScannedPaths.add(entry.path);
    if (shouldCancel != null && shouldCancel()) {
      break;
    }

    final cached = cacheSnapshot[entry.path];
    final cacheHit = cached != null &&
        cached.size == entry.size &&
        cached.mtime.toUtc() == entry.mtime.toUtc();

    String dk;
    String patientName;
    String patientId;
    DateTime? dcmDateRaw;

    if (cacheHit) {
      cacheHits++;
      dk = cached.dedupKey;
      patientName = cached.patientName;
      patientId = cached.patientId.trim();
      dcmDateRaw = cached.dcmDate;

      if (!_hasUsableDedupKey(cached.dedupKey)) {
        skipped.add(DicomSkippedRecord(
            entry.path, 'missing DICOM instance identity, skipped'));
        continue;
      }

      // Cached volumetric files are skipped just like freshly-parsed ones.
      if (cached.isVolumetric) {
        if (importedKeys.contains(dk)) continue;
        skipped.add(DicomSkippedRecord(
            entry.path, 'volumetric scan (CBCT/CT), skipped'));
        continue;
      }

      onFileProgress?.call(idx, totalEntries, entry.path, true);
    } else {
      cacheMisses++;
      final fileSw = Stopwatch()..start();
      onFileProgress?.call(idx, totalEntries, entry.path, false);
      final Uint8List bytes;
      try {
        final b = await readFn(entry.path);
        if (b == null || b.isEmpty) {
          skipped.add(DicomSkippedRecord(
              entry.path, 'readBytes returned null/empty (locked or deleted)'));
          continue;
        }
        bytes = b;
      } catch (e) {
        skipped.add(DicomSkippedRecord(entry.path, 'readBytes failed: $e'));
        continue;
      }

      final DicomParsedMeta? meta;
      try {
        meta = await parseFn(bytes);
      } catch (e) {
        skipped.add(DicomSkippedRecord(entry.path, 'parseMetadata threw: $e'));
        continue;
      }
      if (meta == null) {
        skipped.add(DicomSkippedRecord(entry.path,
            'parseMetadata returned null (corrupt or unsupported)'));
        continue;
      }

      // Volumetric scans (CBCT/CT) are hundreds of slices, useless as 2D
      // images; the originals stay on disk for dedicated 3D software.

      if (meta.isVolumetric) {
        skipped.add(DicomSkippedRecord(
            entry.path, 'volumetric scan (CBCT/CT), skipped'));
        // Still cache the metadata so we don't re-parse on every scan.
        newCacheEntries[entry.path] = DicomCachedMeta(
          mtime: entry.mtime,
          size: entry.size,
          dedupKey: meta.dedupKey,
          patientName: meta.patientName,
          patientId: meta.patientId,
          dcmDate: meta.dcmDate,
          isVolumetric: true,
        );
        continue;
      }

      dk = meta.dedupKey;
      patientName = meta.patientName;
      patientId = meta.patientId.trim();
      dcmDateRaw = meta.dcmDate;

      if (meta.sopInstanceUid.trim().isEmpty &&
          (meta.studyInstanceUid.trim().isEmpty ||
              meta.seriesInstanceUid.trim().isEmpty ||
              meta.instanceNumber.trim().isEmpty)) {
        skipped.add(DicomSkippedRecord(
            entry.path, 'missing DICOM instance identity, skipped'));
        newCacheEntries[entry.path] = DicomCachedMeta(
          mtime: entry.mtime,
          size: entry.size,
          dedupKey: dk,
          patientName: meta.patientName,
          patientId: patientId,
          dcmDate: dcmDateRaw,
          isVolumetric: false,
        );
        continue;
      }

      newCacheEntries[entry.path] = DicomCachedMeta(
        mtime: entry.mtime,
        size: entry.size,
        dedupKey: dk,
        patientName: patientName,
        patientId: patientId,
        dcmDate: dcmDateRaw,
      );
      fileSw.stop();
      perFileMs[entry.path] = fileSw.elapsedMilliseconds;
    }

    if (importedKeys.contains(dk)) continue;

    parsed.add(DicomParsedFile(
      path: entry.path,
      mtime: entry.mtime,
      size: entry.size,
      dedupKey: dk,
      patientName: patientName,
      patientId: patientId,
      dcmDate: dcmDateRaw,
    ));
  }

  parseLoopSw.stop();

  // --------------- Build pending list inside the isolate ---
  final matchSw = Stopwatch()..start();
  final pending = _buildPending(parsed, patientSnapshots, links, pendingMatches,
      unmatchedIds, appointmentDayMap);
  matchSw.stop();

  return _ScanResult(
    parsed: parsed,
    newCacheEntries: newCacheEntries,
    allScannedPaths: allScannedPaths,
    skipped: skipped,
    scanDirMs: scanDirSw.elapsedMilliseconds,
    parseLoopMs: parseLoopSw.elapsedMilliseconds,
    cacheHits: cacheHits,
    cacheMisses: cacheMisses,
    perFileMs: perFileMs,
    pending: pending,
  );
}

bool _hasUsableDedupKey(String key) {
  if (key.startsWith('sop:')) {
    return key.substring('sop:'.length).trim().isNotEmpty;
  }
  if (!key.startsWith('composite:')) return false;
  final parts = key.substring('composite:'.length).split('|');
  return parts.length == 3 && parts.every((part) => part.trim().isNotEmpty);
}

double _dateScore(List<DateTime> dicomDates, String candidateId,
    Map<String, Set<DateTime>> appointmentDayMap) {
  if (dicomDates.isEmpty) return 0.0;
  final apptDays = appointmentDayMap[candidateId];
  if (apptDays == null || apptDays.isEmpty) return 0.0;
  var matches = 0;
  for (final d in dicomDates) {
    if (apptDays.contains(DateTime(d.year, d.month, d.day))) matches++;
  }
  return matches / dicomDates.length;
}

List<DicomPendingImport> _buildPending(
  List<DicomParsedFile> parsed,
  List<_PatientSnapshot> patientSnapshots,
  Map<String, String> links,
  Map<String, String> pendingMatches,
  Set<String> unmatchedIds,
  Map<String, Set<DateTime>> appointmentDayMap,
) {
  final groups = <String, List<DicomParsedFile>>{};
  for (final f in parsed) {
    // Blank DICOM patient IDs can't identify a patient, so such files group by
    // their own dedup key instead of all landing in one batch.
    final groupKey = f.patientId.trim().isEmpty
        ? 'anonymous:${f.dedupKey}'
        : 'patient:${f.patientId.trim()}';
    groups.putIfAbsent(groupKey, () => []).add(f);
  }

  final pending = <DicomPendingImport>[];
  for (final entry in groups.entries) {
    final files = entry.value;
    final dicomPatientId = files.first.patientId.trim();
    // Hints and rejections are keyed per batch: the DICOM patient ID, or the
    // anonymous group key, since the empty string would collide.
    final storeKey = dicomPatientId.isEmpty ? entry.key : dicomPatientId;

    final nameCounts = <String, int>{};
    for (final f in files) {
      if (f.patientName.isNotEmpty) {
        nameCounts[f.patientName] = (nameCounts[f.patientName] ?? 0) + 1;
      }
    }
    final sortedNames = nameCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dicomPatientName =
        sortedNames.isNotEmpty ? sortedNames.first.key : '';
    final allNames = nameCounts.keys.toSet();

    final dates = files
        .map((f) => f.dcmDate)
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort();

    String? matchedId;
    String? matchedName;
    double confidence = 0.0;
    bool isConfirmed = false;
    bool autoLinked = false;

    final linkedApexoId = dicomPatientId.isEmpty ? null : links[dicomPatientId];
    if (linkedApexoId != null && linkedApexoId.isNotEmpty) {
      final snap = patientSnapshots.firstWhere((p) => p.id == linkedApexoId,
          orElse: () => const _PatientSnapshot('', ''));
      if (snap.id == linkedApexoId) {
        matchedId = snap.id;
        matchedName = snap.title;
        confidence = 1.0;
        isConfirmed = true;
        autoLinked = true;
      }
    }

    if (matchedId == null && dicomPatientName.isNotEmpty) {
      // Check pending manual matches as a hint (not an approved link).
      final pendingId = pendingMatches[storeKey];
      if (pendingId != null && pendingId.isNotEmpty) {
        final snap = patientSnapshots.firstWhere((p) => p.id == pendingId,
            orElse: () => const _PatientSnapshot('', ''));
        if (snap.id == pendingId) {
          matchedId = snap.id;
          matchedName = snap.title;
          confidence = 1.0;
          isConfirmed = true;
        }
        // If the Apexo patient was deleted, silently ignore the hint.
      }
    }

    if (matchedId == null && dicomPatientName.isNotEmpty) {
      // A previously rejected suggestion stays rejected: leave the match empty
      // so the dentist picks manually.
      if (!unmatchedIds.contains(storeKey)) {
        String? bestId;
        String? bestName;
        double bestNameScore = 0.0;
        double bestDateScore = 0.0;
        double bestCombined = 0.0;
        for (final snap in patientSnapshots) {
          final nameScore = nameSimilarity(dicomPatientName, snap.title);
          if (nameScore <= 0.0) continue;
          final dtScore = _dateScore(dates, snap.id, appointmentDayMap);
          final combined = 0.6 * nameScore + 0.4 * dtScore;

          bool isBetter = false;
          if (nameScore > bestNameScore + 0.1) {
            // Clear winner by name — take it regardless of dates.
            isBetter = true;
          } else if (nameScore >= bestNameScore - 0.1 &&
              dtScore > bestDateScore) {
            // Names are within ±0.1 — dates break the tie.
            isBetter = true;
          } else if (combined > bestCombined) {
            // Fallback to combined score.
            isBetter = true;
          }

          if (isBetter) {
            bestNameScore = nameScore;
            bestDateScore = dtScore;
            bestCombined = combined;
            bestId = snap.id;
            bestName = snap.title;
          }
        }
        if (bestId != null && bestCombined >= _suggestionThreshold) {
          matchedId = bestId;
          matchedName = bestName;
          confidence = bestCombined;
        }
      } // end if (!unmatchedIds.contains)
    }

    pending.add(DicomPendingImport(
      dicomPatientId: dicomPatientId,
      dicomPatientName: dicomPatientName,
      dicomPatientNames: allNames,
      dates: dates,
      files: files,
      matchedPatientId: matchedId,
      matchedPatientName: matchedName,
      confidence: confidence,
      isConfirmed: isConfirmed,
      autoLinked: autoLinked,
    ));
  }

  pending.sort((a, b) => b.confidence.compareTo(a.confidence));
  return pending;
}

// --------------- Isolate entry point -------------------------

class _IsolateProgress {
  const _IsolateProgress(this.current, this.total, this.path, this.cacheHit);
  final int current;
  final int total;
  final String path;
  final bool cacheHit;
}

class _IsolateCancelSignal {
  const _IsolateCancelSignal();
}

void _isolateScan(_ScanMessage msg) async {
  try {
    await DicomToolkit.init();
  } catch (e, s) {
    logger('DicomImporter._isolateScan: DicomToolkit.init failed: $e', s, 2);
  }

  var cancelled = false;
  ReceivePort? cancelReceivePort;
  if (msg.cancelSignalPort != null) {
    cancelReceivePort = ReceivePort();
    msg.cancelSignalPort!.send(cancelReceivePort.sendPort);
    cancelReceivePort.listen((_) => cancelled = true);
  }

  final result = await _doScan(
    watchDir: msg.watchDir,
    importedKeys: msg.importedKeys,
    cacheSnapshot: msg.cacheSnapshot,
    patientSnapshots: msg.patientSnapshots,
    links: msg.links,
    pendingMatches: msg.pendingMatches,
    unmatchedIds: msg.unmatchedIds,
    appointmentDayMap: msg.appointmentDayMap,
    scanFn: DicomIO.scanDirectory,
    readFn: DicomIO.readBytes,
    parseFn: (bytes) async {
      try {
        return DicomParsedMeta.fromDicomMetadata(
            await const DicomParser().parseMetadata(bytes));
      } catch (_) {
        return null;
      }
    },
    onFileProgress: (current, total, path, cacheHit) {
      msg.resultPort.send(_IsolateProgress(current, total, path, cacheHit));
    },
    shouldCancel: () => cancelled,
  );

  // An isolate won't exit while a ReceivePort is open, so close the cancel port.
  cancelReceivePort?.close();
  msg.resultPort.send(result);
}

// --------------- DicomImporter ----------------------------------

class DicomImporter {
  DicomImporter({
    bool useIsolate = !kIsWeb,
    Future<Set<String>> Function()? allImportedKeys,
    Future<bool> Function(String)? isImported,
    Future<void> Function(String dicomPatientId, String apexoPatientId)?
        setPatient,
    Map<String, String> Function()? linkedPatients,
    Future<Map<String, String>> Function()? pendingMatches,
    Future<Set<String>> Function()? unmatchedIds,
    Map<String, Set<DateTime>> Function()? appointmentDayMap,
    Future<bool> Function(String dicomPatientId, String key)? linkFile,
    Future<List<DicomFileEntry>> Function(String)? scanDirectory,
    Future<Uint8List?> Function(String)? readBytes,
    Future<DicomParsedMeta?> Function(Uint8List)? parseMetadata,
    Future<Map<String, DicomCachedMeta>> Function()? cacheSnapshot,
    Future<void> Function(String, DicomCachedMeta)? cachePut,
    Future<void> Function(Set<String>)? cachePrune,
    Future<void> Function({required String path, required String reason})?
        logSkipped,
    Future<void> Function(String)? clearSkipped,
    List<Patient> Function()? allPatients,
    List<String> Function()? getWatchDirs,
    Future<String> Function(
            {required String rowID, required String sourcePath})?
        handleNewDcm,
    void Function(Appointment)? setAppointment,
    List<Appointment> Function(String)? appointmentsForPatient,
    Future<void> Function()? ensureAppointmentPersisted,
    Future<bool> Function(String)? removeKey,
    this.approvalOverrideForTesting,
    this.unregisterOverrideForTesting,
    this.fileExistsOverrideForTesting,
    this.scanOverrideForTesting,
    Future<void> Function(String patientId)? clearPendingMatch,
    Future<void> Function(String patientId)? clearUnmatched,
  })  : _allImportedKeys =
            allImportedKeys ?? (() => dicomLinks.allImportedKeys),
        _isImported = isImported ?? dicomLinks.isImported,
        _linkFile = linkFile ?? dicomLinks.linkFile,
        _setPatient = setPatient ?? dicomLinks.setPatient,
        _linkedPatients = linkedPatients ?? (() => dicomLinks.linkedPatients),
        _pendingMatches = pendingMatches ?? (() => dicomPendingMatches.all),
        _unmatchedIds = unmatchedIds ?? (() => dicomUnmatched.all),
        _appointmentDayMap =
            appointmentDayMap ?? (() => appointments.appointmentDaysByPatient),
        _useIsolate = useIsolate,
        _scanDirectory = scanDirectory ?? DicomIO.scanDirectory,
        _readBytes = readBytes ?? DicomIO.readBytes,
        _parseMetadata = parseMetadata ??
            ((bytes) async {
              try {
                return DicomParsedMeta.fromDicomMetadata(
                    await const DicomParser().parseMetadata(bytes));
              } catch (_) {
                return null;
              }
            }),
        _cacheSnapshot = cacheSnapshot ?? (() => dicomFileCache.snapshot),
        _cachePut = cachePut ?? dicomFileCache.put,
        _cachePrune = cachePrune ?? dicomFileCache.pruneMissing,
        _logSkipped = logSkipped ??
            (({required String path, required String reason}) =>
                dicomSkippedLog.add(path: path, reason: reason)),
        _clearSkipped = clearSkipped ?? dicomSkippedLog.clear,
        _allPatients = allPatients ?? (() => patients.present.values.toList()),
        _getWatchDirs = getWatchDirs ?? (() => globalSettings.dicomWatchDirs),
        _handleNewDcm = handleNewDcm ??
            (({required String rowID, required String sourcePath}) =>
                imgs.handleNewDcm(
                  rowID: rowID,
                  sourcePath: sourcePath,
                  targetStore: appointments,
                )),
        _setAppointment = setAppointment ?? appointments.set,
        _appointmentsForPatient = appointmentsForPatient ??
            ((id) => appointments
                .allForPatient(id)
                .where((a) => a.archived != true)
                .toList()),
        _ensureAppointmentPersisted = ensureAppointmentPersisted ??
            (() async {
              await appointments.waitUntilChangesAreProcessed();
              final remote = appointments.remote;
              if (remote == null || !remote.isOnline) return;
              await appointments.synchronize();
              if (!await appointments.inSync()) {
                throw StateError(
                    'Appointment persistence did not converge with PocketBase');
              }
            }),
        _removeKey = removeKey ?? dicomLinks.removeKey,
        _clearPendingMatch = clearPendingMatch ??
            ((patientId) => dicomPendingMatches.remove(patientId)),
        _clearUnmatched =
            clearUnmatched ?? ((patientId) => dicomUnmatched.remove(patientId));
  final Future<Set<String>> Function() _allImportedKeys;
  final Future<bool> Function(String) _isImported;
  final Future<void> Function(String dicomPatientId, String apexoPatientId)
      _setPatient;
  final Map<String, String> Function() _linkedPatients;
  final Future<Map<String, String>> Function() _pendingMatches;
  final Future<Set<String>> Function() _unmatchedIds;
  final Map<String, Set<DateTime>> Function() _appointmentDayMap;
  final Future<bool> Function(String dicomPatientId, String key) _linkFile;
  final Future<List<DicomFileEntry>> Function(String) _scanDirectory;
  final Future<Uint8List?> Function(String) _readBytes;
  final Future<DicomParsedMeta?> Function(Uint8List) _parseMetadata;
  final Future<Map<String, DicomCachedMeta>> Function() _cacheSnapshot;
  final Future<void> Function(String, DicomCachedMeta) _cachePut;
  final Future<void> Function(Set<String>) _cachePrune;
  final Future<void> Function({required String path, required String reason})
      _logSkipped;
  final Future<void> Function(String) _clearSkipped;
  final List<Patient> Function() _allPatients;
  final List<String> Function() _getWatchDirs;
  final Future<String> Function(
      {required String rowID, required String sourcePath}) _handleNewDcm;
  final void Function(Appointment) _setAppointment;
  final List<Appointment> Function(String apexoPatientId)
      _appointmentsForPatient;
  final Future<void> Function() _ensureAppointmentPersisted;
  final Future<bool> Function(String dedupKey)? _removeKey;
  final bool _useIsolate;
  @visibleForTesting
  final Future<DicomApprovalResult> Function(
          DicomPendingImport pending, String? apexoPatientId)?
      approvalOverrideForTesting;
  @visibleForTesting
  final Future<bool> Function(String filename)? unregisterOverrideForTesting;
  @visibleForTesting
  final Future<bool> Function(String filename)? fileExistsOverrideForTesting;
  @visibleForTesting
  final Future<List<DicomPendingImport>> Function()? scanOverrideForTesting;
  final Future<void> Function(String patientId) _clearPendingMatch;
  final Future<void> Function(String patientId) _clearUnmatched;

  final ObservableState<({int current, int total})> importProgress =
      ObservableState<({int current, int total})>((current: 0, total: 0));
  final ObservableState<ScanPhase> scanPhase =
      ObservableState<ScanPhase>(ScanPhase.idle);
  final ObservableState<ImportPhase> importPhase =
      ObservableState<ImportPhase>(ImportPhase.idle);
  final ObservableState<({int current, int total, String path, bool cacheHit})>
      scanFileProgress =
      ObservableState<({int current, int total, String path, bool cacheHit})>(
          (current: 0, total: 0, path: '', cacheHit: false));

  int _cancelToken = 0;
  Isolate? _runningIsolate;
  SendPort? _isolateCancelSendPort;

  void cancelScan() {
    _cancelToken++;
    log.info(
        'DicomImporter.cancelScan: cancel requested (token=$_cancelToken)');
    try {
      _isolateCancelSendPort?.send(const _IsolateCancelSignal());
    } catch (_) {}
  }

  // --------------- Scan ---------------------

  // Set when the last scan was cancelled; callers must then keep the existing
  // pending list rather than replacing it with the empty cancelled result.
  bool _lastScanCancelled = false;
  bool get lastScanWasCancelled => _lastScanCancelled;

  Future<List<DicomPendingImport>> scanAndBuildPending() async {
    final scanOverride = scanOverrideForTesting;
    if (scanOverride != null) {
      _lastScanCancelled = false;
      return scanOverride();
    }
    _lastScanCancelled = false;
    try {
      return await _scanAndBuildPending();
    } finally {
      // Reset the phase to idle even on error; a mid-scan exception would
      // otherwise pin `scanPhase` and permanently disable the "Scan now" button.
      _finishScan();
    }
  }

  Future<List<DicomPendingImport>> _scanAndBuildPending() async {
    final totalSw = Stopwatch()..start();
    final watchDirs = _getWatchDirs();
    if (watchDirs.isEmpty) return const <DicomPendingImport>[];

    final myToken = _cancelToken;
    bool isCancelled() => _cancelToken != myToken;

    log.info('DicomImporter.scan: starting scan of ${watchDirs.length} '
        'director${watchDirs.length == 1 ? 'y' : 'ies'}: '
        '${watchDirs.map((d) => '"$d"').join(", ")}');

    scanPhase(ScanPhase.snapshotting);
    final snapSw = Stopwatch()..start();
    final importedKeys = await _allImportedKeys();
    final cacheSnapshot = await _cacheSnapshot();
    final allPats = _allPatients();
    final patientSnapshots =
        allPats.map((p) => _PatientSnapshot(p.id, p.title)).toList();
    final links = _linkedPatients();
    final pendingMatches = await _pendingMatches();
    final unmatchedIds = await _unmatchedIds();
    final appointmentDayMap = _appointmentDayMap();
    snapSw.stop();
    log.info(
        'DicomImporter.scan: snapshots ready in ${snapSw.elapsedMilliseconds}ms '
        '(${importedKeys.length} imported keys, ${cacheSnapshot.length} cached entries, '
        '${patientSnapshots.length} patients, ${links.length} links)');

    if (isCancelled()) {
      _lastScanCancelled = true;
      _finishScan();
      return const <DicomPendingImport>[];
    }

    scanPhase(ScanPhase.listingDir);

    // --------------- Scan each directory, merge results ---------------------------------------
    final allResults = <_ScanResult>[];
    var grandScanDirMs = 0;
    var grandParseLoopMs = 0;
    var grandCacheHits = 0;
    var grandCacheMisses = 0;

    for (var di = 0; di < watchDirs.length; di++) {
      if (isCancelled()) {
        _lastScanCancelled = true;
        _finishScan();
        return const <DicomPendingImport>[];
      }
      final dir = watchDirs[di];
      log.info(
          'DicomImporter.scan: scanning dir ${di + 1}/${watchDirs.length}: "$dir"');
      scanPhase(ScanPhase.scanningFiles);
      final _ScanResult result;
      try {
        result = await _runScan(
          watchDir: dir,
          importedKeys: importedKeys,
          cacheSnapshot: cacheSnapshot,
          patientSnapshots: patientSnapshots,
          links: links,
          pendingMatches: pendingMatches,
          unmatchedIds: unmatchedIds,
          appointmentDayMap: appointmentDayMap,
          onFileProgress: (current, total, path, cacheHit) {
            scanFileProgress((
              current: current,
              total: total,
              path: path,
              cacheHit: cacheHit,
            ));
          },
          shouldCancel: isCancelled,
        );
      } catch (e) {
        log.info(
            'DicomImporter.scan: dir ${di + 1}/${watchDirs.length} "$dir" failed: $e');
        // Continue with remaining directories.
        continue;
      }
      allResults.add(result);
      grandScanDirMs += result.scanDirMs;
      grandParseLoopMs += result.parseLoopMs;
      grandCacheHits += result.cacheHits;
      grandCacheMisses += result.cacheMisses;
    }

    if (isCancelled()) {
      _lastScanCancelled = true;
      _killIsolate();
      _finishScan();
      return const <DicomPendingImport>[];
    }

    // Merge results from all directories.
    final allParsed = allResults.expand((r) => r.parsed).toList();
    final allNewCache = <String, DicomCachedMeta>{};
    for (final r in allResults) {
      allNewCache.addAll(r.newCacheEntries);
    }
    final allPaths = allResults.expand((r) => r.allScannedPaths).toSet();
    final allSkipped = allResults.expand((r) => r.skipped).toList();
    final allPending = allResults.expand((r) => r.pending).toList();

    log.info('DicomImporter.scan: all ${watchDirs.length} directories scanned '
        '${grandScanDirMs}ms dir listing, ${grandParseLoopMs}ms parse loop, '
        '${allPaths.length} discovered, '
        '$grandCacheHits cache hits, $grandCacheMisses misses, '
        '${allParsed.length} pending, ${allSkipped.length} skipped, '
        '${allPending.length} imports)');

    scanPhase(ScanPhase.persisting);
    final persistSw = Stopwatch()..start();
    // Persist side effects for all results.
    await _persistScanSideEffects(_ScanResult(
      parsed: allParsed,
      newCacheEntries: allNewCache,
      allScannedPaths: allPaths,
      skipped: allSkipped,
      pending: allPending,
      scanDirMs: grandScanDirMs,
      parseLoopMs: grandParseLoopMs,
      cacheHits: grandCacheHits,
      cacheMisses: grandCacheMisses,
    ));
    persistSw.stop();
    log.info(
        'DicomImporter.scan: persist side-effects in ${persistSw.elapsedMilliseconds}ms '
        '(${allNewCache.length} cache puts, ${allSkipped.length} skip logs)');

    scanPhase(ScanPhase.matching);
    final resolveSw = Stopwatch()..start();
    final pending = allPending;
    final patientMap = {for (final p in allPats) p.id: p};
    for (final pi in pending) {
      if (pi.matchedPatientId != null) {
        pi.matchedPatient = patientMap[pi.matchedPatientId];
      }
    }
    resolveSw.stop();
    totalSw.stop();
    log.info(
        'DicomImporter.scan: resolved patients in ${resolveSw.elapsedMilliseconds}ms '
        '${pending.length} pending imports. TOTAL ${totalSw.elapsedMilliseconds}ms.');

    return pending;
  }

  void _finishScan() {
    scanPhase(ScanPhase.idle);
    scanFileProgress((current: 0, total: 0, path: '', cacheHit: false));
    _killIsolate();
  }

  void _killIsolate() {
    _isolateCancelSendPort = null;
    final iso = _runningIsolate;
    _runningIsolate = null;
    if (iso != null) {
      try {
        iso.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
  }

  Future<void> _persistScanSideEffects(_ScanResult result) async {
    for (final entry in result.newCacheEntries.entries) {
      await _cachePut(entry.key, entry.value);
    }
    await _cachePrune(result.allScannedPaths);
    for (final s in result.skipped) {
      await _logSkipped(path: s.path, reason: s.reason);
    }
    for (final f in result.parsed) {
      await _clearSkipped(f.path);
    }
  }

  // --------------- Scan runner (isolate / direct) ------------------------------------------------------

  Future<_ScanResult> _runScan({
    required String watchDir,
    required Set<String> importedKeys,
    required Map<String, DicomCachedMeta> cacheSnapshot,
    required List<_PatientSnapshot> patientSnapshots,
    required Map<String, String> links,
    required Map<String, String> pendingMatches,
    required Set<String> unmatchedIds,
    required Map<String, Set<DateTime>> appointmentDayMap,
    required void Function(int current, int total, String path, bool cacheHit)
        onFileProgress,
    required bool Function() shouldCancel,
  }) async {
    if (!_useIsolate) {
      return _doScan(
        watchDir: watchDir,
        importedKeys: importedKeys,
        cacheSnapshot: cacheSnapshot,
        patientSnapshots: patientSnapshots,
        links: links,
        pendingMatches: pendingMatches,
        unmatchedIds: unmatchedIds,
        appointmentDayMap: appointmentDayMap,
        scanFn: _scanDirectory,
        readFn: _readBytes,
        parseFn: _parseMetadata,
        onFileProgress: onFileProgress,
        shouldCancel: shouldCancel,
      );
    }
    return _scanInIsolate(
      watchDir: watchDir,
      importedKeys: importedKeys,
      cacheSnapshot: cacheSnapshot,
      patientSnapshots: patientSnapshots,
      links: links,
      pendingMatches: pendingMatches,
      unmatchedIds: unmatchedIds,
      appointmentDayMap: appointmentDayMap,
      onFileProgress: onFileProgress,
    );
  }

  // Does not catch errors: the caller must call [_killIsolate] and [_finishScan]
  // when the isolate fails.
  Future<_ScanResult> _scanInIsolate({
    required String watchDir,
    required Set<String> importedKeys,
    required Map<String, DicomCachedMeta> cacheSnapshot,
    required List<_PatientSnapshot> patientSnapshots,
    required Map<String, String> links,
    required Map<String, String> pendingMatches,
    required Set<String> unmatchedIds,
    required Map<String, Set<DateTime>> appointmentDayMap,
    required void Function(int current, int total, String path, bool cacheHit)
        onFileProgress,
  }) async {
    final resultPort = ReceivePort();
    final cancelReceivePort = ReceivePort();
    late StreamSubscription<dynamic> cancelSub;
    cancelSub = cancelReceivePort.listen((msg) {
      if (msg is SendPort) {
        _isolateCancelSendPort = msg;
      }
    });

    _isolateCancelSendPort = null;
    final isolate = await Isolate.spawn(
      _isolateScan,
      _ScanMessage(
          watchDir,
          importedKeys,
          cacheSnapshot,
          patientSnapshots,
          links,
          pendingMatches,
          unmatchedIds,
          appointmentDayMap,
          resultPort.sendPort,
          cancelReceivePort.sendPort),
      onError: resultPort.sendPort,
      onExit: resultPort.sendPort,
    );
    _runningIsolate = isolate;

    final completer = Completer<_ScanResult>();
    late StreamSubscription<dynamic> sub;
    sub = resultPort.listen((msg) {
      if (msg is _IsolateProgress) {
        onFileProgress(msg.current, msg.total, msg.path, msg.cacheHit);
        return;
      }
      if (msg is _ScanResult) {
        unawaited(sub.cancel());
        unawaited(cancelSub.cancel());
        resultPort.close();
        cancelReceivePort.close();
        if (!completer.isCompleted) completer.complete(msg);
        return;
      }
      // isolate error or unexpected message
      unawaited(sub.cancel());
      unawaited(cancelSub.cancel());
      resultPort.close();
      cancelReceivePort.close();
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('DicomImporter: isolate scan failed: $msg'),
        );
      }
    });

    return completer.future;
  }

  // --------------- Approve ------------------

  Future<DicomApprovalResult> approveImport(
    DicomPendingImport pending, {
    String? apexoPatientId,
  }) async {
    final override = approvalOverrideForTesting;
    if (override != null) {
      return override(pending, apexoPatientId);
    }
    final targetId = apexoPatientId ?? pending.matchedPatient?.id;
    if (targetId == null || targetId.isEmpty) {
      throw StateError(
          'approveImport: no target patient call manualMatch first or pass '
          'apexoPatientId');
    }

    final approveSw = Stopwatch()..start();
    log.info(
        'DicomImporter.approveImport: starting for dicomPatient="${pending.dicomPatientId}" apexoPatient="$targetId" (${pending.files.length} files)');
    importPhase(ImportPhase.uploading);

    final claimedFiles = <DicomParsedFile>[];
    final failedFiles = <DicomParsedFile>[];
    final rollbackFailures = <Object>[];
    var successfulFiles = 0;

    try {
      final toProcess = <DicomParsedFile>[];
      for (final f in pending.files) {
        if (await _isImported(f.dedupKey)) {
          log.info(
              'DicomImporter.approveImport: already imported, skipping "${f.path}"');
          continue;
        }
        try {
          final claimed = await _linkFile(pending.dicomPatientId, f.dedupKey);
          if (claimed) {
            claimedFiles.add(f);
            toProcess.add(f);
          } else {
            log.info('DicomImporter.approveImport: key claimed concurrently, '
                'skipping "${f.path}"');
          }
        } catch (e, st) {
          failedFiles.add(f);
          logger(
              'DicomImporter.approveImport: markImported failed for '
              '"${_shortName(f.path)}", keeping it retryable: $e',
              st,
              2);
        }
      }

      try {
        if (pending.dicomPatientId.trim().isNotEmpty) {
          await _setPatient(pending.dicomPatientId.trim(), targetId);
          // Clean up any pending manual match — the real link replaces it.
          await _clearUnmatched(pending.dicomPatientId.trim());
        }
        await _clearPendingMatch(pending.selectionKey);
      } catch (e, st) {
        // Roll back the file markers if the patient link couldn't be persisted,
        // otherwise the next scan hides files whose patient is still unlinked.
        for (final f in toProcess) {
          try {
            await _removeKey?.call(f.dedupKey);
          } catch (rollbackError, rollbackStack) {
            rollbackFailures.add(rollbackError);
            logger(
                'DicomImporter.approveImport: rollback failed for '
                '"${_shortName(f.path)}": $rollbackError',
                rollbackStack,
                2);
          }
        }
        logger(
            'DicomImporter.approveImport: linkPatient failed for '
            '${pending.dicomPatientId} $targetId $e',
            st,
            2);
        if (rollbackFailures.isNotEmpty) {
          throw DicomApprovalRollbackException(
            cause: e,
            rollbackFailures: List.unmodifiable(rollbackFailures),
          );
        }
        rethrow;
      }

      if (toProcess.isEmpty) {
        log.info(
            'DicomImporter.approveImport: nothing to do (all ${pending.files.length} '
            'files already imported or failed) in ${approveSw.elapsedMilliseconds}ms');
        return DicomApprovalResult(
          successfulFiles: 0,
          failedFiles: List.unmodifiable(failedFiles),
          rollbackFailures: List.unmodifiable(rollbackFailures),
        );
      }

      // Group by date-only day; time components would split one study date into
      // duplicate appointments.
      final byDate = <DateTime, List<DicomParsedFile>>{};
      for (final f in toProcess) {
        final raw = f.effectiveDate;
        final day = DateTime(raw.year, raw.month, raw.day);
        byDate.putIfAbsent(day, () => []).add(f);
      }

      final total = toProcess.length;
      var done = 0;
      importProgress((current: 0, total: total));

      for (final dateEntry in byDate.entries) {
        final studyDate = dateEntry.key;
        final files = dateEntry.value;

        final existing = _appointmentsForPatient(targetId)
            .where((a) => _sameDay(a.date, studyDate))
            .toList();

        final Appointment appt;
        final bool wasCreated;
        if (existing.isNotEmpty) {
          appt = existing.first;
          wasCreated = false;
        } else {
          // The PocketBase row must exist before an online upload can target it;
          // if every upload fails it is archived below so it never lingers empty.
          appt = Appointment.fromJson({})
            ..patientID = targetId
            ..isDone = true
            ..date =
                DateTime(studyDate.year, studyDate.month, studyDate.day, 12);
          wasCreated = true;
          _setAppointment(appt);
          importPhase(ImportPhase.syncing);
          await _ensureAppointmentPersisted();
          importPhase(ImportPhase.uploading);
        }

        var groupSucceeded = 0;
        importPhase(ImportPhase.uploading);
        for (final f in files) {
          try {
            final fileSw = Stopwatch()..start();
            final dcmName =
                await _handleNewDcm(rowID: appt.id, sourcePath: f.path);
            fileSw.stop();
            log.info(
                'DicomImporter.approveImport: handleNewDcm "${_shortName(f.path)}" '
                '"$dcmName" in ${fileSw.elapsedMilliseconds}ms');
            if (dcmName.isEmpty) {
              throw StateError('handleNewDcm returned an empty filename');
            }

            appt.dcmImgs = appt.dcmImgs
                .where((x) => !DicomImporter.sameDcmUploadIdentity(x, dcmName))
                .toList();
            appt.dcmImgs.add(dcmName);
            successfulFiles++;
            groupSucceeded++;
          } catch (e, st) {
            try {
              // The registry marker is a reservation, not proof of upload success,
              // so a failed file must be unmarked to stay retryable.
              await _removeKey?.call(f.dedupKey);
            } catch (rollbackError, rollbackStack) {
              rollbackFailures.add(rollbackError);
              logger(
                  'DicomImporter.approveImport: file rollback failed for '
                  '"${_shortName(f.path)}": $rollbackError',
                  rollbackStack,
                  2);
            }
            failedFiles.add(f);
            logger(
                'DicomImporter.approveImport: failed for "${_shortName(f.path)}", '
                'unmarking and keeping it retryable: $e',
                st,
                2);
          }
          done++;
          importProgress((current: done, total: total));
        }
        if (wasCreated && groupSucceeded == 0) {
          appt.archived = true;
        }
        // Persist the final file list after processing this date group.
        _setAppointment(appt);
        importPhase(ImportPhase.syncing);
        await _ensureAppointmentPersisted();
      }

      // Progress stays at (total, total); callers reset it to (0, 0) when
      // appropriate.
      approveSw.stop();
      log.info(
          'DicomImporter.approveImport: done $done/$total files imported in '
          '${approveSw.elapsedMilliseconds}ms');
      return DicomApprovalResult(
        successfulFiles: successfulFiles,
        failedFiles: List.unmodifiable(failedFiles),
        rollbackFailures: List.unmodifiable(rollbackFailures),
      );
    } catch (e) {
      // Unexpected error reset progress so isImporting doesn't stay stuck.
      importProgress((current: 0, total: 0));
      for (final f in claimedFiles) {
        try {
          await _removeKey?.call(f.dedupKey);
        } catch (rollbackError, rollbackStack) {
          rollbackFailures.add(rollbackError);
          logger(
              'DicomImporter.approveImport: outer rollback failed for '
              '"${_shortName(f.path)}": $rollbackError',
              rollbackStack,
              2);
        }
      }
      if (rollbackFailures.isNotEmpty) {
        throw DicomApprovalRollbackException(
          cause: e,
          rollbackFailures: List.unmodifiable(rollbackFailures),
        );
      }
      rethrow;
    } finally {
      importPhase(ImportPhase.idle);
    }
  }

  @visibleForTesting
  static bool sameDcmUploadIdentity(String a, String b) =>
      dcm_helpers.sameDcmUploadIdentity(a, b);

  @visibleForTesting
  static String? dcmUploadIdentity(String filename) =>
      dcm_helpers.dcmUploadIdentity(filename);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Removes this file's dedup key from the import registry so the next scan
  /// rediscovers it.
  Future<bool> unregisterFile(String dcmFilename) async {
    final override = unregisterOverrideForTesting;
    if (override != null) return override(dcmFilename);
    try {
      final exists = fileExistsOverrideForTesting != null
          ? await fileExistsOverrideForTesting!(dcmFilename)
          : await imgs.checkIfFileExists(dcmFilename);
      if (!exists) return false;
      final file = await imgs.getOrCreateFile(dcmFilename);
      final bytes = await _readBytes(file.path);
      if (bytes == null || bytes.isEmpty) return false;
      final meta = await _parseMetadata(bytes);
      if (meta == null) return false;
      final key = meta.dedupKey;
      final removed = await _removeKey?.call(key) ?? false;
      if (removed) {
        log.info('DicomImporter.unregisterFile: "$dcmFilename" → '
            'removed dedup key "$key" from registry');
        return true;
      }
      // A marker may already be missing after a previous cleanup, which counts
      // as success, but persistence exceptions must still reach the catch.
      return !await _isImported(key);
    } catch (e, s) {
      logger('DicomImporter.unregisterFile error: $e', s, 2);
      return false;
    }
  }
}

final dicomImporter = DicomImporter();
