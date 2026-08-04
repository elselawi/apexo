import 'package:apexo/core/save_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

/// Unit-level tests for SaveRemote DTOs, filename hashing pattern,
/// and edge cases that don't require a real PocketBase server.
///
/// For integration-level upload/download/delete tests against a live
/// PocketBase instance, see `test/live_backend/core/save_remote_test.dart`.
void main() {
  final remote = SaveRemote(
    storeName: 'unit-test',
    // The DTO and timestamp tests below must not require credentials or a
    // reachable server. SaveRemote starts its health check in the
    // constructor, so cancel its retry timer when this file finishes.
    pbInstance: PocketBase('http://127.0.0.1:65535'),
  );

  tearDownAll(() {
    remote.timer?.cancel();
  });

  // ---------------------------------------------------------------------------
  // RowToWriteRemotely DTO
  // ---------------------------------------------------------------------------
  group('RowToWriteRemotely', () {
    test('defaults store to empty string', () {
      final r = RowToWriteRemotely(id: 'abc', data: '{"x":1}');
      expect(r.id, 'abc');
      expect(r.data, '{"x":1}');
      expect(r.store, '');
    });

    test('accepts explicit store name', () {
      final r = RowToWriteRemotely(id: 'r1', data: '{}');
      r.store = 'appointments';
      expect(r.store, 'appointments');
    });

    test('toJson includes id, data, and store', () {
      final r = RowToWriteRemotely(id: 'id1', data: '{"k":"v"}');
      r.store = 'patients';
      final j = r.toJson();
      expect(j['id'], 'id1');
      expect(j['data'], '{"k":"v"}');
      expect(j['store'], 'patients');
      expect(j.length, 3);
    });

    test('toJson when store is empty string includes it', () {
      final r = RowToWriteRemotely(id: 'id2', data: '{}');
      final j = r.toJson();
      expect(j['store'], '');
    });

    test('different instances with same fields are independent', () {
      final a = RowToWriteRemotely(id: 'x', data: '1');
      final b = RowToWriteRemotely(id: 'x', data: '1');
      expect(a.id, b.id);
      expect(a.data, b.data);
    });

    test('with empty data string', () {
      final r = RowToWriteRemotely(id: 'empty-data', data: '');
      expect(r.data, '');
      expect(r.toJson()['data'], '');
    });

    test('with nested JSON data', () {
      final r =
          RowToWriteRemotely(id: 'json', data: '{"complex":{"nested":true}}');
      expect(r.data, contains('nested'));
    });
  });

  // ---------------------------------------------------------------------------
  // Row DTO (extends RowToWriteRemotely)
  // ---------------------------------------------------------------------------
  group('Row', () {
    test('extends RowToWriteRemotely and adds ts', () {
      const ts = 1700000000000;
      final r = Row(id: 'row1', data: '{}', ts: ts);
      r.store = 'notes';
      expect(r.id, 'row1');
      expect(r.store, 'notes');
      expect(r.ts, ts);
    });

    test('toJson includes id, data, store but NOT ts (not overridden)', () {
      final r = Row(id: 'r6', data: '{"a":1}', ts: 99);
      r.store = 'appointments';
      final j = r.toJson();
      // Row inherits toJson from RowToWriteRemotely which only
      // serializes id, data, store. ts is NOT in the JSON output.
      expect(j['id'], 'r6');
      expect(j['data'], '{"a":1}');
      expect(j['store'], 'appointments');
      expect(j.length, 3);
    });

    test('ts can be a large timestamp (year 2038+)', () {
      final far = DateTime(2040, 1, 1).millisecondsSinceEpoch;
      final r = Row(id: 'row4', data: '{}', ts: far);
      expect(r.ts, far);
    });

    test('ts defaults to 0 when provided explicitly', () {
      final r = Row(id: 'row2', data: '{}', ts: 0);
      expect(r.ts, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // VersionedResult DTO
  // ---------------------------------------------------------------------------
  group('VersionedResult', () {
    test('holds version and rows (positional constructor)', () {
      final vr = VersionedResult(0, []);
      expect(vr.version, 0);
      expect(vr.rows, isEmpty);
    });

    test('version > 0 with non-empty rows', () {
      final rows = [Row(id: 'a', data: '{}', ts: 1)];
      final vr = VersionedResult(100, rows);
      expect(vr.version, 100);
      expect(vr.rows.length, 1);
    });

    test('rows list and version remain independently mutable DTO fields', () {
      final result = VersionedResult(1, []);
      result.version = 2;
      result.rows.add(Row(id: 'later', data: '{}', ts: 3));

      expect(result.version, 2);
      expect(result.rows.single.id, 'later');
      expect(result.rows.single.ts, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // PocketBase timestamp formatting
  // ---------------------------------------------------------------------------
  group('SaveRemote.formatForPocketBase', () {
    test('formats the epoch in PocketBase/SQLite UTC format', () {
      expect(remote.formatForPocketBase(0), '1970-01-01 00:00:00.000Z');
    });

    test('uses UTC rather than the machine local timezone', () {
      final timestamp =
          DateTime.utc(2024, 2, 29, 23, 59, 58, 123).millisecondsSinceEpoch;
      expect(
        remote.formatForPocketBase(timestamp),
        '2024-02-29 23:59:58.123Z',
      );
    });

    test('retains milliseconds required by incremental sync comparisons', () {
      final timestamp =
          DateTime.utc(2038, 1, 19, 3, 14, 7, 7).millisecondsSinceEpoch;
      final formatted = remote.formatForPocketBase(timestamp);

      expect(formatted, endsWith('.007Z'));
      expect(formatted, contains('2038-01-19 03:14:07'));
    });
  });

  // ---------------------------------------------------------------------------
  // Filename hash pattern (_$hash format used by _findExistingByHash)
  // ---------------------------------------------------------------------------
  group('Filename hash pattern', () {
    test('recognizes _hash.extension pattern', () {
      const filename = 'photo_h1a2b3c4d5e6f7g8.jpg';
      final parts = filename.split('_');
      final hash = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      // h1a2b3c4d5e6f7g8 is 16 hex chars
      expect(hash, 'h1a2b3c4d5e6f7g8');
      expect(hash.length, 16);
    });

    test('hash from complex name with multiple underscores', () {
      const filename = 'scan_report_h2x3y4z5.jpg';
      final parts = filename.split('_');
      final hash = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(hash, 'h2x3y4z5');
    });

    test('no-underscore filename gives whole basename as "hash"', () {
      const filename = 'simple.jpg';
      final parts = filename.split('_');
      final hash = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(hash, 'simple');
    });

    test('no extension just returns last segment', () {
      const filename = 'rawfile_h1h2h3h4';
      final parts = filename.split('_');
      final hash = parts.last;
      expect(hash, 'h1h2h3h4');
    });

    test('case is preserved for hash matching', () {
      const filename = 'xray_AbC123.DCM';
      final hash = filename.split('_').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(hash, 'AbC123');
    });
  });
}
