import 'package:apexo/core/synchronization/deferred_file_keys.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_matched_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_unmatched_store.dart';
import 'package:apexo/services/dicom/dicom_helpers.dart' as dcm_helpers;
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/login.dart' show login, onLogoutCallbacks;
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// Windows-only screen controller: `routes.dart` hides the route unless
/// [isSupported].
class DicomController {
  DicomController({
    DicomImporter? importer,
    Future<List<SyncResult>> Function()? synchronizeAppointments,
    Future<bool> Function()? appointmentsInSync,
  })  : _importer = importer ?? dicomImporter,
        _synchronizeAppointments =
            synchronizeAppointments ?? appointments.synchronize,
        _appointmentsInSync = appointmentsInSync ?? appointments.inSync {
    final previous = _registeredController;
    if (previous != null && !identical(previous, this)) {
      previous.dispose();
    }
    _registeredController = this;

    // The activator's returned stage runs only when online and not in demo mode.
    _dicomActivator = () async {
      // First stage: drop any timer from a previous session (re-login, same
      // or other server).
      stopPeriodicScan();
      _healed = false;
      _healing = false;
      return () async {
        startPeriodicScan();
      };
    };
    login.activators['dicom'] = _dicomActivator;

    // Stop the timer on logout, or it keeps scanning into the next session.
    _logoutCallback = stopPeriodicScan;
    onLogoutCallbacks.add(_logoutCallback);

    // Dead-lettered uploads must be unregistered, or they never return to pending.
    _deadLetterCallback = (filename) {
      unawaited(_importer.unregisterFile(filename));
    };
    Store.onFileDeadLettered.add(_deadLetterCallback);
  }
  static DicomController? _registeredController;

  /// Pending imports surfaced by the last scan. Empty until [refresh] runs.
  final ObservableState<List<DicomPendingImport>> pending =
      ObservableState<List<DicomPendingImport>>(const <DicomPendingImport>[]);

  final ObservableState<bool> scanning = ObservableState<bool>(false);

  /// `(0, 0)` means idle.
  ObservableState<({int current, int total})> get importProgress =>
      _importer.importProgress;

  /// Re-export of the importer's scan phase — drives the progress overlay.
  ObservableState<ScanPhase> get scanPhase => _importer.scanPhase;

  /// Re-export of per-file scan progress (inline path).
  ObservableState<({int current, int total, String path, bool cacheHit})>
      get scanFileProgress => _importer.scanFileProgress;

  ObservableState<ImportPhase> get importPhase => _importer.importPhase;

  /// `true` while a scan is in flight (any phase except idle).
  bool get isScanning => _importer.scanPhase() != ScanPhase.idle;

  /// `true` while an import is in flight (`importProgress.total > 0`).
  bool get isImporting {
    final p = importProgress();
    return _approving || p.total > 0;
  }

  final DicomImporter _importer;
  final Future<List<SyncResult>> Function() _synchronizeAppointments;
  final Future<bool> Function() _appointmentsInSync;
  late final Future<Future<void> Function()> Function() _dicomActivator;
  late final void Function() _logoutCallback;
  late final void Function(String filename) _deadLetterCallback;
  bool _approving = false;

  /// Only injected/test controllers need this; [dicomCtrl] lives for the process.
  void dispose() {
    stopPeriodicScan();
    onLogoutCallbacks.remove(_logoutCallback);
    Store.onFileDeadLettered.remove(_deadLetterCallback);
    if (identical(login.activators['dicom'], _dicomActivator)) {
      login.activators.remove('dicom');
    }
    if (identical(_registeredController, this)) {
      _registeredController = null;
    }
  }

  // ── Date-matching helpers ────────────────────────────────────────────

  Set<DateTime> matchingDates(DicomPendingImport pi, String apexoPatientId) {
    final apptDays = _appointmentDaySet(apexoPatientId);
    return pi.dates
        .where((d) => apptDays.contains(DateTime(d.year, d.month, d.day)))
        .toSet();
  }

  /// Returns the set of DICOM study dates that do NOT match.
  Set<DateTime> mismatchingDates(DicomPendingImport pi, String apexoPatientId) {
    final apptDays = _appointmentDaySet(apexoPatientId);
    return pi.dates
        .where((d) => !apptDays.contains(DateTime(d.year, d.month, d.day)))
        .toSet();
  }

  Set<DateTime> _appointmentDaySet(String apexoPatientId) {
    return appointments.appointmentDaysByPatient[apexoPatientId] ??
        const <DateTime>{};
  }

  /// [selectionKeys] are [DicomPendingImport.selectionKey]s, not DICOM patient
  /// IDs: anonymous batches have a blank ID and would all be selected at once.
  Future<int> batchApprove(Set<String> selectionKeys) async {
    if (isImporting) return 0;

    final toApprove = pending()
        .where((pi) =>
            selectionKeys.contains(pi.selectionKey) &&
            pi.matchedPatient != null)
        .toList();
    if (toApprove.isEmpty) return 0;

    _approving = true;
    try {
      var approved = 0;
      final succeeded = <DicomPendingImport>{};
      final partial = <DicomPendingImport, DicomPendingImport>{};
      for (final pi in toApprove) {
        try {
          final result = await _importer.approveImport(pi);
          if (result.complete) {
            approved++;
            succeeded.add(pi);
          } else {
            partial[pi] = pi.copyWithFiles(result.failedFiles);
          }
        } catch (e, s) {
          logger(
              'DicomController.batchApprove error for ${pi.selectionKey}: $e',
              s,
              2);
        }
      }

      // Only remove items that were actually approved successfully.
      if (succeeded.isNotEmpty || partial.isNotEmpty) {
        pending(pending()
            .where((x) => !succeeded.contains(x))
            .map((x) => partial[x] ?? x)
            .toList());
      }
      return approved;
    } finally {
      // The importer reports per-file progress; overwriting it with batch
      // counts made the bar jump. Reset to idle only after all batches.
      importProgress((current: 0, total: 0));
      _approving = false;
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (scanning()) return;
    log.info('DicomController.refresh: scan requested');
    scanning(true);
    try {
      final result = await _importer.scanAndBuildPending();
      // A cancelled scan also returns an empty list; treating that as "no
      // files" would wipe the pending cards.
      if (_importer.lastScanWasCancelled) {
        log.info('DicomController.refresh: scan cancelled → keeping pending');
        return;
      } else {
        pending(result);
        if (result.isEmpty && autoImport && _periodicTimer != null) {
          // Periodic tick with nothing new — keep the log quiet.
          log.info('DicomController.refresh: scan complete → no new files');
        } else {
          log.info('DicomController.refresh: scan complete → '
              '${result.length} pending imports');
        }
      }
      await autoApproveLinked();
    } catch (e, s) {
      logger('DicomController.refresh error: $e', s, 2);
    } finally {
      scanning(false);
    }
  }

  /// Cancels any in-flight scan. Safe to call when no scan is running.
  void cancelScan() => _importer.cancelScan();

  // ── Periodic polling timer ──────────────────────────────────────────

  static const _pollInterval = Duration(seconds: 90);

  Timer? _periodicTimer;
  int _periodicGeneration = 0;

  /// Whether the periodic scan timer is currently active.
  bool get isTimerRunning => _periodicTimer != null;

  void startPeriodicScan() {
    if (_periodicTimer != null) return;
    if (!isSupported) return;
    if (watchDirs.isEmpty || !autoImport) {
      log.info('DicomController.startPeriodicScan: skipped '
          '(watchDirs empty=${watchDirs.isEmpty}, autoImport=$autoImport)');
      return;
    }
    log.info('DicomController: periodic scan started, '
        'interval=${_pollInterval.inSeconds}s');
    final generation = ++_periodicGeneration;
    _periodicTimer = Timer.periodic(_pollInterval, (_) => _tick(generation));
    // Fire the first tick immediately.
    unawaited(_tick(generation));
  }

  void stopPeriodicScan() {
    ++_periodicGeneration;
    cancelScan();
    if (_periodicTimer != null) {
      _periodicTimer!.cancel();
      _periodicTimer = null;
      log.info('DicomController: periodic scan stopped');
    }
    _healed = false;
    _healing = false;
  }

  // Synced settings can change mid-session (another device), so each tick
  // re-checks and stops itself when scanning no longer applies.
  Future<void> _tick(int generation) async {
    if (generation != _periodicGeneration) return;

    // Re-guard against config changes since the timer was started.
    if (watchDirs.isEmpty || !autoImport) {
      log.info('DicomController._tick: stopping timer '
          '(watchDirs empty=${watchDirs.isEmpty}, autoImport=$autoImport)');
      stopPeriodicScan();
      return;
    }

    // Never infer a missing file from local state or an offline server: only
    // the PocketBase file list is authoritative, and this pass runs once.
    if (!_healed && !_healing) {
      _healing = true;
      try {
        if (await _healStaleDcmImgs(
          shouldContinue: () => generation == _periodicGeneration,
        )) {
          _healed = true;
        }
      } finally {
        _healing = false;
      }
    }

    // Logout can bump the generation while healing awaits I/O; never scan
    // under the old session.
    if (generation != _periodicGeneration) return;
    await refresh();
  }

  Future<bool> _healStaleDcmImgs({bool Function()? shouldContinue}) async {
    bool isCurrent() => shouldContinue?.call() ?? true;
    if (!isCurrent()) return false;

    final remote = appointments.remote;
    if (remote == null || !remote.isOnline) {
      // Never infer that a file is missing while the server is unavailable.
      return false;
    }

    // Synchronize first, then require convergence: a sync can fail without
    // throwing.
    try {
      await _synchronizeAppointments();
      if (!isCurrent() || !await _appointmentsInSync()) return false;
    } catch (_) {
      // Offline or sync error — the server state is unknown.
      return false;
    }

    final deferred = await appointments.local?.getDeferred() ?? {};
    final toFix = <String, List<String>>{}; // apptId → stale names
    var inspectionComplete = true;

    // DICOM files go to PocketBase's `imgs` field but are listed separately in
    // `dcmImgs`, so `appt.imgs.contains(dcm)` is false even after upload.
    for (final appt in appointments.docs.values) {
      if (!isCurrent()) return false;
      if (appt.dcmImgs.isEmpty) continue;

      final List<String> serverNames;
      try {
        serverNames = await remote.getFileNames(appt.id);
      } catch (e, s) {
        // A failed row lookup is not evidence of a missing file.
        logger(
            'DicomController._healStaleDcmImgs: could not inspect '
            'appointment ${appt.id}: $e',
            s,
            1);
        inspectionComplete = false;
        continue;
      }
      final pendingUploadFilenames =
          filenamesFromDeferredForRow(deferred, appt.id);
      final stale = staleDcmFileNames(
        appointmentDcmFiles: appt.dcmImgs,
        serverFiles: serverNames,
        pendingUploadFiles: pendingUploadFilenames,
      );
      if (stale.isNotEmpty) {
        toFix[appt.id] = stale;
      }
    }
    if (!isCurrent() || toFix.isEmpty) return inspectionComplete;

    log.info('DicomController._healStaleDcmImgs: cleaning '
        '${toFix.length} appointment(s) with '
        '${toFix.values.fold<int>(0, (s, l) => s + l.length)} stale '
        'dcmImgs entries');

    var changed = false;
    for (final entry in toFix.entries) {
      if (!isCurrent()) return false;
      final appt = appointments.docs[entry.key];
      if (appt == null) {
        inspectionComplete = false;
        continue;
      }

      // Re-read just before mutating: a concurrent import may have uploaded a
      // candidate since the first inspection.
      final List<String> currentServerNames;
      try {
        currentServerNames = await remote.getFileNames(appt.id);
      } catch (e, s) {
        logger(
            'DicomController._healStaleDcmImgs: could not re-inspect '
            'appointment ${appt.id}: $e',
            s,
            1);
        inspectionComplete = false;
        continue;
      }
      if (!isCurrent()) return false;
      final currentDeferred = await appointments.local?.getDeferred() ?? {};
      final currentPending = filenamesFromDeferredForRow(
        currentDeferred,
        appt.id,
      );
      final stillStale = staleDcmFileNames(
        appointmentDcmFiles: appt.dcmImgs,
        serverFiles: currentServerNames,
        pendingUploadFiles: currentPending,
      ).toSet();
      final unregistered = <String>{};
      for (final dcmName in entry.value) {
        if (!isCurrent()) return false;
        if (!stillStale.contains(dcmName)) continue;
        // Clearing the dedup key lets the source file be rediscovered;
        // DicomLinksStore.removeKey keeps the patient link.
        if (await _importer.unregisterFile(dcmName)) {
          unregistered.add(dcmName);
        } else {
          // Unconfirmed unregister: keep the reference so a later pass retries.
          inspectionComplete = false;
        }
      }
      if (unregistered.isNotEmpty) {
        appointmentCommand(
            appt.id,
            (draft) =>
                draft.dcmImgs.removeWhere((d) => unregistered.contains(d)));
        changed = true;
      }
    }
    if (!changed) return inspectionComplete && isCurrent();
    await appointments.waitUntilChangesAreProcessed();
    await _synchronizeAppointments();
    return inspectionComplete && isCurrent() && await _appointmentsInSync();
  }

  @visibleForTesting
  Future<bool> debugHealStaleDcmImgs({bool Function()? shouldContinue}) =>
      _healStaleDcmImgs(shouldContinue: shouldContinue);

  @visibleForTesting
  Future<void> debugTick(int generation) => _tick(generation);

  @visibleForTesting
  int get debugPeriodicGeneration => _periodicGeneration;

  @visibleForTesting
  bool get debugHealed => _healed;

  @visibleForTesting
  bool get debugHealing => _healing;

  @visibleForTesting
  static List<String> staleDcmFileNames({
    required List<String> appointmentDcmFiles,
    required List<String> serverFiles,
    required Set<String> pendingUploadFiles,
  }) {
    // PocketBase appends a collision suffix (`x.dcm` -> `x_ab12cd.dcm`) and
    // `dcmImgs` may hold either the name or its `.dcm.png` preview, so compare
    // logical identities, not raw strings, or present files look stale.
    String identityOf(String name) =>
        dcm_helpers.dcmUploadIdentity(name) ?? name.toLowerCase();

    final serverIdentities = serverFiles.map(identityOf).toSet();
    final pendingIdentities = pendingUploadFiles.map(identityOf).toSet();
    return appointmentDcmFiles.where((name) {
      final id = identityOf(name);
      return !serverIdentities.contains(id) && !pendingIdentities.contains(id);
    }).toList();
  }

  bool _healed = false;
  bool _healing = false;

  Future<void> autoApproveLinked() async {
    // Never overlap a manual approve: both mutate appointments and share the
    // progress observable. The next tick retries.
    if (isImporting) return;

    final current = pending();
    final autoLinked = current.where((pi) => pi.autoLinked).toList();
    if (autoLinked.isEmpty) return;

    log.info('DicomController.autoApproveLinked: auto-approving '
        '${autoLinked.length} linked patient(s)');
    final approvedItems = <DicomPendingImport>{};
    final partial = <DicomPendingImport, DicomPendingImport>{};
    _approving = true;
    try {
      for (final pi in autoLinked) {
        try {
          final result = await _importer.approveImport(pi);
          if (result.complete) {
            approvedItems.add(pi);
          } else {
            partial[pi] = pi.copyWithFiles(result.failedFiles);
          }
        } catch (e, s) {
          logger(
              'DicomController.autoApproveLinked: failed for '
              '${pi.selectionKey}: $e',
              s,
              2);
        }
      }
      if (approvedItems.isNotEmpty || partial.isNotEmpty) {
        pending(current
            .where((x) => !approvedItems.contains(x))
            .map((x) => partial[x] ?? x)
            .toList());
      }
    } finally {
      // The importer leaves progress at (total, total) for batch callers;
      // without this reset `isImporting` stays true forever.
      importProgress((current: 0, total: 0));
      _approving = false;
    }
  }

  Future<void> approve(DicomPendingImport p, {String? apexoPatientId}) async {
    if (isImporting) return;
    _approving = true;
    try {
      final result = await _importer.approveImport(
        p,
        apexoPatientId: apexoPatientId,
      );
      if (result.complete) {
        // Remove the approved batch from the pending list.
        pending(pending().where((x) => !identical(x, p)).toList());
      } else {
        pending(pending()
            .map((x) =>
                identical(x, p) ? p.copyWithFiles(result.failedFiles) : x)
            .toList());
      }
    } catch (e, s) {
      logger('DicomController.approve error: $e', s, 2);
    } finally {
      importProgress((current: 0, total: 0));
      _approving = false;
    }
  }

  /// Persisted so the scanner won't re-suggest a rejected match.
  void unmatch(DicomPendingImport p) {
    p.matchedPatient = null;
    p.confidence = 0;
    p.isConfirmed = false;
    // Key by the stable batch identity — anonymous batches have a blank DICOM
    // patient ID and would otherwise all share (and clobber) one entry.
    unawaited(dicomPendingMatches.remove(p.selectionKey));
    unawaited(dicomUnmatched.add(p.selectionKey));
    // Re-emit the list so the card rebuilds.
    pending(List.of(pending()));
  }

  /// Persists the confirmed match; importing still requires [approve].
  Future<void> manualMatch(DicomPendingImport p, String apexoPatientId) async {
    final matched = patients.get(apexoPatientId);
    if (matched == null) return;
    p.matchedPatient = matched;
    p.confidence = 1.0;
    p.isConfirmed = true;
    await dicomPendingMatches.set(p.selectionKey, apexoPatientId);
    await dicomUnmatched.remove(p.selectionKey); // override the rejection
    pending(List.of(pending()));
  }

  /// Unlinking makes the previously-imported files re-surface on the next scan.
  Future<void> unlinkPatient(String dicomPatientId) async {
    // One delete — link and all imported keys evaporate.
    await dicomLinks.unlink(dicomPatientId);

    // Remove the unlinked patient from the pending list immediately.
    pending(
        pending().where((x) => x.dicomPatientId != dicomPatientId).toList());

    // Rescan to re-surface the unlinked files.
    await refresh();
  }

  // ── Convenience getters for the screen ───────────────────────────────

  String get watchDir => globalSettings.dicomWatchDir;

  /// Parsed list of watch directories.
  List<String> get watchDirs => globalSettings.dicomWatchDirs;

  /// Whether auto-import is enabled.
  bool get autoImport => globalSettings.dicomAutoImport;

  /// The current DICOM→Apexo link map, for the "Linked Patients" section.
  Map<String, String> get linkedPatients => dicomLinks.linkedPatients;

  /// `true` when this controller is usable on the current platform.
  static bool get isSupported => !kIsWeb && Platform.isWindows;
}

/// Singleton controller used by the DICOM Import screen and periodic scan.
final dicomCtrl = DicomController();
