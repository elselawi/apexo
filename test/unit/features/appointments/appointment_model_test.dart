import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Appointment.fromJson', () {
    test('parses all core fields', () {
      final appt = Appointment.fromJson({
        'id': 'abc123',
        'patientID': 'pat1',
        'operatorsIDs': ['op1', 'op2'],
        'date': 28400400, // minutes
        'duration': 30,
        'price': 150.0,
        'paid': 100.0,
        'isDone': true,
        'preOpNotes': 'Sensitive tooth',
        'postOpNotes': 'Done',
        'prescriptions': ['Amox'],
        'teeth': {'11': 'filling'},
        'teethExtraNotes': {'11': 'Deep'},
        'hasLabwork': true,
        'labName': 'Lab1',
        'labworkNotes': 'Crown',
        'labworkReceived': false,
        'imgs': ['img1.jpg', 'img2.png'],
        'dcmImgs': ['scan.dcm'],
        'drawings': {'11': 'outline'},
      });

      expect(appt.id, 'abc123');
      expect(appt.patientID, 'pat1');
      expect(appt.operatorsIDs, ['op1', 'op2']);
      expect(appt.duration, 30);
      expect(appt.price, 150.0);
      expect(appt.paid, 100.0);
      expect(appt.isDone, true);
      expect(appt.preOpNotes, 'Sensitive tooth');
      expect(appt.postOpNotes, 'Done');
      expect(appt.prescriptions, ['Amox']);
      expect(appt.teeth, {'11': 'filling'});
      expect(appt.hasLabwork, true);
      expect(appt.labName, 'Lab1');
      expect(appt.labworkNotes, 'Crown');
      expect(appt.labworkReceived, false);
      expect(appt.imgs, ['img1.jpg', 'img2.png']);
      expect(appt.dcmImgs, ['scan.dcm']);
      expect(appt.drawings, {'11': 'outline'});
    });

    test('handles missing optional fields with defaults', () {
      final appt = Appointment.fromJson({'id': 'min'});
      expect(appt.operatorsIDs, isEmpty);
      expect(appt.patientID, isNull);
      expect(appt.price, 0.0);
      expect(appt.paid, 0.0);
      expect(appt.isDone, false);
      expect(appt.hasLabwork, false);
      expect(appt.imgs, isEmpty);
      expect(appt.dcmImgs, isEmpty);
      expect(appt.duration, 15);
    });

    test('date is in minutes (millisecondsSinceEpoch / 60000)', () {
      final now = DateTime.now();
      final minutes = now.millisecondsSinceEpoch ~/ 60000;
      final appt = Appointment.fromJson({'id': 'd', 'date': minutes});
      expect(appt.date.millisecondsSinceEpoch ~/ 60000, minutes);
    });

    test('booleans parsed from JSON', () {
      final a = Appointment.fromJson({
        'id': 'a',
        'isDone': true,
        'hasLabwork': true,
        'labworkReceived': false,
      });
      expect(a.isDone, true);
      expect(a.hasLabwork, true);
      expect(a.labworkReceived, false);
    });

    test('numeric strings are parsed for money fields', () {
      final appointment = Appointment.fromJson({
        'price': '125.50',
        'paid': '25.25',
      });

      expect(appointment.price, 125.50);
      expect(appointment.paid, 25.25);
    });

    test('malformed numeric values throw instead of silently defaulting', () {
      expect(
        () => Appointment.fromJson({'price': 'invalid'}),
        throwsFormatException,
      );
      expect(
        () => Appointment.fromJson({'paid': 'invalid'}),
        throwsFormatException,
      );
    });

    test('empty collections are omitted while required date remains present',
        () {
      final json = Appointment.fromJson({'id': 'defaults'}).toJson();

      expect(json.containsKey('operatorsIDs'), isFalse);
      expect(json.containsKey('prescriptions'), isFalse);
      expect(json.containsKey('imgs'), isFalse);
      expect(json.containsKey('dcmImgs'), isFalse);
      expect(json['date'], isA<int>());
    });
  });

  group('Appointment.toJson', () {
    test('round-trip preserves all fields', () {
      final appt = testAppointment(
        id: 'rt1',
        patientID: 'pat1',
        operatorsIDs: ['op1'],
        price: 200,
        paid: 150,
        isDone: true,
        hasLabwork: true,
        labName: 'Lab',
      );
      final json = appt.toJson();
      expect(json['id'], 'rt1');
      expect(json['price'], 200);
      expect(json['paid'], 150);
      expect(json['isDone'], true);
    });

    test('excludes computed "title" key', () {
      final json = testAppointment(id: 't1').toJson();
      expect(json.containsKey('title'), false);
    });

    test('date serialized as minutes', () {
      final appt =
          testAppointment(id: 'dt', date: DateTime(2026, 1, 15, 10, 30));
      final json = appt.toJson();
      expect(json['date'], isA<int>());
    });
  });

  group('Appointment.jsonCopyForPush', () {
    test('only includes date, isDone, archived, operatorsIDs', () {
      final appt = testAppointment(id: 'push1', isDone: true);
      final copy = appt.jsonCopyForPush;
      expect(copy.keys, containsAll(['date', 'isDone']));
      expect(copy.containsKey('price'), false);
      expect(copy.containsKey('paid'), false);
    });

    test('push metadata is exact and excludes DICOM changes', () {
      final copy = testAppointment(
        id: 'push-exact',
        dcmImgs: ['scan.dcm'],
      ).jsonCopyForPush;

      expect(copy.keys.toSet(), {'date', 'isDone', 'archived', 'operatorsIDs'});
      expect(copy.containsKey('dcmImgs'), isFalse);
    });
  });

  group('Appointment.push fields', () {
    test('targetsToPushTo includes patientID and operatorsIDs', () {
      final appt = testAppointment(
        id: 'tp1',
        patientID: 'pat1',
        operatorsIDs: ['op1', 'op2'],
      );
      final targets = appt.targetsToPushTo;
      expect(targets.contains('pat1'), true);
      expect(targets.contains('op1'), true);
      expect(targets.contains('op2'), true);
    });

    test('pushIfChanged returns correct keys', () {
      final appt = testAppointment(id: 'pc1');
      expect(appt.pushIfChanged, isNotEmpty);
    });

    test('pushOnCreation returns true', () {
      expect(testAppointment(id: 'po1').pushOnCreation, true);
    });
  });

  group('Appointment computed getters', () {
    test('viewableImgs filters out DCM files', () {
      final appt = testAppointment(
        id: 'vimgs',
        imgs: ['photo.jpg', 'xray.dcm', 'scan.dcm.png', 'chart.png'],
      );
      final v = appt.viewableImgs;
      expect(v, contains('photo.jpg'));
      expect(v, contains('chart.png'));
      expect(v, isNot(contains('xray.dcm')));
    });

    test('viewableDcmImgs filters to only DCM files', () {
      final appt = testAppointment(
        id: 'vdcm',
        dcmImgs: ['photo.jpg', 'xray.dcm', 'scan.dicom'],
      );
      final v = appt.viewableDcmImgs;
      expect(v.length, 2);
      expect(v, contains('xray.dcm'));
      expect(v, contains('scan.dicom'));
    });

    test('endDate = date + duration in minutes', () {
      final appt = testAppointment(
        id: 'ed1',
        date: DateTime(2026, 1, 15, 10, 0),
        duration: 45,
      );
      expect(appt.endDate, DateTime(2026, 1, 15, 10, 45));
    });

    test('fullPaid when paid == price', () {
      expect(testAppointment(id: 'fp1', price: 100, paid: 100).fullPaid, true);
      expect(testAppointment(id: 'fp2', price: 100, paid: 50).fullPaid, false);
      expect(testAppointment(id: 'fp3', price: 0, paid: 0).fullPaid, true);
    });

    test('overPaid when paid > price', () {
      expect(testAppointment(id: 'op1', price: 100, paid: 150).overPaid, true);
      expect(testAppointment(id: 'op2', price: 100, paid: 100).overPaid, false);
    });

    test('underPaid when paid < price', () {
      expect(testAppointment(id: 'up1', price: 100, paid: 50).underPaid, true);
    });

    test('paymentDifference is abs(paid - price)', () {
      final a = testAppointment(id: 'pd1', price: 100, paid: 150);
      expect(a.paymentDifference, 50.0);
      expect(testAppointment(id: 'pd2', price: 100, paid: 25).paymentDifference,
          75.0);
    });

    test('isMissed: past, >1 day ago, not done', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final missed = testAppointment(id: 'mis1', date: past, isDone: false);
      expect(missed.isMissed, true);
    });

    test('isMissed false for today', () {
      final today =
          testAppointment(id: 'mis2', date: DateTime.now(), isDone: false);
      expect(today.isMissed, false);
    });

    test('isMissed false when done', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final done = testAppointment(id: 'mis3', date: past, isDone: true);
      expect(done.isMissed, false);
    });

    test('locking distinguishes full, none, and personal permissions', () {
      final original = login.savedPermissions;
      try {
        login.savedPermissions = Perm.full;
        expect(testAppointment(id: 'lock-full').locked, isFalse);

        login.savedPermissions = Perm.zeroes;
        expect(testAppointment(id: 'lock-none').locked, isTrue);

        final personal = Perm.zeroes;
        personal[Perm.appointments] = 1;
        login.savedPermissions = personal;
        expect(
          testAppointment(id: 'lock-personal-other', operatorsIDs: ['other'])
              .locked,
          isTrue,
        );
        expect(
          testAppointment(id: 'lock-personal-self', operatorsIDs: ['']).locked,
          isFalse,
        );
      } finally {
        login.savedPermissions = original;
      }
    });

    test('labworkStatus returns "none" when no labwork', () {
      expect(
          testAppointment(id: 'ls1', hasLabwork: false).labworkStatus, 'none');
    });

    test('copy(blank: true) creates independent clone', () {
      final orig = testAppointment(id: 'cpy1', price: 100, isDone: false);
      final clone = orig.copy(true);
      expect(clone.id, isNot('cpy1'));
    });

    test('copy preserves all fields', () {
      final orig =
          testAppointment(id: 'cpy2', price: 200, paid: 100, duration: 30);
      final clone = orig.copy(false);
      expect(clone.id, 'cpy2');
      expect(clone.price, 200);
      expect(clone.paid, 100);
      expect(clone.duration, 30);
    });

    test('copy deep-copies mutable collections', () {
      final original = testAppointment(
        id: 'deep-copy',
        operatorsIDs: ['op1'],
        prescriptions: ['drug'],
        teeth: {'11': 'filling'},
        imgs: ['photo.png'],
      );
      final clone = original.copy(false);
      clone.operatorsIDs.add('op2');
      clone.prescriptions.add('second-drug');
      clone.teeth['12'] = 'crown';
      clone.imgs.add('second.png');

      expect(original.operatorsIDs, ['op1']);
      expect(original.prescriptions, ['drug']);
      expect(original.teeth, {'11': 'filling'});
      expect(original.imgs, ['photo.png']);
    });
  });
}
