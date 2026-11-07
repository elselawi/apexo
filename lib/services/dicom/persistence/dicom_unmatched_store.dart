import 'dart:async';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Rejected DICOM patient IDs stored as keys with an unused `''` value; a scan
/// skips fuzzy matching for them. A manual match or approve clears the entry.
class DicomUnmatchedStore {
  DicomUnmatchedStore._();
  static final DicomUnmatchedStore _instance = DicomUnmatchedStore._();
  static DicomUnmatchedStore get instance => _instance;

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
    final box = Hive.openBox<String>('dicom_unmatched', path: await filesDir());
    _box = box;
    await box;
  }

  Future<Box<String>> get _openBox async {
    await init();
    return _box!;
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

  /// Snapshot taken at scan time; the IDs cross into the isolate as plain data.
  Future<Set<String>> get all async {
    final box = await _openBox;
    return box.keys.whereType<String>().toSet();
  }
}

/// Singleton instance used throughout the app.
final dicomUnmatched = DicomUnmatchedStore.instance;
