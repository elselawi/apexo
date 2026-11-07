import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:path/path.dart' as p;

bool _cachedFileExists(String path) => File(path).existsSync();

/// A downloaded `.dcm` in the LRU cache. The Hive box stores these as JSON
/// keyed by local filename; [lastAccess] drives eviction order.
class DicomLruEntry {
  const DicomLruEntry({
    required this.name,
    required this.lastAccess,
    required this.size,
    this.evicted = false,
  });

  factory DicomLruEntry.fromJson(Map<String, dynamic> json) => DicomLruEntry(
        name: json['name'] as String? ?? '',
        lastAccess: json['lastAccess'] != null
            ? DateTime.parse(json['lastAccess'] as String)
            : DateTime.fromMillisecondsSinceEpoch(0),
        size: json['size'] as int? ?? 0,
        evicted: json['evicted'] as bool? ?? false,
      );

  /// Local filename (relative to `filesDir()`).
  final String name;

  /// Last access time (updated each time the viewer opens the file).
  final DateTime lastAccess;

  /// File size in bytes (captured at insertion time).
  final int size;

  /// The local file was deleted to free space; the entry stays so the next
  /// viewer open re-downloads it and clears this flag.
  final bool evicted;

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
}

/// Hive-backed LRU cache of downloaded `.dcm` originals. Past
/// [evictionThresholdBytes] the oldest files are deleted but their entries are
/// kept (marked `evicted`), so `filesDir()` stays bounded.
class DicomLruCache {
  @visibleForTesting
  DicomLruCache.forTesting({
    this.evictionThresholdBytes = 1024,
    this.storagePath,
    String? boxName,
    DateTime Function()? clock,
  })  : boxName = boxName ?? 'dicom_lru_test_${++_testBoxSequence}',
        _clock = clock ?? DateTime.now;
  DicomLruCache._({
    DateTime Function()? clock,
  })  : storagePath = null,
        evictionThresholdBytes = _defaultThreshold,
        boxName = _defaultBoxName,
        _clock = clock ?? DateTime.now;

  static const int _defaultThreshold = 500 * 1024 * 1024; // 500 MB
  static const String _defaultBoxName = 'dicom_lru';
  static int _testBoxSequence = 0;

  static final DicomLruCache _instance = DicomLruCache._();
  static DicomLruCache get instance => _instance;

  final int evictionThresholdBytes;
  final String? storagePath;
  final String boxName;
  final DateTime Function() _clock;

  Future<Box<String>>? _box;
  Future<void>? _initialization;

  Future<void> init() {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _initialize();
    _initialization = initialization;
    // On a failed open, clear the memoized future so a later call retries
    // instead of reusing a half-open box that throws on every access.
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
    final box = Hive.openBox<String>(
      boxName,
      path: storagePath ?? await filesDir(),
    );
    _box = box;
    await box;
  }

  Future<Box<String>> get _openBox async {
    await init();
    return _box!;
  }

  Future<void> touch(String name, int size) async {
    try {
      final box = await _openBox;
      final entry = DicomLruEntry(
        name: name,
        lastAccess: _clock(),
        size: size,
        evicted: false,
      );
      await box.put(name, jsonEncode(entry.toJson()));
      await _evictIfNeeded();
    } catch (e, s) {
      logger('DicomLruCache.touch error: $e', s, 2);
    }
  }

  Future<void> markAccessed(String name) async {
    try {
      final box = await _openBox;
      final raw = box.get(name);
      if (raw == null) return;
      final entry =
          DicomLruEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await box.put(
          name,
          jsonEncode(
              entry.copyWith(lastAccess: _clock(), evicted: false).toJson()));
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
      final file = File(p.join(storagePath ?? await filesDir(), name));
      return await compute(_cachedFileExists, file.path);
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

  // Evicts oldest entries until usage is under [evictionThresholdBytes]. The
  // newest entry always survives, so the viewer never evicts the open file.
  Future<void> _evictIfNeeded() async {
    try {
      final entries = await activeEntries;
      int total = entries.fold<int>(0, (sum, e) => sum + e.size);
      if (total <= evictionThresholdBytes) return;

      // Sort by lastAccess ascending (oldest first = LRU).
      entries.sort((a, b) => a.lastAccess.compareTo(b.lastAccess));

      final box = await _openBox;
      final dir = storagePath ?? await filesDir();

      // Evict from the oldest, but always keep at least 1 entry.
      for (int i = 0;
          i < entries.length - 1 && total > evictionThresholdBytes;
          i++) {
        final entry = entries[i];
        try {
          final file = File(p.join(dir, entry.name));
          if (await compute(_cachedFileExists, file.path)) {
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
      final dir = storagePath ?? await filesDir();
      for (final raw in box.values) {
        try {
          final entry =
              DicomLruEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          final file = File(p.join(dir, entry.name));
          if (await compute(_cachedFileExists, file.path)) await file.delete();
        } catch (_) {}
      }
      await box.clear();
    } catch (e, s) {
      logger('DicomLruCache.clear error: $e', s, 2);
    }
  }

  /// Closes the cache box. Intended for short-lived clients and tests.
  Future<void> dispose() async {
    final initialization = _initialization;
    if (initialization == null && _box == null) return;
    // Wait for an in-flight open so we don't clear state mid-initialization.
    try {
      await initialization;
    } catch (_) {}
    try {
      final box = await _box;
      if (box != null && box.isOpen) await box.close();
    } finally {
      _initialization = null;
      _box = null;
    }
  }
}

/// Singleton used throughout the app.
final dicomLruCache = DicomLruCache.instance;
