import 'dart:async';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Unapproved manual matches: `dicomPatientId → apexoPatientId`. A scan uses one
/// only when the Apexo patient and its `.dcm` files still exist; else ignored.
class DicomPendingMatches {
  DicomPendingMatches._();
  static final DicomPendingMatches _instance = DicomPendingMatches._();
  static DicomPendingMatches get instance => _instance;

  Future<Box<String>>? _box;
  Future<void>? _initialization;

  Future<void> init() {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _initialize();
    _initialization = initialization;
    // Clear the memoized future on failure so a later call retries instead of
    // reusing a half-open box.
    unawaited(initialization.catchError((_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
        _box = null;
      }
    }));
    return initialization;
  }

  Future<void> _initialize() async {
    await safeHiveInit();
    final box =
        Hive.openBox<String>('dicom_pending_matches', path: await filesDir());
    _box = box;
    await box;
  }

  Future<Box<String>> get _openBox async {
    await init();
    return _box!;
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
