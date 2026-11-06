import 'dart:convert';

import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_clinic_service.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

class MemoryClinic {
  final records = <String, Map<String, Map<String, dynamic>>>{};
  bool failFinalAdminSave = false;
  bool leaveProof = false;
  int proofCreates = 0;

  Map<String, Map<String, dynamic>> collection(String name) =>
      records.putIfAbsent(name, () => {});

  late final client = MockClient((request) async {
    final parts = request.url.pathSegments;
    final name = parts[2];
    final rows = collection(name);
    final id = parts.length > 4 ? parts[4] : null;
    http.Response response(Object body, [int status = 200]) => http.Response(
        jsonEncode(body), status, headers: {'content-type': 'application/json'});
    if (request.method == 'GET') {
      if (id != null) return response(rows[id] ?? {}, rows.containsKey(id) ? 200 : 404);
      return response({'page': 1, 'perPage': 500, 'totalItems': rows.length,
        'totalPages': 1, 'items': rows.values.toList()});
    }
    if (request.method == 'DELETE') {
      if (leaveProof && name == bookingVerificationCollectionName) return response({}, 503);
      rows.remove(id);
      return response({});
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (name == bookingAdminCollectionName && body['pending_operation'] == null && failFinalAdminSave) {
      return response({}, 503);
    }
    if (request.method == 'PATCH' && !rows.containsKey(id)) return response({}, 404);
    if (request.method == 'POST' && name == bookingVerificationCollectionName) {
      if (rows.values.any((row) => row['challenge'] == body['challenge'])) return response({}, 400);
      proofCreates++;
    }
    final key = id ?? body['id'] as String? ?? 'proof0000000001';
    rows[key] = {'id': key, ...?rows[key], ...body};
    return response(rows[key]!);
  });
}

class MemoryWorker extends BookingApi {
  MemoryWorker() : super(origin: 'https://book.test');
  String adminKey = 'A' * 43;
  String inboxKey = 'B' * 43;
  int revision = 1;
  bool handleTaken = false;
  bool loseRegistrationResponse = false;
  final registrations = <Map<String, Object?>>[];
  final rotationKeys = <String>[];

  @override
  Future<BookingRegistrationResult> register(Map<String, Object?> body) async {
    registrations.add(body);
    if (handleTaken) throw BookingApiException(code: 'handle_taken', statusCode: 409);
    adminKey = body['adminKey']! as String;
    inboxKey = body['inboxKey']! as String;
    if (loseRegistrationResponse) throw BookingApiException(code: 'timeout', network: true);
    return BookingRegistrationResult(clinicId: body['clinicId']! as String,
        publicUrl: 'https://book.test/${body['handle']}', keyRevision: revision);
  }

  @override
  Future<BookingRegistrationResult> recover(Map<String, Object?> body) async {
    adminKey = body['adminKey']! as String;
    inboxKey = body['inboxKey']! as String;
    return BookingRegistrationResult(clinicId: body['clinicId']! as String,
        publicUrl: 'https://book.test/jimclinic', keyRevision: 7);
  }

  @override
  Future<int> rotate(String key, {required int expectedKeyRevision,
      required String newAdminKey, required String newInboxKey}) async {
    rotationKeys.add(key);
    if (key != adminKey) throw BookingApiException(code: 'unauthorized', statusCode: 401);
    if (newAdminKey == adminKey && newInboxKey == inboxKey) return revision;
    expect(expectedKeyRevision, revision);
    adminKey = newAdminKey;
    inboxKey = newInboxKey;
    return ++revision;
  }
}

void main() {
  late MemoryClinic backend;
  late MemoryWorker worker;
  late BookingClinicService service;
  late PocketBase? originalPb;
  late String originalToken, originalAdminId, originalUrl;

  setUp(() {
    originalPb = login.pb;
    originalToken = login.token;
    originalAdminId = login.adminCollectionId;
    originalUrl = login.url;
    backend = MemoryClinic();
    login.pb = PocketBase('https://pb.hospital-clinic.dev', httpClientFactory: () => backend.client);
    login.url = 'https://pb.hospital-clinic.dev';
    login.adminCollectionId = 'test-superuser';
    login.token = 'x.${base64Url.encode(utf8.encode('test-superuser'))}.x';
    worker = MemoryWorker();
    service = BookingClinicService(api: worker);
  });

  tearDown(() {
    service.dispose();
    backend.client.close();
    login.pb = originalPb;
    login.token = originalToken;
    login.adminCollectionId = originalAdminId;
    login.url = originalUrl;
  });

  void seedEnrollment() {
    backend.collection(bookingClinicCollectionName)[bookingClinicRecordId] = {
      'id': bookingClinicRecordId, 'handle': 'jimclinic',
      'clinic_id': '0123456789abcdef0123456789abcdef',
      'public_url': 'https://book.test/jimclinic', 'inbox_key': worker.inboxKey,
      'key_revision': 1,
    };
    backend.collection(bookingAdminCollectionName)[bookingAdminRecordId] = {
      'id': bookingAdminRecordId, 'clinic_id': '0123456789abcdef0123456789abcdef',
      'admin_key': worker.adminKey,
    };
  }

  BookingClinicConfig config() => BookingClinicConfig(
      profile: BookingProfile(name: 'Jim Clinic', phone: '+966551234567'),
      timeZone: 'UTC', dialCode: '+966', hours: BookingWeeklyHours.empty(), closedDates: []);

  test('first rotation falls back from candidate to the active admin key', () async {
    seedEnrollment();
    final clinic = await service.rotate();
    expect(worker.rotationKeys, [worker.adminKey, 'A' * 43]);
    expect(clinic.keyRevision, 2);
    expect((await service.loadAdmin())!.adminKey, worker.adminKey);
    expect((await service.loadClinic())!.inboxKey, worker.inboxKey);
  });

  test('rotation resumes after publishing the new staff credential', () async {
    seedEnrollment();
    backend.failFinalAdminSave = true;
    await expectLater(service.rotate(), throwsA(isA<ClientException>()));
    expect((await service.loadClinic())!.keyRevision, 2);
    backend.failFinalAdminSave = false;
    final clinic = await service.rotate();
    expect(clinic.keyRevision, 2);
    expect(worker.revision, 2);
    expect((await service.loadAdmin())!.pendingOperation, isNull);
  });

  test('a rejected handle can be replaced without replaying the rejected attempt', () async {
    worker.handleTaken = true;
    await expectLater(service.register(handle: 'takenclinic', config: config()),
        throwsA(isA<BookingApiException>()));
    worker.handleTaken = false;
    final enrollment = await service.register(handle: 'freeclinic', config: config());
    expect(worker.registrations.map((body) => body['handle']), ['takenclinic', 'freeclinic']);
    expect(enrollment.clinic.handle, 'freeclinic');
  });

  test('an uncertain registration keeps its original identity and renews a leftover proof', () async {
    backend.leaveProof = true;
    worker.loseRegistrationResponse = true;
    await expectLater(service.register(handle: 'jimclinic', config: config()),
        throwsA(isA<BookingApiException>()));
    backend.leaveProof = false;
    worker.loseRegistrationResponse = false;
    final enrollment = await service.register(handle: 'changedclinic', config: config());
    expect(worker.registrations[0], worker.registrations[1]);
    expect(enrollment.clinic.handle, 'jimclinic');
    expect(backend.proofCreates, 2);
  });

  test('recovery works with a missing admin record and uses the Worker revision', () async {
    seedEnrollment();
    backend.collection(bookingAdminCollectionName).clear();
    final enrollment = await service.recover();
    expect(enrollment.clinic.keyRevision, 7);
    expect((await service.loadAdmin())!.adminKey, worker.adminKey);
  });

  test('a service from an old login cannot write into a replacement clinic', () async {
    seedEnrollment();
    login.pb = PocketBase('https://other.clinic.example');
    await expectLater(service.rotate(), throwsStateError);
    expect(worker.rotationKeys, isEmpty);
  });
}
