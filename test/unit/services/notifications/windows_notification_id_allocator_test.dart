@Tags(['serial'])
library;

import 'package:apexo/services/notifications/windows_notification_id_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements WindowsNotificationIdStore {
  _MemoryStore([this.next = 1]);

  int next;
  int writes = 0;
  bool closed = false;

  @override
  Future<int> readNext() async {
    return next;
  }

  @override
  Future<void> writeNext(int value) async {
    writes++;
    next = value;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test('allocates distinct ids across process-like allocator instances',
      () async {
    final store = _MemoryStore();
    final firstProcess = WindowsNotificationIdAllocator(store: store);
    final secondProcess = WindowsNotificationIdAllocator(store: store);

    final ids = <int>[
      await firstProcess.nextId(),
      await firstProcess.nextId(),
      await secondProcess.nextId(),
      await secondProcess.nextId(),
    ];

    expect(ids, [1, 2, 3, 4]);
    expect(store.writes, 4,
        reason: 'the next id is persisted before it is returned');
  });

  test('serializes concurrent allocations', () async {
    final store = _MemoryStore();
    final allocator = WindowsNotificationIdAllocator(store: store);

    final ids = await Future.wait(
      List<Future<int>>.generate(40, (_) => allocator.nextId()),
    );

    expect(ids.toSet(), hasLength(40));
    expect(ids, List<int>.generate(40, (index) => index + 1));
  });

  test('wraps the positive signed 32-bit range without using tag zero',
      () async {
    final store = _MemoryStore(WindowsNotificationIdAllocator.maxId);
    final allocator = WindowsNotificationIdAllocator(store: store);

    expect(await allocator.nextId(), WindowsNotificationIdAllocator.maxId);
    expect(await allocator.nextId(), 1);
    expect(await allocator.nextId(), 2);
  });

  test('repairs an invalid persisted value instead of returning tag zero',
      () async {
    for (final invalid in [0, -1, WindowsNotificationIdAllocator.maxId + 1]) {
      final store = _MemoryStore(invalid);
      final allocator = WindowsNotificationIdAllocator(store: store);
      expect(await allocator.nextId(), 1, reason: 'stored value $invalid');
    }
  });

  test('close delegates to the backing store', () async {
    final store = _MemoryStore();
    final allocator = WindowsNotificationIdAllocator(store: store);

    await allocator.close();

    expect(store.closed, isTrue);
  });
}
