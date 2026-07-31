import 'dart:async';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Hive-backed set of DICOM patient IDs that the dentist explicitly
/// rejected.  Schema: key = `dicomPatientId`, value = `""` (unused).
///
/// At scan time, if a DICOM patient is in this set, fuzzy name matching is
/// skipped — the pending import surfaces with "No matching patient found"
/// instead of the old (rejected) suggestion.  Survives app restarts.
///
/// Entries are removed when the dentist manually matches the patient
/// (overriding the rejection) or approves the import.
class DicomUnmatchedStore {
  DicomUnmatchedStore._();
  static final DicomUnmatchedStore _instance = DicomUnmatchedStore._();
  static DicomUnmatchedStore get instance => _instance;

  late final Future<Box<String>> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await safeHiveInit();
    _box = Hive.openBox<String>('dicom_unmatched', path: await filesDir());
  }

  Future<Box<String>> get _openBox async {
    if (!_initialized) await init();
    return _box;
  }

  Future<void> add(String dicomPatientId) async {
    try {
      final box = await _openBox;
      await box.put(dicomPatientId, '');
    } catch (e, s) {
      logger('DicomUnmatchedStore.add error: $e', s, 2);
    }
  }

  Future<void> remove(String dicomPatientId) async {
    try {
      final box = await _openBox;
      await box.delete(dicomPatientId);
    } catch (e, s) {
      logger('DicomUnmatchedStore.remove error: $e', s, 2);
    }
  }

  /// Returns all unmatched DICOM patient IDs as a flat set.
  /// Snapshot at scan time — passed as plain data into the isolate.
  Future<Set<String>> get all async {
    final box = await _openBox;
    return box.keys.whereType<String>().toSet();
  }
}

/// Singleton instance used throughout the app.
final dicomUnmatched = DicomUnmatchedStore.instance;
