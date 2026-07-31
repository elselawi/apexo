import 'dart:async';
import 'dart:convert';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Cached metadata for a `.dcm` file, keyed by absolute path.
///
/// At scale (40,000+ files), opening and parsing metadata for
/// every file on every scan is noticeable. This cache stores the parsed
/// metadata + the file's `mtime + size` so unchanged files can be skipped
/// entirely (no file open, no parse) on subsequent scans.
class DicomCachedMeta {
  /// File's last-modified timestamp at the time of parsing.
  final DateTime mtime;

  /// File size in bytes at the time of parsing.
  final int size;

  /// Dedup key (SOP Instance UID or composite fallback).
  final String dedupKey;

  /// DICOM patient name (raw, as stored in the file).
  final String patientName;

  /// DICOM patient ID (MRN).
  final String patientId;

  /// DICOM study date (YYYYMMDD string, as stored in the file).
  final DateTime? dcmDate;

  /// Whether this file is part of a volumetric scan (CBCT/CT).
  /// Cached so that cache-hit scans can skip volumetric files without
  /// re-parsing metadata.
  final bool isVolumetric;

  const DicomCachedMeta({
    required this.mtime,
    required this.size,
    required this.dedupKey,
    required this.patientName,
    required this.patientId,
    required this.dcmDate,
    this.isVolumetric = false,
  });

  Map<String, dynamic> toJson() => {
        'mtime': mtime.toIso8601String(),
        'size': size,
        'dedupKey': dedupKey,
        'patientName': patientName,
        'patientId': patientId,
        'dcmDate': dcmDate?.millisecondsSinceEpoch ?? 0,
        'isVolumetric': isVolumetric,
      };

  factory DicomCachedMeta.fromJson(Map<String, dynamic> json) =>
      DicomCachedMeta(
        mtime: DateTime.parse(json['mtime'] as String),
        size: json['size'] as int,
        dedupKey: json['dedupKey'] as String,
        patientName: json['patientName'] as String? ?? '',
        patientId: json['patientId'] as String? ?? '',
        dcmDate: (json['dcmDate'] as int) == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['dcmDate'] as int,
                isUtc: true),
        isVolumetric: json['isVolumetric'] == true,
      );
}

/// Hive-backed cache of parsed DICOM metadata, keyed by absolute file path.
///
/// Box name: `dicom_file_cache`. Stores [DicomCachedMeta] as JSON strings.
///
/// Usage during a scan:
/// 1. `isUnchanged(path, mtime, size)` → if true, reuse cached metadata
///    via `get(path)` without opening or parsing the file.
/// 2. Else: open + parse + `put(path, ...)` to update the cache.
/// 3. After the scan, `pruneMissing(currentPaths)` evicts entries for files
///    that have been deleted from disk.
class DicomFileCache {
  DicomFileCache._();

  static final DicomFileCache _instance = DicomFileCache._();
  static DicomFileCache get instance => _instance;

  late final Future<Box<String>> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await safeHiveInit();
    _box = Hive.openBox<String>('dicom_file_cache', path: await filesDir());
  }

  Future<Box<String>> get _openBox async {
    if (!_initialized) await init();
    return _box;
  }

  /// Returns true if the cache has an entry for [path] with the same
  /// [mtime] and [size] — meaning the file hasn't changed since it was
  /// last parsed, and the cached metadata can be reused.
  Future<bool> isUnchanged(String path, DateTime mtime, int size) async {
    try {
      final box = await _openBox;
      final raw = box.get(path);
      if (raw == null) return false;
      final cached = DicomCachedMeta.fromJson(jsonDecode(raw));
      return cached.size == size && cached.mtime.toUtc() == mtime.toUtc();
    } catch (e, s) {
      logger('DicomFileCache.isUnchanged error: $e', s, 2);
      return false;
    }
  }

  /// Returns the cached metadata for [path], or null if not cached.
  Future<DicomCachedMeta?> get(String path) async {
    try {
      final box = await _openBox;
      final raw = box.get(path);
      if (raw == null) return null;
      return DicomCachedMeta.fromJson(jsonDecode(raw));
    } catch (e, s) {
      logger('DicomFileCache.get error: $e', s, 2);
      return null;
    }
  }

  /// Stores or updates the cached metadata for [path].
  Future<void> put(String path, DicomCachedMeta meta) async {
    try {
      final box = await _openBox;
      await box.put(path, jsonEncode(meta.toJson()));
    } catch (e, s) {
      logger('DicomFileCache.put error: $e', s, 2);
    }
  }

  /// Evicts cache entries whose path is not in [currentPaths] — i.e., files
  /// that have been deleted from disk since the last scan.
  Future<void> pruneMissing(Set<String> currentPaths) async {
    try {
      final box = await _openBox;
      final staleKeys = box.keys
          .whereType<String>()
          .where((k) => !currentPaths.contains(k))
          .toList();
      await box.deleteAll(staleKeys);
      if (staleKeys.isNotEmpty) {
        log.info(
            'DicomFileCache.pruneMissing: evicted ${staleKeys.length} stale entries');
      }
    } catch (e, s) {
      logger('DicomFileCache.pruneMissing error: $e', s, 2);
    }
  }

  /// Returns a snapshot of the entire cache (path → meta). Used by
  /// [DicomImporter] to pass the cache into the scan isolate as plain data
  /// (the isolate can't touch Hive).
  Future<Map<String, DicomCachedMeta>> get snapshot async {
    try {
      final box = await _openBox;
      final out = <String, DicomCachedMeta>{};
      for (final key in box.keys.whereType<String>()) {
        final raw = box.get(key);
        if (raw == null) continue;
        try {
          out[key] = DicomCachedMeta.fromJson(jsonDecode(raw));
        } catch (_) {
          // skip malformed entries
        }
      }
      return out;
    } catch (e, s) {
      logger('DicomFileCache.snapshot error: $e', s, 2);
      return <String, DicomCachedMeta>{};
    }
  }

  /// Clears the entire cache. Useful for a "reset DICOM state" admin action.
  Future<void> clear() async {
    try {
      final box = await _openBox;
      await box.clear();
    } catch (e, s) {
      logger('DicomFileCache.clear error: $e', s, 2);
    }
  }
}

/// Singleton instance used throughout the app.
final dicomFileCache = DicomFileCache.instance;
