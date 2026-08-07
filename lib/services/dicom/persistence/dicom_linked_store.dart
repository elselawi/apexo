import 'dart:async';
import 'dart:convert';

import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:hive_flutter/adapters.dart';

/// Computes a stable deduplication key from the four UID/instance fields.
///
/// **Primary**: `sopInstanceUid` (tag 0008,0018) — globally unique per DICOM
/// instance. **Fallback** (if SOP UID is empty/missing): composite of
/// `studyInstanceUid + seriesInstanceUid + instanceNumber`.
String dedupKeyFromValues({
  required String sopInstanceUid,
  required String studyInstanceUid,
  required String seriesInstanceUid,
  required String instanceNumber,
}) {
  final sop = sopInstanceUid.trim();
  if (sop.isNotEmpty) return 'sop:$sop';
  final study = studyInstanceUid.trim();
  final series = seriesInstanceUid.trim();
  final instance = instanceNumber.trim();
  return 'composite:$study|$series|$instance';
}

/// Computes a stable deduplication key for a parsed DICOM file.
String dedupKey(final DicomMetadata m) => dedupKeyFromValues(
      sopInstanceUid: m.sopInstanceUid,
      studyInstanceUid: m.studyInstanceUid,
      seriesInstanceUid: m.seriesInstanceUid,
      instanceNumber: m.instanceNumber,
    );

// ── Link entry JSON model ──────────────────────────────────────────────

class _LinkEntry {
  String? patient;
  List<String> keys;
  _LinkEntry({this.patient, List<String>? keys}) : keys = keys ?? [];
  factory _LinkEntry.fromJson(String json) {
    try {
      final map = jsonDecode(json);
      return _LinkEntry(
        patient: map['p'] as String?,
        keys: List<String>.from(map['k'] ?? []),
      );
    } catch (_) {
      return _LinkEntry();
    }
  }
  String toJson() => jsonEncode({'p': patient, 'k': keys});
}

/// Single source of truth for DICOM patient links and imported-file dedup.
///
/// One Hive box (`dicom_links`). Each entry maps a DICOM patient ID to:
/// ```json
/// {"p": "apexo-patient-uuid", "k": ["sop:...", "sop:..."]}
/// ```
///
/// - `p` is `null` until the dentist links the DICOM patient to an Apexo
///   patient (approve or manual-match).
/// - `k` is the list of imported dedup keys for that patient.
class DicomLinksStore {
  final String _boxName;
  final String? _storagePath;
  @visibleForTesting
  bool debugFailInitialization = false;

  DicomLinksStore._({
    String boxName = 'dicom_links',
    String? storagePath,
  })  : _boxName = boxName,
        _storagePath = storagePath;

  static final DicomLinksStore _instance = DicomLinksStore._();
  static DicomLinksStore get instance => _instance;

  @visibleForTesting
  static DicomLinksStore createForTesting({
    required String boxName,
    required String storagePath,
  }) =>
      DicomLinksStore._(boxName: boxName, storagePath: storagePath);

  @visibleForTesting
  Future<void>? get debugInitialization => _initialization;

  Future<Box<String>>? _box;
  Future<void>? _initialization;
  Future<void> _mutationTail = Future<void>.value();
  final Map<String, _LinkEntry> _cache = {};
  Set<String> _allKeysCache = const {};
  final ObservableState<int> _version = ObservableState<int>(0);
  ObservableState<int> get version => _version;

  Future<void> init() {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _initialize();
    _initialization = initialization;
    initialization.catchError((_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
        _box = null;
      }
    });
    return initialization;
  }

  Future<void> _initialize() async {
    if (debugFailInitialization) {
      debugFailInitialization = false;
      throw StateError('test initialization failure');
    }
    if (_storagePath == null) {
      await safeHiveInit();
    }
    _box = Hive.openBox<String>(
      _boxName,
      path: _storagePath ?? await filesDir(),
    );
    await _rebuildCache();
  }

  Future<Box<String>> get _openBox async {
    await init();
    return _box!;
  }

  Future<void> _rebuildCache() async {
    final box = await _box!;
    _cache.clear();
    final keys = <String>{};
    for (final key in box.keys) {
      final raw = box.get(key as String);
      if (raw == null || raw.isEmpty) continue;
      final entry = _LinkEntry.fromJson(raw);
      _cache[key] = entry;
      keys.addAll(entry.keys);
    }
    _allKeysCache = keys;
  }

  void _bump() => _version(_version() + 1);

  Future<T> _serializeMutation<T>(Future<T> Function() action) {
    final result = _mutationTail.then((_) => action());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<Set<String>> get allImportedKeys async {
    await init();
    await _mutationTail;
    return Set<String>.from(_allKeysCache);
  }

  Future<bool> isImported(String key) async {
    await init();
    await _mutationTail;
    return _allKeysCache.contains(key);
  }

  Future<bool> linkFile(String dicomPatientId, String key) {
    return _serializeMutation(() async {
      try {
        if (_allKeysCache.contains(key)) return false;
        final box = await _openBox;
        final current = _cache[dicomPatientId];
        final next = _LinkEntry(
          patient: current?.patient,
          keys: [...?current?.keys, key],
        );
        // Persist first. Only update the process cache after Hive confirms the
        // write, otherwise a storage error can permanently hide the file from
        // the next scan until the application restarts.
        await box.put(dicomPatientId, next.toJson());
        _cache[dicomPatientId] = next;
        _allKeysCache.add(key);
        _bump();
        return true;
      } catch (e, s) {
        logger('DicomLinksStore.linkFile error: $e', s, 2);
        rethrow;
      }
    });
  }

  Future<void> setPatient(String dicomPatientId, String apexoPatientId) {
    return _serializeMutation(() async {
      try {
        final box = await _openBox;
        final current = _cache[dicomPatientId];
        final next = _LinkEntry(
          patient: apexoPatientId,
          keys: [...?current?.keys],
        );
        await box.put(dicomPatientId, next.toJson());
        _cache[dicomPatientId] = next;
        _bump();
      } catch (e, s) {
        logger('DicomLinksStore.setPatient error: $e', s, 2);
        rethrow;
      }
    });
  }

  Future<void> unlink(String dicomPatientId) {
    return _serializeMutation(() async {
      try {
        final box = await _openBox;
        final entry = _cache[dicomPatientId];
        await box.delete(dicomPatientId);
        // Update the cache only after the persistent delete succeeds.
        _cache.remove(dicomPatientId);
        if (entry != null) {
          _allKeysCache.removeAll(entry.keys);
        }
        _bump();
        log.info(
            'DicomLinksStore.unlink: cleared ${entry?.keys.length ?? 0} keys '
            'for dicomPatient="$dicomPatientId"');
      } catch (e, s) {
        logger('DicomLinksStore.unlink error: $e', s, 2);
        rethrow;
      }
    });
  }

  /// Whether an entry without imported-file markers can be discarded.
  ///
  /// A confirmed DICOM-to-Apexo patient mapping must survive independently
  /// so that a failed file can be rediscovered without requiring rematching.
  static bool canDeleteEmptyEntry({
    required String? patientId,
    required List<String> keys,
  }) =>
      keys.isEmpty && (patientId == null || patientId.isEmpty);

  /// Removes a single dedup key from whichever patient entry owns it.
  ///
  /// Used when a DICOM file's upload permanently failed — clearing the
  /// imported-file marker lets the source file be re-discovered on the next
  /// directory scan.
  ///
  /// A DICOM patient link is independent from its imported-file markers.
  /// In particular, removing the final marker must not discard [patient]:
  /// doing so changes a recoverable failed upload into an unlinked patient
  /// that must be manually matched again.
  Future<bool> removeKey(String dedupKey) {
    return _serializeMutation(() async {
      try {
        final box = await _openBox; // ensures Hive is open + cache is populated
        if (!_allKeysCache.contains(dedupKey)) return false;
        for (final entry in _cache.entries) {
          if (!entry.value.keys.contains(dedupKey)) continue;

          final nextKeys = entry.value.keys
              .where((key) => key != dedupKey)
              .toList(growable: true);
          final deleteEntry = canDeleteEmptyEntry(
            patientId: entry.value.patient,
            keys: nextKeys,
          );
          if (deleteEntry) {
            await box.delete(entry.key);
          } else {
            final next = _LinkEntry(
              patient: entry.value.patient,
              keys: nextKeys,
            );
            await box.put(entry.key, next.toJson());
          }

          // Update both caches only after the Hive operation succeeds.
          _allKeysCache.remove(dedupKey);
          if (deleteEntry) {
            _cache.remove(entry.key);
          } else {
            _cache[entry.key] = _LinkEntry(
              patient: entry.value.patient,
              keys: nextKeys,
            );
          }
          _bump();
          log.info('DicomLinksStore.removeKey: removed "$dedupKey" '
              'from dicomPatient="${entry.key}"');
          return true;
        }
        // Shouldn't happen if _allKeysCache is consistent, but be defensive.
        _allKeysCache.remove(dedupKey);
        return false;
      } catch (e, s) {
        logger('DicomLinksStore.removeKey error: $e', s, 2);
        rethrow;
      }
    });
  }

  Map<String, String> get linkedPatients {
    final result = <String, String>{};
    for (final entry in _cache.entries) {
      final p = entry.value.patient;
      if (p != null && p.isNotEmpty) {
        result[entry.key] = p;
      }
    }
    return result;
  }

  /// Number of unique imported DICOM files claimed by a DICOM patient.
  int importedFileCountFor(String dicomPatientId) =>
      _cache[dicomPatientId]?.keys.toSet().length ?? 0;

  int get linkedCount {
    var count = 0;
    for (final entry in _cache.values) {
      if (entry.patient != null && entry.patient!.isNotEmpty) count++;
    }
    return count;
  }

  int get importedCount => _allKeysCache.length;

  @visibleForTesting
  Future<void> debugCloseBoxWithoutReset() async {
    final box = await _box;
    if (box != null && box.isOpen) {
      await box.close();
    }
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _mutationTail;
    final boxFuture = _box;
    _box = null;
    _initialization = null;
    _cache.clear();
    _allKeysCache = const {};
    if (boxFuture != null) {
      try {
        final box = await boxFuture;
        if (box.isOpen) await box.close();
      } catch (_) {
        // Initialization failures have no open box to close.
      }
    }
  }
}

/// Singleton instance used throughout the app.
final dicomLinks = DicomLinksStore.instance;
