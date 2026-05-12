import 'dart:async';
import 'dart:convert';
import 'package:apexo/core/save_local.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/model_push_data.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

class _DeferredPush {
  late final Future<Box<String>> hiveBox;

  bool _initialized = false;

  void init(String clinicServer) {
    if (_initialized) return;
    _initialized = true;
    hiveBox = _initialize(clinicServer);
  }

  Future<Box<String>> _initialize(String clinicServer) async {
    await safeHiveInit();
    return Hive.openBox<String>("push-${simpleHash(clinicServer)}",
        path: await filesDir());
  }

  // Put notifications into the box
  Future<void> putBulk(List<PushData> toPush) async {
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
        return PushData.fromJson(jsonDecode(boxRes));
      } else {
        return null;
      }
    } catch (e, s) {
      throw StorageException('Failed to get value for key $key: $e', s);
    }
  }

  Future<void> clearByStore(String store) async {
    if (!_initialized) init(login.url);
    try {
      final box = await hiveBox;
      final List<String> keysToDelete = [];
      for (var encoded in box.values) {
        final decoded = jsonDecode(encoded);
        if (decoded['store'] == store) keysToDelete.add(decoded['id']);
      }
      await box.deleteAll(keysToDelete);
    } catch (e, s) {
      throw StorageException('Failed to clear storage: $e', s);
    }
  }
}

final deferredPush = _DeferredPush();
