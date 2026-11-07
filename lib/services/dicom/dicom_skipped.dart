import 'dart:async';
import 'dart:convert';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// A skipped file shown in the DICOM screen's "Skipped files" section.
class DicomSkippedEntry {
  const DicomSkippedEntry({
    required this.path,
    required this.reason,
    required this.timestamp,
  });

  factory DicomSkippedEntry.fromJson(Map<String, dynamic> json) =>
      DicomSkippedEntry(
        path: json['path'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        timestamp: json['timestamp'] as String? ?? '',
      );

  /// Absolute path to the `.dcm` file.
  final String path;

  /// Why the file was skipped (parse failure, corrupted, etc.).
  final String reason;

  /// When the skip was logged (ISO 8601).
  final String timestamp;

  Map<String, dynamic> toJson() => {
        'path': path,
        'reason': reason,
        'timestamp': timestamp,
      };
}

/// Hive log of skipped files, keyed by path + timestamp (the same file may fail
/// again) and shown in the DICOM screen so the dentist can investigate.
class DicomSkippedLog {
  DicomSkippedLog._();

  static final DicomSkippedLog _instance = DicomSkippedLog._();
  static DicomSkippedLog get instance => _instance;

  Future<Box<String>>? _box;
  Future<void>? _initialization;

  Future<void> init() {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _initialize();
    _initialization = initialization;
    // Clear the memoized future on failure so a later call retries instead of
    // reusing a half-open box (LateInitializationError on every access).
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
    final box = Hive.openBox<String>('dicom_skipped', path: await filesDir());
    _box = box;
    await box;
  }

  Future<Box<String>> get _openBox async {
    await init();
    return _box!;
  }

  /// Idempotent per (path, reason) within a scan, so a resync does not flood it.
  Future<void> add({required String path, required String reason}) async {
    try {
      final box = await _openBox;
      final entry = DicomSkippedEntry(
        path: path,
        reason: reason,
        timestamp: DateTime.now().toIso8601String(),
      );
      // Repeated skips update the entry rather than accumulating duplicates.
      await box.put(path, jsonEncode(entry.toJson()));
    } catch (e, s) {
      // best-effort logging — never crash on the logging path
      logger('DicomSkippedLog.add error: $e', s, 2);
    }
  }

  /// Returns all skipped-file entries (for display in the DICOM screen).
  Future<List<DicomSkippedEntry>> get all async {
    try {
      final box = await _openBox;
      return box.values
          .map((raw) {
            try {
              return DicomSkippedEntry.fromJson(
                  jsonDecode(raw) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<DicomSkippedEntry>()
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e, s) {
      logger('DicomSkippedLog.all error: $e', s, 2);
      return [];
    }
  }

  /// Clears a skipped-file entry once the file is successfully imported.
  Future<void> clear(String path) async {
    try {
      final box = await _openBox;
      await box.delete(path);
    } catch (e, s) {
      logger('DicomSkippedLog.clear error: $e', s, 2);
    }
  }

  /// Clears all skipped-file entries.
  Future<void> clearAll() async {
    try {
      final box = await _openBox;
      await box.clear();
    } catch (e, s) {
      logger('DicomSkippedLog.clearAll error: $e', s, 2);
    }
  }
}

/// Singleton instance used throughout the app.
final dicomSkippedLog = DicomSkippedLog.instance;
