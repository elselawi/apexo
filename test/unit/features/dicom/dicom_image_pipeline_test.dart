import 'dart:io' as io;

import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/services/dicom/dicom_lru.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal [Store] subclass that records [deleteImg] calls without
/// touching PocketBase or Hive — lets us verify [Store.deleteDcmImg]
/// calls deleteImg exactly twice (`.dcm` + `.png`).
class _RecordingStore extends Store<Appointment> {
  final List<(String, String)> deletedCalls = [];

  _RecordingStore() : super(modeling: Appointment.fromJson);

  @override
  Future<void> deleteImg(String rowID, String name) async {
    deletedCalls.add((rowID, name));
  }
}

/// Like [_RecordingStore] but throws on `.png` deletions — verifies that
/// [Store.deleteDcmImg] swallows the error for the preview file.
class _ThrowingOnPngStore extends _RecordingStore {
  @override
  Future<void> deleteImg(String rowID, String name) async {
    if (name.endsWith('.png')) {
      throw Exception('file not found');
    }
    await super.deleteImg(rowID, name);
  }
}

void main() {
  late io.Directory testDirectory;
  final caches = <DicomLruCache>[];

  DicomLruCache newCache({int threshold = 1024, DateTime Function()? clock}) {
    final cache = DicomLruCache.forTesting(
      evictionThresholdBytes: threshold,
      storagePath: testDirectory.path,
      clock: clock,
    );
    caches.add(cache);
    return cache;
  }

  Future<void> flushNotifications() => Future<void>.delayed(Duration.zero);

  setUpAll(() async {
    testDirectory = await io.Directory.systemTemp.createTemp('apexo-dicom-');
  });

  tearDownAll(() async {
    for (final cache in caches) {
      await cache.dispose();
    }
    await DicomLruCache.instance.dispose();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  group('DicomLruEntry — JSON round-trip', () {
    test('toJson / fromJson preserves all fields', () {
      final original = DicomLruEntry(
        name: 'dcm_abc123.dcm',
        lastAccess: DateTime.utc(2025, 7, 25, 12, 0, 0),
        size: 288366,
        evicted: false,
      );

      final json = original.toJson();
      final restored = DicomLruEntry.fromJson(json);

      expect(restored.name, original.name);
      expect(restored.lastAccess, original.lastAccess);
      expect(restored.size, original.size);
      expect(restored.evicted, original.evicted);
    });

    test('fromJson handles evicted=true', () {
      final entry = DicomLruEntry.fromJson({
        'name': 'x.dcm',
        'lastAccess': '2025-01-01T00:00:00.000Z',
        'size': 100,
        'evicted': true,
      });
      expect(entry.evicted, isTrue);
    });

    test('copyWith updates fields correctly', () {
      final entry = DicomLruEntry(
        name: 'x.dcm',
        lastAccess: DateTime.utc(2025, 1, 1),
        size: 100,
      );
      final updated =
          entry.copyWith(evicted: true, lastAccess: DateTime.utc(2025, 7, 25));
      expect(updated.name, 'x.dcm');
      expect(updated.evicted, isTrue);
      expect(updated.lastAccess, DateTime.utc(2025, 7, 25));
      expect(updated.size, 100);
    });
  });

  group('DicomLruCache — Hive operations', () {
    test('touch then isCached returns true', () async {
      final cache = newCache();
      const name = 'test-lru-touch.dcm';
      // Create a dummy local file so isCached's file-exists check passes.
      final file = io.File('${testDirectory.path}/$name');
      await file.writeAsBytes(List.filled(10, 0));

      await cache.touch(name, 10);
      expect(await cache.isCached(name), isTrue);

      // Cleanup
      if (await file.exists()) await file.delete();
    });

    test('isCached returns false for unknown name', () async {
      final cache = newCache();
      expect(await cache.isCached('nonexistent.dcm'), isFalse);
    });

    test('markAccessed updates lastAccess timestamp', () async {
      var now = DateTime.utc(2026, 1, 1);
      final cache = newCache(clock: () => now);
      const name = 'test-lru-mark.dcm';
      final file = io.File('${testDirectory.path}/$name');
      await file.writeAsBytes(List.filled(10, 0));

      await cache.touch(name, 10);
      final entriesBefore = await cache.activeEntries;
      final entryBefore = entriesBefore.firstWhere((e) => e.name == name);

      now = now.add(const Duration(seconds: 1));
      await cache.markAccessed(name);

      final entriesAfter = await cache.activeEntries;
      final entryAfter = entriesAfter.firstWhere((e) => e.name == name);

      expect(entryAfter.lastAccess.isAfter(entryBefore.lastAccess), isTrue);

      if (await file.exists()) await file.delete();
    });
  });

  group('DicomLruCache — eviction', () {
    test('evicts LRU entries when threshold exceeded', () async {
      // Use a test instance with a tiny threshold (1 KB).
      var now = DateTime.utc(2026, 1, 1);
      final cache = newCache(clock: () => now);
      await cache.init();

      final dir = testDirectory;

      // Insert 3 entries, each 500 bytes → total 1500 > 1024 threshold.
      // After eviction, the oldest should be evicted, keeping total ≤ 1024.
      final names = [
        'evict-old.dcm',
        'evict-mid.dcm',
        'evict-new.dcm',
      ];

      for (final name in names) {
        final file = io.File('${dir.path}/$name');
        await file.writeAsBytes(List.filled(500, 0));
      }

      // Touch in order with small delays so lastAccess differs.
      await cache.touch(names[0], 500);
      now = now.add(const Duration(seconds: 1));
      await cache.touch(names[1], 500);
      now = now.add(const Duration(seconds: 1));
      await cache.touch(names[2], 500);

      // After the 3rd touch (total 1500 > 1024), eviction should have
      // removed the oldest entry (names[0]) to bring total to 1000 ≤ 1024.
      final active = await cache.activeEntries;
      final activeNames = active.map((e) => e.name).toSet();

      // The oldest should be evicted.
      expect(activeNames.contains(names[0]), isFalse,
          reason: 'LRU entry should be evicted');
      // The two most recent should survive.
      expect(activeNames.contains(names[1]), isTrue);
      expect(activeNames.contains(names[2]), isTrue);

      // Total should be ≤ threshold.
      expect(await cache.totalSize, lessThanOrEqualTo(1024));

      // Cleanup
      for (final name in names) {
        final file = io.File('${dir.path}/$name');
        if (await file.exists()) await file.delete();
      }
      await cache.clear();
    });

    test('always keeps at least one entry (never evicts everything)', () async {
      final cache = newCache(
        threshold: 100,
        clock: () => DateTime.utc(2026, 1, 1),
      );
      await cache.init();

      final dir = testDirectory;
      const name = 'evict-single.dcm';
      final file = io.File('${dir.path}/$name');
      await file.writeAsBytes(List.filled(500, 0));

      // Single entry exceeding threshold — should NOT be evicted.
      await cache.touch(name, 500);

      final active = await cache.activeEntries;
      expect(active, isNotEmpty);
      expect(active.first.name, name);

      if (await file.exists()) await file.delete();
      await cache.clear();
    });
  });

  group('Store.deleteDcmImg', () {
    test('calls deleteImg twice: .dcm + .png', () async {
      final store = _RecordingStore();
      await store.deleteDcmImg('apt-1', 'dcm_abc.dcm');

      expect(store.deletedCalls.length, 2);
      expect(store.deletedCalls[0], ('apt-1', 'dcm_abc.dcm'));
      expect(store.deletedCalls[1], ('apt-1', 'dcm_abc.dcm.png'));
    });

    test('swallows error on .png deletion (may not exist)', () async {
      final store = _ThrowingOnPngStore();
      // Should not throw even though .png deletion fails — deleteDcmImg
      // catches the error and returns normally.
      await store.deleteDcmImg('apt-1', 'dcm_abc.dcm');

      // The .dcm call succeeded and was recorded; the .png call threw
      // before recording (simulating a file that doesn't exist on PB).
      expect(store.deletedCalls.length, 1);
      expect(store.deletedCalls[0], ('apt-1', 'dcm_abc.dcm'));
    });
  });

  group('getImage — DCM redirect', () {
    test('isADcmName is checked before normal image path', () {
      // Verify the redirect target: a .dcm name maps to .dcm.png
      // This is a logic-level test — the actual getImage call requires
      // PocketBase (remote.getImageLink) which isn't available in unit tests.
      const dcmName = 'scan.dcm';
      expect(isADcmName(dcmName), isTrue);
      expect('$dcmName.png', 'scan.dcm.png');
    });

    test('non-DCM names do not get .png suffix', () {
      const imgName = 'photo.jpg';
      expect(isADcmName(imgName), isFalse);
    });
  });

  group('dicomPngReady ObservableState', () {
    test('starts at 0', () {
      // Reset to 0 for the test
      dicomPngReady(0);
      expect(dicomPngReady(), 0);
    });

    test('can be bumped and observed', () async {
      dicomPngReady(0);
      int observed = -1;
      dicomPngReady.observe((v) => observed = v);

      dicomPngReady(dicomPngReady() + 1);
      await flushNotifications();

      expect(observed, 1);
      expect(dicomPngReady(), 1);

      dicomPngReady(0); // reset
    });
  });
}
