import 'dart:async';

import 'package:apexo/core/persistence/serial_operation_queue.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';

/// Persisted storage for the next Windows toast id.
///
/// The allocator talks to this interface so tests can use an in-memory store;
/// production uses a Hive box in the app's files directory. It must work from a
/// hidden process before any staff store is initialized, which is why it does
/// not reuse a clinic's store.
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

/// Allocates the numeric tag a Windows toast is shown with.
///
/// The installed Windows local-notifications plugin uses the numeric id as the
/// toast Tag. A process-local counter restarts at zero in every hidden process,
/// so successive pushes would replace the previous notification. This allocator
/// persists the *next* id before returning the current one; a crash can skip an
/// id, but two displayed notifications cannot share one.
///
/// The id stays in the positive signed 32-bit range the native tag accepts. On
/// wraparound it restarts at 1; reaching that point takes 2,147,483,647
/// notifications, and the previous tag has long left the notification centre.
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
