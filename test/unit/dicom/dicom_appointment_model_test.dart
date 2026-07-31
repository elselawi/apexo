import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appointment model changes for DICOM integration:
///  - `dcmImgs` (slot 18) delta serialization.
///  - `viewableDcmImgs` getter filtering via `isADcmName`.
///  - `pushIfChanged` intentionally excludes `dcmImgs` (adding X-rays must
///    not push to the patient; other devices learn via PocketBase sync).
///  - `isADcmName` utility.
void main() {
  group('Appointment.dcmImgs — delta serialization', () {
    test('round-trips a non-empty list', () {
      final appt = Appointment.fromJson({
        "dcmImgs": ["a.dcm", "b.dcm"]
      });
      expect(appt.dcmImgs, ["a.dcm", "b.dcm"]);
      final json = appt.toJson();
      expect(json["dcmImgs"], ["a.dcm", "b.dcm"]);
    });

    test('default Appointment.toJson() omits dcmImgs (delta serialization)',
        () {
      final json = Appointment.fromJson({}).toJson();
      expect(json.containsKey("dcmImgs"), isFalse,
          reason: 'empty dcmImgs must not be serialized');
    });

    test('fromJson defaults dcmImgs to empty list when missing', () {
      final appt = Appointment.fromJson({});
      expect(appt.dcmImgs, isEmpty);
    });

    test('dcmImgs slot 18 does not collide with existing fields', () {
      final appt = Appointment.fromJson({
        "id": "apt-1",
        "duration": 30,
        "imgs": ["x.jpg"],
        "dcmImgs": ["y.dcm"],
      });
      expect(appt.duration, 30);
      expect(appt.imgs, ["x.jpg"]);
      expect(appt.dcmImgs, ["y.dcm"]);
    });
  });

  group('Appointment.viewableDcmImgs', () {
    test('filters out non-DCM entries', () {
      final appt = Appointment.fromJson({
        "dcmImgs": ["scan.dcm", "photo.jpg", "other.DICOM", "notes.txt"],
      });
      expect(appt.viewableDcmImgs, ["scan.dcm", "other.DICOM"]);
    });

    test('empty when dcmImgs is empty', () {
      expect(Appointment.fromJson({}).viewableDcmImgs, isEmpty);
    });
  });

  group('Appointment.pushIfChanged / jsonCopyForPush', () {
    test('pushIfChanged excludes dcmImgs (adding X-rays must not push)', () {
      expect(
          Appointment.fromJson({}).pushIfChanged, isNot(contains("dcmImgs")));
    });

    test('jsonCopyForPush excludes dcmImgs (not part of push payload)', () {
      final appt = Appointment.fromJson({
        "dcmImgs": ["a.dcm", "b.dcm"]
      });
      final pushCopy = appt.jsonCopyForPush;
      expect(pushCopy.containsKey("dcmImgs"), isFalse);
    });
  });

  group('isADcmName', () {
    test('true for .dcm extension (lowercase)', () {
      expect(isADcmName("scan.dcm"), isTrue);
    });

    test('true for .DCM extension (case-insensitive, RVG software)', () {
      expect(isADcmName("scan.DCM"), isTrue);
    });

    test('true for .dicom extension', () {
      expect(isADcmName("scan.dicom"), isTrue);
    });

    test('true for .DICOM extension (case-insensitive)', () {
      expect(isADcmName("scan.DICOM"), isTrue);
    });

    test('false for image files', () {
      expect(isADcmName("photo.jpg"), isFalse);
      expect(isADcmName("photo.png"), isFalse);
    });

    test('false for non-image files', () {
      expect(isADcmName("notes.txt"), isFalse);
      expect(isADcmName("report.pdf"), isFalse);
    });

    test('false for filenames with no extension', () {
      expect(isADcmName("noextension"), isFalse);
    });

    test('dcm appears as part of filename but not extension', () {
      expect(isADcmName("dcm_file.jpg"), isFalse);
    });
  });
}
