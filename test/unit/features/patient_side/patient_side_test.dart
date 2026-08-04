import 'dart:async';

import 'package:apexo/services/patient_side.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Map<String, dynamic> savedPatientSide;

  setUp(() {
    savedPatientSide = patientSide.toJson();
  });

  tearDown(() {
    // Restore fields directly: fromJson can intentionally auto-activate a
    // complete credential set, which is an integration concern.
    patientSide.server = savedPatientSide['server'] as String;
    patientSide.name = savedPatientSide['name'] as String;
    patientSide.patientID = savedPatientSide['patientID'] as String;
    patientSide.relayKey = savedPatientSide['relayKey'] as String;
    patientSide.appointments.clear();
    patientSide.imgLinks.clear();
    patientSide.collectionId = '';
  });

  group('PatientAppointment.fromJson', () {
    test('parses all core fields', () {
      final appt = PatientAppointment.fromJson({
        'id': 'apt-1',
        'price': 250.0,
        'paid': 100.0,
        'date': 28400400, // minutes
        'prescriptions': ['Amox 500mg', 'Ibuprofen'],
        'imgs': ['img1.jpg', 'img2.png'],
        'archived': 1,
        'isDone': 1,
      });

      expect(appt.id, 'apt-1');
      expect(appt.price, 250.0);
      expect(appt.paid, 100.0);
      expect(appt.date.millisecondsSinceEpoch ~/ 60000, 28400400);
      expect(appt.prescriptions, ['Amox 500mg', 'Ibuprofen']);
      expect(appt.imgs, ['img1.jpg', 'img2.png']);
      expect(appt.archived, true);
      expect(appt.isDone, true);
    });

    test('archived and isDone default to false when missing', () {
      final appt = PatientAppointment.fromJson({'id': 'a'});
      expect(appt.archived, false);
      expect(appt.isDone, false);
    });

    test('archived=false when JSON value is 0', () {
      final appt = PatientAppointment.fromJson({'id': 'b', 'archived': 0});
      expect(appt.archived, false);
    });

    test('isDone=false when JSON value is 0', () {
      final appt = PatientAppointment.fromJson({'id': 'c', 'isDone': 0});
      expect(appt.isDone, false);
    });

    test('accepts PocketBase bool and integer flags equivalently', () {
      final boolFlags = PatientAppointment.fromJson({
        'archived': true,
        'isDone': true,
      });
      final integerFlags = PatientAppointment.fromJson({
        'archived': 1,
        'isDone': 1,
      });

      expect(boolFlags.archived, isTrue);
      expect(boolFlags.isDone, isTrue);
      expect(integerFlags.archived, isTrue);
      expect(integerFlags.isDone, isTrue);
    });

    test('date is converted from minutes (×60000)', () {
      final appt = PatientAppointment.fromJson({'date': 1000});
      expect(appt.date.millisecondsSinceEpoch, 1000 * 60000);
    });

    test('date uses default DateTime.now() when missing', () {
      final appt = PatientAppointment.fromJson({});
      expect(appt.date, isA<DateTime>());
      // Should be very close to now
      final diff = DateTime.now().difference(appt.date).inSeconds.abs();
      expect(diff, lessThan(60));
    });

    test('prescriptions defaults to empty list when missing', () {
      final appt = PatientAppointment.fromJson({});
      expect(appt.prescriptions, isEmpty);
    });

    test('imgs defaults to empty list when missing', () {
      final appt = PatientAppointment.fromJson({});
      expect(appt.imgs, isEmpty);
    });

    test('id defaults to empty string when missing', () {
      final appt = PatientAppointment.fromJson({});
      expect(appt.id, isEmpty);
    });

    test('price defaults to 0 when missing', () {
      final appt = PatientAppointment.fromJson({});
      expect(appt.price, 0);
    });

    test('paid defaults to 0 when missing', () {
      final appt = PatientAppointment.fromJson({});
      expect(appt.paid, 0);
    });

    test('price parsed as string is also accepted', () {
      final appt = PatientAppointment.fromJson({'price': '123.45'});
      expect(appt.price, 123.45);
    });

    test('paid parsed as int is converted to double', () {
      final appt = PatientAppointment.fromJson({'paid': 75});
      expect(appt.paid, 75.0);
    });

    test('malformed money and collection payloads are rejected', () {
      expect(
        () => PatientAppointment.fromJson({'price': 'invalid'}),
        throwsFormatException,
      );
      expect(
        () => PatientAppointment.fromJson({'imgs': 'not-a-list'}),
        throwsA(anything),
      );
    });
  });

  group('PatientSide — singleton', () {
    test('patientSide singleton exists', () {
      expect(patientSide, isNotNull);
    });

    test('getImgLink builds the correct PB file URL', () {
      patientSide.server = 'https://clinic.example';
      patientSide.collectionId = 'public';
      final link = patientSide.getImgLink('row-id-42', 'tooth.jpg');
      expect(
          link, 'https://clinic.example/api/files/public/row-id-42/tooth.jpg');
    });

    test('getThumbFromImgLink appends thumb=100x100 query', () {
      const base = 'https://example.com/api/files/foo/bar/img.jpg';
      final thumb = patientSide.getThumbFromImgLink(base);
      expect(thumb, '$base?thumb=100x100');
    });

    test('getThumbFromImgLink preserves an existing query string', () {
      const base = 'https://example.com/image.jpg?token=abc';
      expect(patientSide.getThumbFromImgLink(base),
          'https://example.com/image.jpg?token=abc&thumb=100x100');
    });
  });

  group('PatientSide — serialization', () {
    test('toJson includes all credential fields', () {
      patientSide.server = 'srv';
      patientSide.name = 'nm';
      patientSide.patientID = 'pid';
      patientSide.relayKey = 'rk';

      final json = patientSide.toJson();
      expect(json['server'], 'srv');
      expect(json['name'], 'nm');
      expect(json['patientID'], 'pid');
      expect(json['relayKey'], 'rk');
    });

    test('fromJson restores all credential fields with empty defaults', () {
      patientSide.fromJson({});
      expect(patientSide.server, isEmpty);
      expect(patientSide.name, isEmpty);
      expect(patientSide.patientID, isEmpty);
      expect(patientSide.relayKey, isEmpty);
    });

    test('partial persisted credentials do not trigger network activation', () {
      patientSide.fromJson({
        'server': 'srv2',
        'name': 'nm2',
        'patientID': 'pid2',
        // relayKey omitted → activation guard remains false.
      });

      expect(patientSide.server, 'srv2');
      expect(patientSide.name, 'nm2');
      expect(patientSide.patientID, 'pid2');
      expect(patientSide.relayKey, isEmpty);
    });
  });

  group('PatientSide — logoutPatientSide', () {
    test('clears all credential fields', () {
      patientSide.server = 'srv';
      patientSide.name = 'nm';
      patientSide.patientID = 'pid';
      patientSide.relayKey = 'rk';

      patientSide.logoutPatientSide();

      expect(patientSide.server, isEmpty);
      expect(patientSide.name, isEmpty);
      expect(patientSide.patientID, isEmpty);
      expect(patientSide.relayKey, isEmpty);
    });
  });

  group('PatientSide.activate with injected boundaries', () {
    test('missing credentials fail without making HTTP requests', () async {
      var requests = 0;
      final side = PatientSide(
        server: '',
        name: 'Patient',
        patientID: 'patient-id',
        relayKey: 'relay',
        httpGet: (_) async {
          requests++;
          return http.Response('{}', 200);
        },
      );

      await side.activate();

      expect(requests, 0);
      expect(loginCtrl.loginError(), 'Patient Side URL, Name or ID is empty');
      expect(loginCtrl.loadingPatientSide(), isFalse);
    });

    test('successful activation parses API data and does not duplicate links',
        () async {
      var request = 0;
      var identifyCalls = 0;
      final side = PatientSide(
        server: 'https://clinic.example',
        name: 'Patient',
        patientID: 'patient-id',
        relayKey: 'relay',
        httpGet: (_) async {
          request++;
          if (request.isOdd) {
            return http.Response('''{"items":[
              {"id":"currency_______","data":{"value":"EUR"}},
              {"id":"phone__________","data":{"value":"123"}},
              {"id":"country_______","data":{"value":"DE"}},
              {"id":"prescription_header","data":{"value":"Clinic"}}
            ]}''', 200);
          }
          return http.Response('''{"items":[{
            "id":"appointment-1","collectionId":"public",
            "price":100,"paid":25,"date":28400400,
            "imgs":["image.jpg"],"archived":false,"isDone":true
          }]}''', 200);
        },
        identifyDevice: () async => identifyCalls++,
      );

      await side.activate();
      await side.activate();

      expect(side.currency, 'EUR');
      expect(side.phone, '123');
      expect(side.countryCode, 'DE');
      expect(side.clinicNameAndAddress, 'Clinic');
      expect(side.collectionId, 'public');
      expect(side.appointments, hasLength(1));
      expect(side.imgLinks, [
        'https://clinic.example/api/files/public/appointment-1/image.jpg',
      ]);
      expect(identifyCalls, 2);
      expect(loginCtrl.loadingPatientSide(), isFalse);
    });

    test('HTTP or payload failure clears loading and exposes error', () async {
      final side = PatientSide(
        server: 'https://clinic.example',
        name: 'Patient',
        patientID: 'patient-id',
        relayKey: 'relay',
        httpGet: (_) async => throw Exception('network down'),
      );

      await expectLater(side.activate(), throwsA(isA<Exception>()));
      expect(loginCtrl.loadingPatientSide(), isFalse);
      expect(loginCtrl.loginError(), contains('network down'));
    });

    test('logout invalidates an in-flight activation', () async {
      final response = Completer<http.Response>();
      final side = PatientSide(
        server: 'https://clinic.example',
        name: 'Patient',
        patientID: 'patient-id',
        relayKey: 'relay',
        httpGet: (_) => response.future,
      );

      final activation = side.activate();
      side.logoutPatientSide();
      response.complete(http.Response('{"items":[]}', 200));
      await activation;

      expect(side.patientID, isEmpty);
      expect(side.server, isEmpty);
    });
  });
}
