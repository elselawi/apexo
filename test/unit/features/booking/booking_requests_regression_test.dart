import 'dart:async';
import 'dart:convert';

import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_requests_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'booking_requests_controller_test.dart' show clinic, item, page;

http.Response response(Object value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

void main() {
  BookingRequestsController controller(
      Future<http.Response> Function(http.Request) handler) {
    final api =
        BookingApi(origin: 'https://book.test', client: MockClient(handler));
    final result = BookingRequestsController();
    result.attach(api: api, clinic: clinic(), accountId: 'account');
    addTearDown(() {
      result.detach();
      api.dispose();
    });
    return result;
  }

  test('scheduling is exclusive per request and isolated across logins', () {
    final inbox = controller((_) async => response(page([])));
    final generation = inbox.generation;
    expect(inbox.beginScheduling('request000001'), isTrue);
    expect(inbox.beginScheduling('request000001'), isFalse);
    inbox.detach();
    final api = BookingApi(origin: 'https://book.test');
    addTearDown(api.dispose);
    inbox.attach(api: api, clinic: clinic(), accountId: 'other');
    expect(inbox.beginScheduling('request000001'), isTrue);
    inbox.finishScheduling('request000001', generation);
    expect(inbox.beginScheduling('request000001'), isFalse);
  });

  test('a refresh caller awaits the shared in-flight snapshot', () async {
    final blocked = Completer<http.Response>();
    final started = Completer<void>();
    final inbox = controller((_) {
      started.complete();
      return blocked.future;
    });
    final first = inbox.refresh();
    await started.future;
    var completed = false;
    final second = inbox.refresh().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    blocked.complete(response(page([item('request000001')])));
    await Future.wait([first, second]);
    expect(inbox.items(), hasLength(1));
  });

  test('switching filters during a refresh fetches the newly selected filter',
      () async {
    final blocked = Completer<http.Response>();
    final started = Completer<void>();
    final statuses = <String>[];
    final inbox = controller((request) async {
      final status = (jsonDecode(request.body) as Map)['status'] as String;
      statuses.add(status);
      if (status == 'pending' && !started.isCompleted) {
        started.complete();
        return blocked.future;
      }
      return response(page([item('request000002', status: status)]));
    });
    final first = inbox.refresh();
    await started.future;
    inbox.switchFilter('handled');
    blocked.complete(response(page([item('request000001')])));
    await first;
    await inbox.refresh();
    expect(statuses, ['pending', 'handled', 'pending']);
    expect(inbox.items().single.status, 'handled');
  });

  test('polling a terminal filter also refreshes the dashboard pending cache',
      () async {
    final statuses = <String>[];
    final inbox = controller((request) async {
      final status = (jsonDecode(request.body) as Map)['status'] as String;
      statuses.add(status);
      return response(page([item('request-$status', status: status)]));
    });
    inbox.filter('handled');
    await inbox.refresh();
    expect(statuses, ['handled', 'pending']);
    expect(inbox.items().single.status, 'handled');
    expect(inbox.cache.forFilter('pending').single.status, 'pending');
  });

  test('a previous login refresh cannot block or overwrite a new session',
      () async {
    final blocked = Completer<http.Response>();
    final started = Completer<void>();
    var calls = 0;
    final api = BookingApi(
        origin: 'https://book.test',
        client: MockClient((_) async {
          if (++calls == 1) {
            started.complete();
            return blocked.future;
          }
          return response(page([item('newrequest001')]));
        }));
    final inbox = BookingRequestsController();
    addTearDown(() {
      inbox.detach();
      api.dispose();
    });
    inbox.attach(api: api, clinic: clinic(), accountId: 'old');
    final old = inbox.refresh();
    await started.future;
    inbox.attach(api: api, clinic: clinic(), accountId: 'new');
    expect(inbox.lastSuccessfulAt(), isNull);
    await inbox.refresh();
    blocked.complete(response(page([item('oldrequest001')])));
    await old;
    expect(inbox.items().single.requestId, 'newrequest001');
  });

  test('replayed links are reconciled before publishing the pending snapshot',
      () async {
    var handled = false;
    final inbox = controller((request) async {
      if (request.url.path.endsWith('/state')) {
        handled = true;
        return response({'version': 2});
      }
      return response(page(handled ? [] : [item('request000001')]));
    });
    inbox.rememberPendingLink(item('request000001'), 'appointment001');
    await inbox.refresh();
    expect(inbox.pendingLinks(), isEmpty);
    expect(inbox.items(), isEmpty);
    expect(inbox.pending(), 0);
  });

  test('unconfirmed appointments are never automatically acknowledged',
      () async {
    final inbox = controller((request) async {
      expect(request.url.path.endsWith('/state'), isFalse);
      return response(page([item('request000001')]));
    });
    inbox.rememberPendingLink(item('request000001'), 'appointment001',
        confirmed: false);
    await inbox.refresh();
    expect(inbox.pendingLinks(), hasLength(1));
    expect(inbox.items(), hasLength(1));
  });

  test(
      'transitions update the badge and populate already-cached terminal filters',
      () async {
    final inbox = controller((request) async {
      if (request.url.path.endsWith('/state')) return response({'version': 2});
      final status = (jsonDecode(request.body) as Map)['status'];
      return response(page(status == 'pending' ? [item('request000001')] : []));
    });
    await inbox.refresh(status: 'handled');
    await inbox.refresh();
    final pending = inbox.items().single;
    await inbox.markHandled(pending, 'appointment001');
    await inbox.markHandled(pending, 'appointment001');
    expect(inbox.pending(), 0);
    expect(inbox.items(), isEmpty);
    expect(inbox.cache.forFilter('handled').single.linkedId, 'appointment001');
  });

  test('a late pull cannot resurrect a request handled while it was in flight',
      () async {
    final blocked = Completer<http.Response>();
    final started = Completer<void>();
    var pulls = 0;
    final inbox = controller((request) async {
      if (request.url.path.endsWith('/state')) return response({'version': 2});
      if (++pulls == 2) {
        started.complete();
        return blocked.future;
      }
      return response(page(pulls > 2 ? [] : [item('request000001')]));
    });
    await inbox.refresh();
    final pending = inbox.items().single;
    final refreshing = inbox.refresh();
    await started.future;
    await inbox.markHandled(pending, 'appointment001');
    blocked.complete(response(page([pending])));
    await refreshing;
    expect(inbox.items(), isEmpty);
    expect(inbox.pending(), 0);
    expect(pulls, 3);
  });

  test('non-advancing pagination never replaces a complete cached snapshot',
      () async {
    var broken = false;
    final inbox = controller((_) async => response(broken
        ? page([item('partial000001', seq: 2)],
            nextBeforeSeq: 2, snapshot: 'token')
        : page([item('complete00001')])));
    await inbox.refresh();
    broken = true;
    await inbox.refresh();
    expect(inbox.connected(), isFalse);
    expect(inbox.items().single.requestId, 'complete00001');
  });
}
