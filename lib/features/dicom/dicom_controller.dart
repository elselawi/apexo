import 'dart:async';
import 'dart:io' show Platform;

import 'package:apexo/core/observable.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_matched_store.dart';
import 'package:apexo/services/dicom/persistence/dicom_unmatched_store.dart';
import 'package:apexo/services/dicom/dicom_importer.dart';
import 'package:apexo/services/login.dart' show login, onLogoutCallbacks;
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// Controller for the DICOM Import screen.///
/// A thin reactive shell over [DicomImporter] — holds the pending-list,
/// scanning, and progress observables the screen renders from, and exposes
/// the user actions (refresh / approve / unmatch / manualMatch / unlink).
///
/// **Windows-only feature**: the route is gated on
/// `Platform.isWindows && !kIsWeb` in `lib/app/routes.dart`, so this
/// controller is only constructed there. The methods below are still safe to
/// call on other platforms (they no-op / return early when the watch dir is
/// empty), but the UI never reaches them off-Windows.
class DicomController {
  static DicomController? _registeredController;

  /// Pending imports surfaced by the last scan. Empty until [refresh] runs.
  final ObservableState<List<DicomPendingImport>> pending =
      ObservableState<List<DicomPendingImport>>(const <DicomPendingImport>[]);

  /// `true` while a scan is in flight. Drives the "Scan now" button spinner
  /// and disables it.
  final ObservableState<bool> scanning = ObservableState<bool>(false);

  /// Re-export of the importer's progress observable so the screen can
  /// render a per-file progress bar during [approve]. `(0, 0)` = idle.
  ObservableState<({int current, int total})> get importProgress =>
      _importer.importProgress;

  /// Re-export of the importer's scan phase — drives the progress overlay.
  ObservableState<ScanPhase> get scanPhase => _importer.scanPhase;

  /// Re-export of per-file scan progress (inline path).
  ObservableState<({int current, int total, String path, bool cacheHit})>
      get scanFileProgress => _importer.scanFileProgress;

  /// `true` while a scan is in flight (any phase except idle).
  bool get isScanning => _importer.scanPhase() != ScanPhase.idle;

  /// `true` while an import is in flight (`importProgress.total > 0`).
  bool get isImporting {
    final p = importProgress();
    return p.total > 0;
  }

  final DicomImporter _importer;
  final Future<List<SyncResult>> Function() _synchronizeAppointments;
  final Future<bool> Function() _appointmentsInSync;
  late final Future<Future<void> Function()> Function() _dicomActivator;
  late final void Function() _logoutCallback;
  late final void Function(String filename) _deadLetterCallback;

  /// Creates a controller backed by [importer] (defaults to the global
  /// [dicomImporter] singleton). The optional parameter exists so tests can
  /// inject a mock importer without touching the real stores.
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

    // Register the periodic-scan lifecycle with the login system.
    // The activator's first stage runs during login.activate(); the second
    // stage (returned callback) runs only when online and not in demo mode.
    _dicomActivator = () async {
      // First stage: stop any timer from a previous session (covers
      // re-login to same or different server). Hive boxes are already
      // opened in dicom_init.dart — no additional setup needed here.
      stopPeriodicScan();
      _healed = false;
      _healing = false;
      return () async {
        // Second stage (online, non-demo): start the periodic timer
        // if auto-import is enabled and watch dirs are configured.
        startPeriodicScan();
      };
    };
    login.activators['dicom'] = _dicomActivator;

    // Register a logout callback so the timer stops when the user
    // signs out — prevents cross-server contamination.
    _logoutCallback = stopPeriodicScan;
    onLogoutCallbacks.add(_logoutCallback);

    // When a DICOM file's upload permanently fails (dead-letter),
    // also clear the import registry so the file re-appears in the
    // pending list on the next directory scan.
    _deadLetterCallback = (filename) {
      unawaited(_importer.unregisterFile(filename));
    };
    Store.onFileDeadLettered.add(_deadLetterCallback);
  }

  /// Releases global lifecycle callbacks owned by this controller.
  ///
  /// The application singleton lives for the process lifetime; injected or
  /// test controllers should call this when their owner is disposed.
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

  /// Returns the set of DICOM study dates from [pi] that fall on the same
  /// calendar day as an existing appointment for [apexoPatientId].
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
    final all =
        appointments.byPatient[apexoPatientId]?["all"] ?? const <Appointment>[];
    return all
        .where((a) => a.archived != true)
        .map((a) => DateTime(a.date.year, a.date.month, a.date.day))
        .toSet();
  }

  /// Batch-approves every selected pending import that has a confirmed match.
  /// Returns the count of approved batches.
  /// Only successfully approved items are removed from pending — failed ones
  /// remain so the dentist can retry.
  /// Progress bar stays visible across all items (reset only at the end).
  Future<int> batchApprove(Set<String> dicomPatientIds) async {
    if (isImporting) return 0;

    // Count total batches upfront so we can show aggregate progress.
    final toApprove = pending()
        .where((pi) =>
            dicomPatientIds.contains(pi.dicomPatientId) &&
            pi.matchedPatient != null)
        .toList();
    if (toApprove.isEmpty) return 0;

    final batchTotal = toApprove.length;
    var batchDone = 0;
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
            'DicomController.batchApprove error for ${pi.dicomPatientId}: $e',
            s,
            2);
      }
      batchDone++;
      // Show aggregate batch progress — don't reset to (0,0) between items
      // so the bar stays visible the whole time.
      importProgress((current: batchDone, total: batchTotal));
    }

    importProgress((current: 0, total: 0));

    // Only remove items that were actually approved successfully.
    if (succeeded.isNotEmpty || partial.isNotEmpty) {
      pending(pending()
          .where((x) => !succeeded.contains(x))
          .map((x) => partial[x] ?? x)
          .toList());
    }
    return approved;
  }

  // ── Actions ──────────────────────────────────────────────────────────

  /// Scans the watch directory and rebuilds the pending list.
  ///
  /// Re-entrant-safe: skips if a scan is already in flight. Errors are
  /// logged and swallowed — the UI shows the previous pending list (or
  /// empty) rather than crashing.
  Future<void> refresh() async {
    if (scanning()) return;
    log.info('DicomController.refresh: scan requested');
    scanning(true);
    try {
      final result = await _importer.scanAndBuildPending();
      pending(result);
      if (result.isEmpty && autoImport && _periodicTimer != null) {
        // Periodic tick with nothing new — keep the log quiet.
        log.info('DicomController.refresh: scan complete → no new files');
      } else {
        log.info('DicomController.refresh: scan complete → '
            '${result.length} pending imports');
      }
      // Auto-approve linked patients — same behaviour whether triggered
      // by the periodic timer or the manual "Scan now" button.
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

  /// Starts the 90-second periodic scan timer.
  ///
  /// Guards:
  /// - No-ops if the timer is already running.
  /// - No-ops if the platform doesn't support DICOM scanning ([isSupported]).
  /// - No-ops if no watch directories are configured or auto-import is off.
  ///
  /// The first tick fires immediately so new files aren't delayed by a full
  /// interval.
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
    _tick(generation);
  }

  /// Stops the periodic scan timer and cancels any in-flight scan.
  ///
  /// Safe to call when no timer is running. Called on logout and when
  /// the activator re-runs (re-login to same or different server).
  void stopPeriodicScan() {
    ++_periodicGeneration;
    if (_periodicTimer != null) {
      _periodicTimer!.cancel();
      _periodicTimer = null;
      cancelScan();
      log.info('DicomController: periodic scan stopped');
    }
    _healed = false;
    _healing = false;
  }

  /// One tick of the periodic timer: scans for new files and auto-approves
  /// any that belong to already-linked patients.
  ///
  /// Self-stops if watch dirs become empty or auto-import is turned off
  /// mid-session (e.g., settings changed on another device and synced).
  Future<void> _tick(int generation) async {
    if (generation != _periodicGeneration) return;

    // Re-guard against config changes since the timer was started.
    if (watchDirs.isEmpty || !autoImport) {
      log.info('DicomController._tick: stopping timer '
          '(watchDirs empty=${watchDirs.isEmpty}, autoImport=$autoImport)');
      stopPeriodicScan();
      return;
    }

    // One-time cleanup: remove stale dcmImgs entries only after verifying
    // each file against PocketBase. Never infer missing files from a local
    // model mismatch or from an unavailable server.
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

    // Logout/re-login can cancel the timer while healing is awaiting I/O.
    // Never continue into a scan under the old session.
    if (generation != _periodicGeneration) return;
    await refresh();
  }

  /// One-time cleanup pass: removes `dcmImgs` entries whose files are
  /// definitively absent from PocketBase (for example, an upload failed).
  /// The server file list is checked before changing either model state or
  /// the registry. DicomLinksStore.removeKey preserves the patient link.
  Future<bool> _healStaleDcmImgs({bool Function()? shouldContinue}) async {
    bool isCurrent() => shouldContinue?.call() ?? true;
    if (!isCurrent()) return false;

    final remote = appointments.remote;
    if (remote == null || !remote.isOnline) {
      // Never infer that a file is missing while the server is unavailable.
      return false;
    }

    // Synchronize the appointment JSON first, then require convergence. A
    // synchronize call can return a sync error without throwing.
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

    // Use PocketBase's actual file field, not Appointment.imgs. DICOM files
    // are stored in the PB `imgs` field but intentionally listed separately
    // in Appointment.dcmImgs, so `appt.imgs.contains(dcm)` is normally false
    // even after a successful upload.
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
          Store.filenamesFromDeferredForRow(deferred, appt.id);
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

      // Re-read the authoritative file list immediately before mutation. A
      // concurrent import may have uploaded or referenced a candidate after
      // the initial inspection.
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
      final currentPending = Store.filenamesFromDeferredForRow(
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
        // Clear the dedup marker so a source file can be rediscovered.
        // DicomLinksStore.removeKey preserves any confirmed patient link.
        if (await _importer.unregisterFile(dcmName)) {
          unregistered.add(dcmName);
        } else {
          // Without a confirmed registry result, retain the appointment
          // reference so the one-time pass can retry safely later.
          inspectionComplete = false;
        }
      }
      if (unregistered.isNotEmpty) {
        appt.dcmImgs.removeWhere((d) => unregistered.contains(d));
        appointments.set(appt);
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
    final serverSet = serverFiles.map((name) => name.toLowerCase()).toSet();
    final pendingSet =
        pendingUploadFiles.map((name) => name.toLowerCase()).toSet();
    return appointmentDcmFiles
        .where((name) =>
            !serverSet.contains(name.toLowerCase()) &&
            !pendingSet.contains(name.toLowerCase()))
        .toList();
  }

  bool _healed = false;
  bool _healing = false;

  /// Auto-approves any [DicomPendingImport] items in the current pending
  /// list that are [DicomPendingImport.autoLinked] (i.e. the DICOM patient
  /// already has a confirmed link to an Apexo patient).
  ///
  /// Silently skips non-auto-linked items. Failed approvals are logged and
  /// the item stays in the pending list so the dentist can retry manually.
  ///
  /// Visible for testing so unit tests can verify the filtering + approval
  /// logic without going through the full scan pipeline.
  Future<void> autoApproveLinked() async {
    final current = pending();
    final autoLinked = current.where((pi) => pi.autoLinked).toList();
    if (autoLinked.isEmpty) return;

    log.info('DicomController.autoApproveLinked: auto-approving '
        '${autoLinked.length} linked patient(s)');
    final approvedItems = <DicomPendingImport>{};
    final partial = <DicomPendingImport, DicomPendingImport>{};
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
            '${pi.dicomPatientId}: $e',
            s,
            2);
      }
    }
    // Remove only complete approvals. Partial outcomes remain as a reduced
    // pending item so the failed files can be retried immediately.
    if (approvedItems.isNotEmpty || partial.isNotEmpty) {
      pending(current
          .where((x) => !approvedItems.contains(x))
          .map((x) => partial[x] ?? x)
          .toList());
    }
  }

  /// Approves a pending batch, importing its files into the matched (or
  /// [apexoPatientId]-overridden) patient's appointments. Removes the batch
  /// from [pending] on success.
  ///
  /// Re-entrant-safe: skips if an import is already in flight (the screen
  /// also disables the Approve button during import).
  Future<void> approve(DicomPendingImport p, {String? apexoPatientId}) async {
    if (isImporting) return;
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
    }
  }

  /// Clears the suggested match on [p] (the dentist disagrees with the
  /// suggestion). Sets [DicomPendingImport.matchedPatient] to null and
  /// [DicomPendingImport.confidence] to 0. Persists the rejection so the
  /// same suggestion won't appear again after restart.
  void unmatch(DicomPendingImport p) {
    p.matchedPatient = null;
    p.confidence = 0;
    p.isConfirmed = false;
    dicomPendingMatches.remove(p.dicomPatientId);
    dicomUnmatched.add(p.dicomPatientId);
    // Re-emit the list so the card rebuilds.
    pending(List.of(pending()));
  }

  /// Manually sets the matched Apexo patient for [p] (the dentist picked one
  /// from the patient picker). Marks the match as confirmed and persists it
  /// so it survives app restarts (without auto-importing).
  Future<void> manualMatch(DicomPendingImport p, String apexoPatientId) async {
    final matched = patients.get(apexoPatientId);
    if (matched == null) return;
    p.matchedPatient = matched;
    p.confidence = 1.0;
    p.isConfirmed = true;
    await dicomPendingMatches.set(p.dicomPatientId, apexoPatientId);
    await dicomUnmatched.remove(p.dicomPatientId); // override the rejection
    pending(List.of(pending()));
  }

  /// Unlinks a DICOM patient — one delete: link and all imported keys
  /// evaporate. Previously-imported files will re-surface on the next scan.
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

  /// The configured watch directories (re-rendered via `globalSettings`
  /// stream in the screen).
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
