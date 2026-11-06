import 'dart:async';

import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_clinic_service.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'booking_requests_controller_test.dart' show clinic, item;

class DiscoveryService extends BookingClinicService {
  DiscoveryService() : super(api: BookingApi(origin: 'https://book.test',
      client: MockClient((_) async => http.Response(
        '{"items":[],"pending":0}', 200,
        headers: {'content-type': 'application/json'}))));

  Future<bool> schema = Future.value(true);
  Future<BookingClinicRecord?> record = Future.value(clinic());

  @override
  Future<bool> collectionsReady() => schema;

  @override
  Future<BookingClinicRecord?> loadClinic() => record;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logout invalidates discovery before it can publish or restart polling', () async {
    final service = DiscoveryService();
    final pending = Completer<BookingClinicRecord?>();
    service.record = pending.future;
    final session = BookingSession(createService: () => service);
    final discovering = session.initialize();
    await Future<void>.delayed(Duration.zero);
    session.reset();
    pending.complete(clinic());
    await discovering;
    expect(session.ready(), isFalse);
    expect(session.schemaReady(), isFalse);
    expect(session.clinic(), isNull);
    expect(session.requests.isAttached, isFalse);
  });

  test('late discovery cannot overwrite a newer reload', () async {
    final service = DiscoveryService();
    final pending = Completer<BookingClinicRecord?>();
    service.record = pending.future;
    final session = BookingSession(createService: () => service);
    addTearDown(session.reset);
    final discovering = session.initialize();
    await Future<void>.delayed(Duration.zero);
    service.record = Future.value(null);
    await session.reload();
    pending.complete(clinic());
    await discovering;
    expect(session.clinic(), isNull);
    expect(session.requests.isAttached, isFalse);
  });

  test('reloading unchanged credentials retains unconfirmed appointment links', () async {
    final service = DiscoveryService();
    final session = BookingSession(createService: () => service);
    addTearDown(session.reset);
    await session.initialize();
    await session.requests.refresh();
    session.requests.rememberPendingLink(item('request000001'), 'appointment001', confirmed: false);
    final generation = session.requests.generation;
    await session.reload();
    await session.requests.refresh();
    expect(session.requests.generation, generation);
    expect(session.requests.pendingLinks().single.appointmentId, 'appointment001');
  });
}
