import 'dart:convert';
import 'dart:async';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

// Constants for metadata keys
const String _versionKey = 'meta:version';
const String _deferredKey = 'meta:deferred';

// this would be used in restore from remote backup functionality
final List<ClearingFunction> removeAllLocalData = [];
typedef ClearingFunction = Future<void> Function();

// SaveLocal class for managing local storage operations
class SaveLocal {
  final String name;
  final String uniqueId;
  late final Future<Box<String>> mainHiveBox;
  late final Future<Box<String>> metaHiveBox;

  SaveLocal({required this.name, required this.uniqueId}) {
    mainHiveBox = initialize("$name-main");
    metaHiveBox = initialize("$name-meta");
    removeAllLocalData.add(() async {
      await clear();
    });
  }

  Future<Box<String>> initialize(String name) async {
    await safeHiveInit();
    return Hive.openBox<String>(name + uniqueId, path: await filesDir());
  }

  // Put entries into the main box
  Future<void> put(Map<String, String> entries) async {
    try {
      final box = await mainHiveBox;
      await box.putAll(entries);
    } catch (e, s) {
      throw StorageException('Failed to put entries: $e', s);
    }
  }

  // Get a value from the main box
  Future<String> get(String key) async {
    try {
      final box = await mainHiveBox;
      return box.get(key) ?? "";
    } catch (e, s) {
      throw StorageException('Failed to get value for key $key: $e', s);
    }
  }

  // Get all values from the main box
  Future<Map<String, String>> getAll() async {
    try {
      final box = await mainHiveBox;
      return box.toMap().cast<String, String>();
    } catch (e, s) {
      throw StorageException('Failed to get all values: $e', s);
    }
  }

  // Get version from meta box
  Future<int> getVersion() async {
    try {
      final Box box = await metaHiveBox;
      return int.parse(box.get(_versionKey) ?? "0");
    } catch (e, s) {
      throw StorageException('Failed to get version: $e', s);
    }
  }

  // Put version into meta box
  Future<void> putVersion(int versionValue) async {
    try {
      final Box box = await metaHiveBox;
      await box.put(_versionKey, versionValue.toString());
    } catch (e, s) {
      throw StorageException('Failed to put version: $e', s);
    }
  }

  // Get deferred data from meta box
  Future<Map<String, int>> getDeferred() async {
    try {
      final Box box = await metaHiveBox;
      final jsonString = box.get(_deferredKey) ?? "{}";
      return Map<String, int>.from(jsonDecode(jsonString));
    } catch (e, s) {
      throw StorageException('Failed to get deferred data: $e', s);
    }
  }

  // Put deferred data into meta box
  Future<void> putDeferred(Map<String, int> deferred) async {
    try {
      final Box box = await metaHiveBox;
      await box.put(_deferredKey, jsonEncode(deferred));
    } catch (e, s) {
      throw StorageException('Failed to put deferred data: $e', s);
    }
  }

  Future<void> clear() async {
    try {
      final mainBox = await mainHiveBox;
      final metaBox = await metaHiveBox;
      await putVersion(0);
      await putDeferred({});
      await mainBox.clear();
      await metaBox.clear();
    } catch (e, s) {
      throw StorageException('Failed to clear storage: $e', s);
    }
  }
}

// Custom exception for storage operations
class StorageException implements Exception {
  final String message;
  final StackTrace stackTrace;
  StorageException(this.message, this.stackTrace);
  @override
  String toString() => 'StorageException: $message';
}
