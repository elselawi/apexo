import 'dart:async';
import 'dart:convert';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// A logged "skipped file" entry. Surfaced in the DICOM screen
/// as an expandable "Skipped files" section so the dentist can see why a
/// file wasn't imported.
class DicomSkippedEntry {
  /// Absolute path to the `.dcm` file.
  final String path;

  /// Why the file was skipped (parse failure, corrupted, etc.).
  final String reason;

  /// When the skip was logged (ISO 8601).
  final String timestamp;

  const DicomSkippedEntry({
    required this.path,
    required this.reason,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'reason': reason,
        'timestamp': timestamp,
      };

  factory DicomSkippedEntry.fromJson(Map<String, dynamic> json) =>
      DicomSkippedEntry(
        path: json['path'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        timestamp: json['timestamp'] as String? ?? '',
      );
}

/// Hive-backed log of DICOM files that were skipped during a scan.
///
/// Box name: `dicom_skipped`. Keyed by path + timestamp (to allow the same
/// path to appear multiple times across scans if it keeps failing). Values
/// are JSON-encoded [DicomSkippedEntry].
///
/// Surfaced in the DICOM screen as an expandable "Skipped files"
/// section so the dentist can investigate why a file wasn't imported.
class DicomSkippedLog {
  DicomSkippedLog._();

  static final DicomSkippedLog _instance = DicomSkippedLog._();
  static DicomSkippedLog get instance => _instance;

  late final Future<Box<String>> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await safeHiveInit();
    _box = Hive.openBox<String>('dicom_skipped', path: await filesDir());
  }

  Future<Box<String>> get _openBox async {
    if (!_initialized) await init();
    return _box;
  }

  /// Logs a skipped file. Idempotent per (path, reason) within the same
  /// scan — avoids flooding the log with the same entry on every resync.
  Future<void> add({required String path, required String reason}) async {
    try {
      final box = await _openBox;
      final entry = DicomSkippedEntry(
        path: path,
        reason: reason,
        timestamp: DateTime.now().toIso8601String(),
      );
      // Keyed by path so repeated skips of the same file update the entry
      // rather than accumulating duplicates across scans.
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
              return DicomSkippedEntry.fromJson(jsonDecode(raw));
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
