import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:path/path.dart' as p;

/// A tracked downloaded `.dcm` original in the LRU cache.
///
/// Hive box `dicom_lru` stores these as JSON, keyed by the local filename
/// in `filesDir()`. The [lastAccess] timestamp drives LRU eviction when
/// the total DCM cache exceeds [DicomLruCache.evictionThresholdBytes].
class DicomLruEntry {
  /// Local filename (relative to `filesDir()`).
  final String name;

  /// Last access time (updated each time the viewer opens the file).
  final DateTime lastAccess;

  /// File size in bytes (captured at insertion time).
  final int size;

  /// Whether the local file has been evicted (deleted to free space).
  /// The Hive entry is kept so we know the file was once cached; the next
  /// viewer open re-downloads it transparently and clears this flag.
  final bool evicted;

  const DicomLruEntry({
    required this.name,
    required this.lastAccess,
    required this.size,
    this.evicted = false,
  });

  DicomLruEntry copyWith({
    DateTime? lastAccess,
    int? size,
    bool? evicted,
  }) =>
      DicomLruEntry(
        name: name,
        lastAccess: lastAccess ?? this.lastAccess,
        size: size ?? this.size,
        evicted: evicted ?? this.evicted,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'lastAccess': lastAccess.toIso8601String(),
        'size': size,
        'evicted': evicted,
      };

  factory DicomLruEntry.fromJson(Map<String, dynamic> json) => DicomLruEntry(
        name: json['name'] as String? ?? '',
        lastAccess: json['lastAccess'] != null
            ? DateTime.parse(json['lastAccess'] as String)
            : DateTime.fromMillisecondsSinceEpoch(0),
        size: json['size'] as int? ?? 0,
        evicted: json['evicted'] as bool? ?? false,
      );
}

/// Hive-backed LRU cache of downloaded `.dcm` originals on native platforms.
///
/// Xray images run 5–20 MB; a full-mouth series is ~18 images (up to 360 MB).
/// Without eviction, `filesDir()` would grow unbounded on mobile devices.
/// This cache tracks every downloaded `.dcm` and, when the total exceeds
/// [evictionThresholdBytes] (500 MB by default), evicts the least-recently-
/// accessed entries — deleting the local file while keeping the Hive entry
/// marked as `evicted`. The next viewer open re-downloads transparently.
///
/// On web there is no filesystem, so this cache is never used (the viewer
/// fetches the `.dcm` fresh per session into memory only).
class DicomLruCache {
  // ignore: unused_element_parameter
  DicomLruCache._({this.evictionThresholdBytes = _defaultThreshold});

  static const int _defaultThreshold = 500 * 1024 * 1024; // 500 MB

  static final DicomLruCache _instance = DicomLruCache._();
  static DicomLruCache get instance => _instance;

  /// Creates an instance with a custom eviction threshold. For testing only —
  /// the singleton uses the default 500 MB threshold.
  @visibleForTesting
  DicomLruCache.forTesting({this.evictionThresholdBytes = 1024});

  /// When the total size of non-evicted entries exceeds this, the LRU
  /// entries are evicted (local files deleted) until usage drops below it.
  final int evictionThresholdBytes;

  late final Future<Box<String>> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await safeHiveInit();
    _box = Hive.openBox<String>('dicom_lru', path: await filesDir());
  }

  Future<Box<String>> get _openBox async {
    if (!_initialized) await init();
    return _box;
  }

  /// Records a `.dcm` download (or updates the access timestamp on re-open).
  /// After insertion, runs eviction if the threshold is exceeded.
  Future<void> touch(String name, int size) async {
    try {
      final box = await _openBox;
      final entry = DicomLruEntry(
        name: name,
        lastAccess: DateTime.now(),
        size: size,
        evicted: false,
      );
      await box.put(name, jsonEncode(entry.toJson()));
      await _evictIfNeeded();
    } catch (e, s) {
      logger('DicomLruCache.touch error: $e', s, 2);
    }
  }

  /// Marks [name] as accessed (updates [DicomLruEntry.lastAccess]) without
  /// changing the size. Called when the viewer opens an already-cached file.
  Future<void> markAccessed(String name) async {
    try {
      final box = await _openBox;
      final raw = box.get(name);
      if (raw == null) return;
      final entry =
          DicomLruEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await box.put(
          name,
          jsonEncode(entry
              .copyWith(lastAccess: DateTime.now(), evicted: false)
              .toJson()));
    } catch (e, s) {
      logger('DicomLruCache.markAccessed error: $e', s, 2);
    }
  }

  /// Returns `true` if the `.dcm` exists locally and is not evicted.
  Future<bool> isCached(String name) async {
    try {
      final box = await _openBox;
      final raw = box.get(name);
      if (raw == null) return false;
      final entry =
          DicomLruEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (entry.evicted) return false;
      final file = File(p.join(await filesDir(), name));
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Returns all non-evicted entries (for inspection / debugging).
  Future<List<DicomLruEntry>> get activeEntries async {
    try {
      final box = await _openBox;
      return box.values
          .map((raw) {
            try {
              return DicomLruEntry.fromJson(
                  jsonDecode(raw) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<DicomLruEntry>()
          .where((e) => !e.evicted)
          .toList();
    } catch (e, s) {
      logger('DicomLruCache.activeEntries error: $e', s, 2);
      return [];
    }
  }

  /// Total size of all non-evicted entries, in bytes.
  Future<int> get totalSize async {
    final entries = await activeEntries;
    return entries.fold<int>(0, (sum, e) => sum + e.size);
  }

  /// If total size exceeds [evictionThresholdBytes], evicts LRU entries
  /// (deletes their local files, marks them `evicted`) until usage is
  /// below the threshold. At least one entry always survives (the most
  /// recently accessed) so the viewer never evicts the file being viewed.
  Future<void> _evictIfNeeded() async {
    try {
      final entries = await activeEntries;
      int total = entries.fold<int>(0, (sum, e) => sum + e.size);
      if (total <= evictionThresholdBytes) return;

      // Sort by lastAccess ascending (oldest first = LRU).
      entries.sort((a, b) => a.lastAccess.compareTo(b.lastAccess));

      final box = await _openBox;
      final dir = await filesDir();

      // Evict from the oldest, but always keep at least 1 entry.
      for (int i = 0;
          i < entries.length - 1 && total > evictionThresholdBytes;
          i++) {
        final entry = entries[i];
        try {
          final file = File(p.join(dir, entry.name));
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // file may already be gone — proceed
        }
        await box.put(
            entry.name, jsonEncode(entry.copyWith(evicted: true).toJson()));
        total -= entry.size;
      }
    } catch (e, s) {
      logger('DicomLruCache._evictIfNeeded error: $e', s, 2);
    }
  }

  /// Clears the entire cache (deletes all local `.dcm` files + Hive entries).
  Future<void> clear() async {
    try {
      final box = await _openBox;
      final dir = await filesDir();
      for (final raw in box.values) {
        try {
          final entry =
              DicomLruEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          final file = File(p.join(dir, entry.name));
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      await box.clear();
    } catch (e, s) {
      logger('DicomLruCache.clear error: $e', s, 2);
    }
  }
}

/// Singleton used throughout the app.
final dicomLruCache = DicomLruCache.instance;
