import 'dart:convert';

import 'package:apexo/core/persistence/save_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

const _cursorDate = '2026-10-13 10:00:00.000Z';
const _firstDate = '2026-10-13 10:00:01.000Z';
const _lastDate = '2026-10-13 10:00:02.000Z';

String _id(int value) => value.toString().padLeft(15, '0');

int _timestamp(String date) => DateTime.parse(date).millisecondsSinceEpoch;

Map<String, dynamic> _record(
  int id,
  String updated, {
  String store = 'appointments',
  int revision = 1,
}) =>
    {
      'id': _id(id),
      'collectionId': 'data',
      'collectionName': 'data',
      'store': store,
      'updated': updated,
      'data': {'revision': revision},
      'imgs': ['photo_${id}_$revision.jpg'],
    };

class _MutablePocketBaseApi {
  final rows = <Map<String, dynamic>>[];
  final pageRequests = <http.Request>[];
  int pageReads = 0;
  void Function(int)? beforePageRead;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/api/health')) {
      return _json({'code': 200, 'message': 'ok'});
    }
    if (request.method != 'GET' || !request.url.path.endsWith('/records')) {
      return _json({'code': 404, 'message': 'Unexpected request'}, 404);
    }

    final query = request.url.queryParameters;
    if ((query['fields'] ?? '').split(',').contains('data')) {
      pageRequests.add(request);
      beforePageRead?.call(++pageReads);
    }

    final filter = query['filter'] ?? '';
    final store = RegExp(r'store="([^"]+)"').firstMatch(filter)?.group(1);
    final lowerDates = RegExp(r'updated>"([^"]+)"').allMatches(filter);
    final lower = lowerDates.isEmpty ? null : lowerDates.last.group(1);
    final equal = RegExp(r'updated="([^"]+)"').firstMatch(filter)?.group(1);
    final afterId = RegExp(r'id>"([^"]+)"').firstMatch(filter)?.group(1);
    final upper = RegExp(r'updated<="([^"]+)"').firstMatch(filter)?.group(1);
    final matching = rows.where((row) {
      if (store != null && row['store'] != store) return false;
      final updated = row['updated'] as String;
      final newer = lower == null || updated.compareTo(lower) > 0;
      final tied = equal != null &&
          updated == equal &&
          afterId != null &&
          (row['id'] as String).compareTo(afterId) > 0;
      return (newer || tied) &&
          (upper == null || updated.compareTo(upper) <= 0);
    }).toList();

    final sort = (query['sort'] ?? '').split(',');
    matching.sort((a, b) {
      for (final key in sort) {
        if (key.isEmpty) continue;
        final descending = key.startsWith('-');
        final field = descending ? key.substring(1) : key;
        final comparison = (a[field] as String).compareTo(b[field] as String);
        if (comparison != 0) return descending ? -comparison : comparison;
      }
      return 0;
    });

    final page = int.parse(query['page'] ?? '1');
    final perPage = int.parse(query['perPage'] ?? '30');
    final skipTotal = query['skipTotal'] == 'true';
    return _json({
      'page': page,
      'perPage': perPage,
      'totalItems': skipTotal ? -1 : matching.length,
      'totalPages': skipTotal ? -1 : (matching.length / perPage).ceil(),
      'items': matching.skip((page - 1) * perPage).take(perPage).toList(),
    });
  }

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: const {'content-type': 'application/json'},
      );
}

void main() {
  late _MutablePocketBaseApi api;
  late MockClient client;
  late SaveRemote remote;

  setUp(() {
    api = _MutablePocketBaseApi();
    client = MockClient(api.handle);
    remote = SaveRemote(
      storeName: 'appointments',
      pbInstance: PocketBase(
        'http://fake-pocketbase',
        httpClientFactory: () => client,
      ),
    );
  });

  tearDown(() {
    remote.dispose();
    client.close();
  });

  group('getSince keyset pagination', () {
    test('concurrent updates never skip unseen rows or duplicate identities',
        () async {
      api.rows.addAll([
        for (var id = 1; id <= 1801; id++) _record(id, _firstDate),
        _record(1802, _lastDate),
      ]);
      api.beforePageRead = (page) {
        if (page != 2) return;
        // Moving a fetched row to the tail shifts every remaining offset.
        api.rows[0]
          ..['updated'] = _lastDate
          ..['data'] = {'revision': 2}
          ..['imgs'] = ['latest.jpg'];
      };

      final result = await remote.getSince(version: _timestamp(_cursorDate));

      expect(result.rows, hasLength(1802));
      expect(result.rows.map((row) => row.id).toSet(),
          {for (var id = 1; id <= 1802; id++) _id(id)});
      expect(result.rows.map((row) => row.id), [
        for (var id = 2; id <= 1801; id++) _id(id),
        _id(1),
        _id(1802),
      ]);
      final rewritten = result.rows.singleWhere((row) => row.id == _id(1));
      expect(jsonDecode(rewritten.data), {'revision': 2});
      expect(rewritten.ts, _timestamp(_lastDate));
      expect(result.version, _timestamp(_lastDate));
      expect(remote.fullNamesCache[_id(1)], ['latest.jpg']);
      expect(remote.fullNamesCache[_id(901)], ['photo_901_1.jpg']);
      expect(api.pageRequests, hasLength(4));
      for (final request in api.pageRequests) {
        final query = request.url.queryParameters;
        expect(query['page'], '1');
        expect(query['sort'], 'updated,id');
        expect(query['skipTotal'], 'true');
        expect(query['fields'], 'data,id,updated,imgs');
      }
    });

    test('timestamp ties span full pages without changing the saved cursor',
        () async {
      api.rows.addAll([
        _record(0, _cursorDate),
        for (var id = 1800; id >= 1; id--) _record(id, _firstDate),
        _record(1801, _lastDate, store: 'patients'),
      ]);

      final result = await remote.getSince(version: _timestamp(_cursorDate));

      expect(result.rows.map((row) => row.id),
          [for (var id = 1; id <= 1800; id++) _id(id)]);
      expect(result.version, _timestamp(_firstDate));
      expect(remote.fullNamesCache, hasLength(1800));
      expect(remote.fullNamesCache, isNot(contains(_id(0))));
      expect(remote.fullNamesCache, isNot(contains(_id(1801))));
      expect(api.pageRequests, hasLength(3));
      expect(api.pageRequests[1].url.queryParameters['filter'],
          contains('id>"${_id(900)}"'));
      expect(api.pageRequests[2].url.queryParameters['filter'],
          contains('id>"${_id(1800)}"'));
      expect(api.pageRequests.last.url.queryParameters['page'], '1');
    });

    test('writes beyond the initial window remain visible to the next pull',
        () async {
      api.rows.addAll([
        for (var id = 1; id <= 901; id++) _record(id, _firstDate),
      ]);
      api.beforePageRead = (page) {
        if (page != 2) return;
        for (final index in [0, 900]) {
          api.rows[index]
            ..['updated'] = _lastDate
            ..['data'] = {'revision': 2}
            ..['imgs'] = ['latest.jpg'];
        }
        api.rows.add(_record(902, _lastDate));
      };

      final first = await remote.getSince(version: _timestamp(_cursorDate));

      expect(first.rows.map((row) => row.id),
          [for (var id = 1; id <= 900; id++) _id(id)]);
      expect(first.version, _timestamp(_firstDate));
      expect(first.rows.singleWhere((row) => row.id == _id(1)).ts,
          _timestamp(_firstDate));
      expect(remote.fullNamesCache, isNot(contains(_id(901))));

      final next = await remote.getSince(version: first.version);

      expect(next.rows.map((row) => row.id), [_id(1), _id(901), _id(902)]);
      expect(jsonDecode(next.rows.first.data), {'revision': 2});
      expect(jsonDecode(next.rows[1].data), {'revision': 2});
      expect(next.version, _timestamp(_lastDate));
      expect(remote.fullNamesCache[_id(1)], ['latest.jpg']);
      expect(remote.fullNamesCache[_id(901)], ['latest.jpg']);
      expect(remote.fullNamesCache[_id(902)], ['photo_902_1.jpg']);
    });

    test('an empty pull keeps the strict timestamp boundary and zero result',
        () async {
      api.rows.addAll([
        _record(1, _cursorDate),
        _record(2, _firstDate),
        _record(3, _lastDate, store: 'patients'),
      ]);
      remote.fullNamesCache[_id(1)] = ['cached.jpg'];

      final result = await remote.getSince(version: _timestamp(_firstDate));

      expect(result.rows, isEmpty);
      expect(result.version, 0);
      expect(remote.fullNamesCache, {
        _id(1): ['cached.jpg'],
      });
    });
  });
}
