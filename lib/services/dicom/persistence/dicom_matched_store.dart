import 'dart:async';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Hive-backed map of dentist-confirmed manual matches that haven't been
/// approved yet.  Schema: `dicomPatientId → apexoPatientId` (both strings).
///
/// Used at scan time as a hint: if a DICOM patient has a pending match AND
/// the matched Apexo patient still exists AND actual `.dcm` files are found
/// on disk, the pending import surfaces with confidence 1.0.  If the files
/// were deleted or the Apexo patient was removed, the match is silently
/// ignored (no phantom entries appear).
///
/// Entries are cleaned up when the dentist approves the import (the real
/// link in [DicomLinksStore] replaces it) or when the dentist unmatches.
class DicomPendingMatches {
  DicomPendingMatches._();
  static final DicomPendingMatches _instance = DicomPendingMatches._();
  static DicomPendingMatches get instance => _instance;

  late final Future<Box<String>> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await safeHiveInit();
    _box =
        Hive.openBox<String>('dicom_pending_matches', path: await filesDir());
  }

  Future<Box<String>> get _openBox async {
    if (!_initialized) await init();
    return _box;
  }

  /// Returns all pending matches as a map.  Snapshot at scan time.
  Future<Map<String, String>> get all async {
    final box = await _openBox;
    final result = <String, String>{};
    for (final key in box.keys) {
      final v = box.get(key as String);
      if (v != null && v.isNotEmpty) result[key] = v;
    }
    return result;
  }

  Future<void> set(String dicomPatientId, String apexoPatientId) async {
    try {
      final box = await _openBox;
      await box.put(dicomPatientId, apexoPatientId);
    } catch (e, s) {
      logger('DicomPendingMatches.set error: $e', s, 2);
    }
  }

  Future<void> remove(String dicomPatientId) async {
    try {
      final box = await _openBox;
      await box.delete(dicomPatientId);
    } catch (e, s) {
      logger('DicomPendingMatches.remove error: $e', s, 2);
    }
  }
}

/// Singleton instance used throughout the app.
final dicomPendingMatches = DicomPendingMatches.instance;
