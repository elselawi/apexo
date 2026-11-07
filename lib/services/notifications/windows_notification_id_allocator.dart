import 'dart:async';

import 'package:apexo/core/persistence/serial_operation_queue.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Persisted storage for the next Windows toast id; it must open from a hidden
/// push process before any staff store exists, so it cannot reuse a clinic store.
abstract interface class WindowsNotificationIdStore {
  Future<int> readNext();

  Future<void> writeNext(int value);

  Future<void> close();
}

/// The production store: a tiny Hive box beside the app's other local data.
class HiveWindowsNotificationIdStore implements WindowsNotificationIdStore {
  Box<int>? _box;

  Future<Box<int>> _open() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    await safeHiveInit();
    final box = await Hive.openBox<int>(
      'windows-notification-ids',
      path: await filesDir(),
    );
    _box = box;
    return box;
  }

  @override
  Future<int> readNext() async {
    final box = await _open();
    return box.get(_nextKey, defaultValue: 1) ?? 1;
  }

  @override
  Future<void> writeNext(int value) async {
    final box = await _open();
    await box.put(_nextKey, value);
  }

  @override
  Future<void> close() async {
    final box = _box;
    _box = null;
    if (box != null && box.isOpen) await box.close();
  }

  static const String _nextKey = 'next-id';
}

/// Allocates the toast Tag. A process-local counter restarts at zero in every
/// hidden push process, so the next id is persisted before the current one is
/// returned: a crash can skip an id, but two toasts cannot share one.
class WindowsNotificationIdAllocator {
  WindowsNotificationIdAllocator({WindowsNotificationIdStore? store})
      : _store = store ?? HiveWindowsNotificationIdStore();

  final WindowsNotificationIdStore _store;
  final SerialOperationQueue _queue = SerialOperationQueue();

  static const int maxId = 0x7fffffff;

  Future<int> nextId() {
    return _queue.run(() async {
      final current = await _store.readNext();
      final id = current < 1 || current > maxId ? 1 : current;
      final next = id == maxId ? 1 : id + 1;
      await _store.writeNext(next);
      return id;
    });
  }

  Future<void> close() => _store.close();
}
