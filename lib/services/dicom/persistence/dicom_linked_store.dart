import 'dart:async';
import 'dart:convert';

import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/logger.dart';
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
  DicomLinksStore._();
  static final DicomLinksStore _instance = DicomLinksStore._();
  static DicomLinksStore get instance => _instance;

  late final Future<Box<String>> _box;
  bool _initialized = false;
  final Map<String, _LinkEntry> _cache = {};
  Set<String> _allKeysCache = const {};
  final ObservableState<int> _version = ObservableState<int>(0);
  ObservableState<int> get version => _version;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await safeHiveInit();
    _box = Hive.openBox<String>('dicom_links', path: await filesDir());
    await _rebuildCache();
  }

  Future<Box<String>> get _openBox async {
    if (!_initialized) await init();
    return _box;
  }

  Future<void> _rebuildCache() async {
    final box = await _openBox;
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

  Future<Set<String>> get allImportedKeys async {
    if (!_initialized) await init();
    return Set<String>.from(_allKeysCache);
  }

  Future<bool> isImported(String key) async {
    if (!_initialized) await init();
    return _allKeysCache.contains(key);
  }

  Future<void> linkFile(String dicomPatientId, String key) async {
    try {
      if (_allKeysCache.contains(key)) return;
      final box = await _openBox;
      final entry = _cache[dicomPatientId] ?? _LinkEntry();
      entry.keys.add(key);
      _cache[dicomPatientId] = entry;
      _allKeysCache.add(key);
      await box.put(dicomPatientId, entry.toJson());
      _bump();
    } catch (e, s) {
      logger('DicomLinksStore.linkFile error: $e', s, 2);
    }
  }

  Future<void> setPatient(String dicomPatientId, String apexoPatientId) async {
    try {
      final box = await _openBox;
      final entry = _cache[dicomPatientId] ?? _LinkEntry();
      entry.patient = apexoPatientId;
      _cache[dicomPatientId] = entry;
      await box.put(dicomPatientId, entry.toJson());
      _bump();
    } catch (e, s) {
      logger('DicomLinksStore.setPatient error: $e', s, 2);
    }
  }

  Future<void> unlink(String dicomPatientId) async {
    try {
      final box = await _openBox;
      final entry = _cache.remove(dicomPatientId);
      if (entry != null) {
        _allKeysCache.removeAll(entry.keys);
      }
      await box.delete(dicomPatientId);
      _bump();
      log.info(
          'DicomLinksStore.unlink: cleared ${entry?.keys.length ?? 0} keys '
          'for dicomPatient="$dicomPatientId"');
    } catch (e, s) {
      logger('DicomLinksStore.unlink error: $e', s, 2);
    }
  }

  /// Removes a single dedup key from whichever patient entry owns it.
  ///
  /// Used when a DICOM file's upload permanently failed — clearing the
  /// registry entry lets the file be re-discovered on the next directory
  /// scan so the dentist can re-approve it.
  Future<bool> removeKey(String dedupKey) async {
    try {
      final box = await _openBox; // ensures Hive is open + cache is populated
      if (!_allKeysCache.contains(dedupKey)) return false;
      for (final entry in _cache.entries) {
        if (entry.value.keys.remove(dedupKey)) {
          _allKeysCache.remove(dedupKey);
          if (entry.value.keys.isEmpty) {
            _cache.remove(entry.key);
            await box.delete(entry.key);
          } else {
            await box.put(entry.key, entry.value.toJson());
          }
          _bump();
          log.info('DicomLinksStore.removeKey: removed "$dedupKey" '
              'from dicomPatient="${entry.key}"');
          return true;
        }
      }
      // Shouldn't happen if _allKeysCache is consistent, but be defensive.
      _allKeysCache.remove(dedupKey);
      return false;
    } catch (e, s) {
      logger('DicomLinksStore.removeKey error: $e', s, 2);
      return false;
    }
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

  int get linkedCount {
    var count = 0;
    for (final entry in _cache.values) {
      if (entry.patient != null && entry.patient!.isNotEmpty) count++;
    }
    return count;
  }

  int get importedCount => _allKeysCache.length;
}

/// Singleton instance used throughout the app.
final dicomLinks = DicomLinksStore.instance;
