import 'dart:convert';

import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_requests_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

BookingRequest item(String id, {String status = "pending", int seq = 1}) =>
    BookingRequest(
      seq: seq,
      requestId: id,
      reference: "1106-01",
      name: "Jane Doe",
      phone: "+966551234567",
      preference: BookingPreference(
          kind: "exact", date: "2026-11-09", from: "16:00", to: "21:00"),
      candidateDates: const ["2026-11-09"],
      configRevision: 1,
      fromDate: "2026-11-09",
      toDate: "2026-11-09",
      windowFrom: "16:00",
      windowTo: "21:00",
      timeZone: "Asia/Riyadh",
      language: "en",
      createdAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      version: 1,
      status: status,
    );

Map<String, Object?> page(
  List<BookingRequest> items, {
  int? nextBeforeSeq,
  String? snapshot,
  int? pending,
}) =>
    {
      "items": items.map((entry) => entry.toJson()).toList(),
      "nextBeforeSeq": nextBeforeSeq,
      "snapshot": snapshot,
      "pending": pending ?? items.where((entry) => entry.isPending).length,
    };

BookingClinicRecord clinic() => BookingClinicRecord(
      handle: "jimclinic",
      clinicId: "0123456789abcdef0123456789abcdef",
      publicUrl: "https://book.test/jimclinic",
      inboxKey: "B" * 43,
      keyRevision: 1,
    );

void main() {
  test("replaces a filter only after every page arrives", () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      seen.add("${body["beforeSeq"]}");
      if (body["beforeSeq"] == null) {
        return http.Response(
          jsonEncode(page([item("req00000000002", seq: 2)], nextBeforeSeq: 2, snapshot: "token")),
          200,
          headers: {"content-type": "application/json"},
        );
      }
      return http.Response(
        jsonEncode(page([item("req00000000001", seq: 1)], pending: 2)),
        200,
        headers: {"content-type": "application/json"},
      );
    });
    final api = BookingApi(origin: "https://book.test", client: client);
    final controller = BookingRequestsController();
    controller.attach(api: api, clinic: clinic(), accountId: "account");
    await controller.refresh();

    expect(seen, ["null", "2"]);
    expect(controller.items().map((entry) => entry.requestId),
        ["req00000000002", "req00000000001"]);
    expect(controller.pending(), 2);
    expect(controller.connected(), isTrue);
    expect(controller.cache.forFilter("pending"), hasLength(2));
    controller.detach();
  });

  test("keeps the previous snapshot when a refresh fails", () async {
    var fail = false;
    final client = MockClient((request) async {
      if (fail) throw http.ClientException("offline");
      return http.Response(
        jsonEncode(page([item("req00000000001")])),
        200,
        headers: {"content-type": "application/json"},
      );
    });
    final api = BookingApi(origin: "https://book.test", client: client);
    final controller = BookingRequestsController();
    controller.attach(api: api, clinic: clinic(), accountId: "account");
    await controller.refresh();
    expect(controller.items(), hasLength(1));

    fail = true;
    await controller.refresh();
    expect(controller.items(), hasLength(1));
    expect(controller.connected(), isFalse);
    controller.detach();
  });

  test("stops polling and warns when the key is revoked", () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            "ok": false,
            "error": {"code": "unauthorized"}
          }),
          401,
          headers: {"content-type": "application/json"},
        ));
    final api = BookingApi(origin: "https://book.test", client: client);
    final controller = BookingRequestsController();
    controller.attach(api: api, clinic: clinic(), accountId: "account");
    await controller.refresh();
    expect(controller.revoked(), isTrue);
    expect(controller.connected(), isFalse);
    controller.detach();
  });

  test("applies a handled transition to the cached pending list", () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith("/state")) {
        return http.Response(
          jsonEncode({"ok": true, "version": 2}),
          200,
          headers: {"content-type": "application/json"},
        );
      }
      return http.Response(
        jsonEncode(page([item("req00000000001")])),
        200,
        headers: {"content-type": "application/json"},
      );
    });
    final api = BookingApi(origin: "https://book.test", client: client);
    final controller = BookingRequestsController();
    controller.attach(api: api, clinic: clinic(), accountId: "account");
    await controller.refresh();
    final request = controller.items().single;
    final version = await controller.markHandled(request, "appointment001");
    expect(version, 2);
    expect(controller.items(), isEmpty);
    controller.detach();
  });

  test("remembers a pending link for retry", () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode(page([])),
          200,
          headers: {"content-type": "application/json"},
        ));
    final api = BookingApi(origin: "https://book.test", client: client);
    final controller = BookingRequestsController();
    controller.attach(api: api, clinic: clinic(), accountId: "account");
    controller.rememberPendingLink(item("req00000000001"), "appointment001");
    expect(controller.pendingLinks(), hasLength(1));
    controller.detach();
    expect(controller.pendingLinks(), isEmpty);
  });
}

