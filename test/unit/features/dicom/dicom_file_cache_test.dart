import 'dart:convert';

import 'package:apexo/services/dicom/dicom_file_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DicomCachedMeta — JSON round-trip', () {
    test('toJson / fromJson preserves all fields', () {
      final original = DicomCachedMeta(
        mtime: DateTime.utc(2025, 7, 25, 12, 0, 0),
        size: 288366,
        dedupKey: 'sop:1.2.3.4',
        patientName: 'Smith^John',
        patientId: 'MRN123',
        dcmDate: DateTime.utc(2025, 7, 25),
      );

      final json = original.toJson();
      final restored = DicomCachedMeta.fromJson(json);

      expect(restored.mtime, original.mtime);
      expect(restored.size, original.size);
      expect(restored.dedupKey, original.dedupKey);
      expect(restored.patientName, original.patientName);
      expect(restored.patientId, original.patientId);
      expect(restored.dcmDate, original.dcmDate);
    });

    test(
        'fromJson handles missing optional fields gracefully (empty strings, null date)',
        () {
      final json = jsonDecode(
              '{"mtime":"2025-07-25T12:00:00.000Z","size":100,"dedupKey":"sop:1","dcmDate":0}')
          as Map<String, dynamic>;
      final restored = DicomCachedMeta.fromJson(json);
      expect(restored.patientName, '');
      expect(restored.patientId, '');
      expect(restored.dcmDate, isNull);
    });

    test('toJson produces valid JSON string', () {
      final meta = DicomCachedMeta(
        mtime: DateTime.utc(2025, 1, 1),
        size: 100,
        dedupKey: 'sop:1',
        patientName: 'Test',
        patientId: 'T1',
        dcmDate: DateTime.utc(2025, 1, 1),
      );
      final jsonStr = jsonEncode(meta.toJson());
      expect(jsonStr, contains('"dedupKey":"sop:1"'));
      expect(jsonStr, contains('"size":100'));
    });
  });

  group('DicomFileCache — Hive operations', () {
    test('isUnchanged returns false for uncached path', () async {
      // The cache box is opened lazily; in flutter test it uses a temp dir.
      // We use a unique path to avoid collisions with other tests.
      final cache = DicomFileCache.instance;
      final result = await cache.isUnchanged(
        '/nonexistent/test-uncached-${DateTime.now().microsecondsSinceEpoch}.dcm',
        DateTime.now(),
        100,
      );
      expect(result, isFalse);
    });

    test('put then get returns the cached metadata', () async {
      final cache = DicomFileCache.instance;
      final testPath =
          '/test/put-get-${DateTime.now().microsecondsSinceEpoch}.dcm';
      final meta = DicomCachedMeta(
        mtime: DateTime.utc(2025, 7, 25),
        size: 288366,
        dedupKey: 'sop:test-put-get',
        patientName: 'Test Patient',
        patientId: 'TEST001',
        dcmDate: DateTime.utc(2025, 7, 25),
      );

      await cache.put(testPath, meta);
      final retrieved = await cache.get(testPath);

      expect(retrieved, isNotNull);
      expect(retrieved!.dedupKey, 'sop:test-put-get');
      expect(retrieved.patientName, 'Test Patient');
      expect(retrieved.patientId, 'TEST001');
      expect(retrieved.size, 288366);
    });

    test('isUnchanged returns true after put with same mtime+size', () async {
      final cache = DicomFileCache.instance;
      final testPath =
          '/test/unchanged-${DateTime.now().microsecondsSinceEpoch}.dcm';
      final mtime = DateTime.utc(2025, 7, 25, 12, 0, 0);
      final size = 288366;

      final meta = DicomCachedMeta(
        mtime: mtime,
        size: size,
        dedupKey: 'sop:unchanged',
        patientName: 'Test',
        patientId: 'T1',
        dcmDate: DateTime.utc(2025, 7, 25),
      );

      await cache.put(testPath, meta);
      expect(await cache.isUnchanged(testPath, mtime, size), isTrue);
    });

    test('isUnchanged returns false after mtime changes', () async {
      final cache = DicomFileCache.instance;
      final testPath =
          '/test/mtime-change-${DateTime.now().microsecondsSinceEpoch}.dcm';
      final oldMtime = DateTime.utc(2025, 7, 25, 12, 0, 0);
      final newMtime = DateTime.utc(2025, 7, 25, 13, 0, 0);
      final size = 288366;

      final meta = DicomCachedMeta(
        mtime: oldMtime,
        size: size,
        dedupKey: 'sop:mtime-change',
        patientName: 'Test',
        patientId: 'T1',
        dcmDate: DateTime.utc(2025, 7, 25),
      );

      await cache.put(testPath, meta);
      expect(await cache.isUnchanged(testPath, newMtime, size), isFalse);
    });

    test('isUnchanged returns false after size changes', () async {
      final cache = DicomFileCache.instance;
      final testPath =
          '/test/size-change-${DateTime.now().microsecondsSinceEpoch}.dcm';
      final mtime = DateTime.utc(2025, 7, 25, 12, 0, 0);

      final meta = DicomCachedMeta(
        mtime: mtime,
        size: 288366,
        dedupKey: 'sop:size-change',
        patientName: 'Test',
        patientId: 'T1',
        dcmDate: DateTime.utc(2025, 7, 25),
      );

      await cache.put(testPath, meta);
      expect(await cache.isUnchanged(testPath, mtime, 999999), isFalse);
    });

    test('pruneMissing evicts stale entries', () async {
      final cache = DicomFileCache.instance;
      final keepPath =
          '/test/keep-${DateTime.now().microsecondsSinceEpoch}.dcm';
      final stalePath =
          '/test/stale-${DateTime.now().microsecondsSinceEpoch}.dcm';

      final meta = DicomCachedMeta(
        mtime: DateTime.utc(2025, 7, 25),
        size: 100,
        dedupKey: 'sop:prune',
        patientName: 'Test',
        patientId: 'T1',
        dcmDate: DateTime.utc(2025, 7, 25),
      );

      await cache.put(keepPath, meta);
      await cache.put(stalePath, meta);

      // prune — only keepPath is in the current set
      await cache.pruneMissing({keepPath});

      expect(await cache.get(keepPath), isNotNull);
      expect(await cache.get(stalePath), isNull);
    });
  });
}
