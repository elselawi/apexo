import 'dart:async';
import 'dart:convert';
import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

class _DeferredPush {
  /// **`late`, not `late final`.** [reset] exists so that the *next* login re-runs
  /// [init] for its own clinic server — and assigning a `late final` a second time
  /// throws `LateInitializationError`. That throw used to land inside
  /// `Messaging.identifyDevice`, so on every login after the first one in a
  /// process the clinic's relay key was never ensured and no device was
  /// registered (`accounts 08`, which signs in twice).
  late Future<Box<String>> hiveBox;

  bool _initialized = false;

  void init(String clinicServer) {
    if (_initialized) return;
    _initialized = true;
    hiveBox = _initialize(clinicServer);
  }

  /// Resets so [init] re-runs for the next login (different server = different
  /// Hive box). Called from [Login.logout] via [onLogoutCallbacks].
  void reset() {
    _initialized = false;
  }

  Future<Box<String>> _initialize(String clinicServer) async {
    await safeHiveInit();
    return Hive.openBox<String>("push-${simpleHash(clinicServer)}",
        path: await filesDir());
  }

  // Put notifications into the box
  Future<void> putBulk(List<PushData> toPush) async {
    if (toPush.isEmpty) return;
    if (!_initialized) init(login.url);
    try {
      final box = await hiveBox;
      await box.putAll(
        {for (var n in toPush) n.id: jsonEncode(n.toJson())},
      );
    } catch (e, s) {
      throw StorageException('Failed to put entries: $e', s);
    }
  }

  // Get a value from the main box
  Future<PushData?> getByID(String key) async {
    if (!_initialized) init(login.url);
    try {
      final box = await hiveBox;
      final boxRes = box.get(key);
      if (boxRes != null) {
        return PushData.fromJson(jsonDecode(boxRes) as Map<String, dynamic>);
      } else {
        return null;
      }
    } catch (e, s) {
      throw StorageException('Failed to get value for key $key: $e', s);
    }
  }

  Future<void> clearByIDs(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    if (!_initialized) init(login.url);
    try {
      final box = await hiveBox;
      await box.deleteAll(ids);
    } catch (e, s) {
      throw StorageException('Failed to clear entries by ID: $e', s);
    }
  }

  Future<void> clearByStore(String store) async {
    if (!_initialized) init(login.url);
    try {
      final box = await hiveBox;
      final List<dynamic> keysToDelete = [];
      for (final entry in box.toMap().entries) {
        try {
          final decoded = jsonDecode(entry.value) as Map<String, dynamic>;
          if (decoded['store'] == store) {
            keysToDelete.add(entry.key);
          }
        } catch (_) {
          // Discard corrupted JSON entries so they cannot permanently wedge the queue.
          keysToDelete.add(entry.key);
        }
      }
      if (keysToDelete.isNotEmpty) {
        await box.deleteAll(keysToDelete);
      }
    } catch (e, s) {
      throw StorageException('Failed to clear storage: $e', s);
    }
  }
}

final deferredPush = _DeferredPush();
