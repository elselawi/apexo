import 'package:apexo/services/dicom/dicom_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isDcmFileName', () {
    test('recognizes the .dcm extension', () {
      expect(isDcmFileName('scan.dcm'), isTrue);
    });

    test('recognizes the .dicom extension', () {
      expect(isDcmFileName('scan.dicom'), isTrue);
    });

    test('is case-insensitive for both supported extensions', () {
      for (final name in [
        'scan.DCM',
        'scan.Dicom',
        'scan.DICOM',
        'SCAN.dCm',
      ]) {
        expect(isDcmFileName(name), isTrue, reason: name);
      }
    });

    test('accepts paths containing DICOM filenames', () {
      expect(isDcmFileName(r'C:\imports\patient\scan.dcm'), isTrue);
      expect(isDcmFileName('/imports/patient/scan.dicom'), isTrue);
    });

    test('accepts filenames with multiple dots', () {
      expect(isDcmFileName('patient.2026.01.scan.dcm'), isTrue);
      expect(isDcmFileName('patient.2026.01.scan.dicom'), isTrue);
    });

    test('accepts names that begin with a dot when the extension matches', () {
      expect(isDcmFileName('.dcm'), isTrue);
      expect(isDcmFileName('.dicom'), isTrue);
    });

    test('rejects empty and whitespace-only names', () {
      expect(isDcmFileName(''), isFalse);
      expect(isDcmFileName('   '), isFalse);
    });

    test('rejects names without a supported extension', () {
      for (final name in [
        'scan',
        'scan.txt',
        'scan.jpg',
        'scan.png',
        'scan.dcm.txt',
        'scan.dicom.jpg',
      ]) {
        expect(isDcmFileName(name), isFalse, reason: name);
      }
    });

    test('requires the extension at the end of the name', () {
      for (final name in [
        'scan.dcm.backup',
        'scan.dicom.backup',
        'scan.dcm.png',
        'scan.dicom.png',
      ]) {
        expect(isDcmFileName(name), isFalse, reason: name);
      }
    });

    test('does not treat a partial extension as DICOM', () {
      for (final name in [
        'scan.dc',
        'scan.dico',
        'scan.dcmx',
        'scan.dicomx',
        'scan.xdcm',
      ]) {
        expect(isDcmFileName(name), isFalse, reason: name);
      }
    });

    test('matches the suffix even when the basename has leading whitespace',
        () {
      expect(isDcmFileName(' scan.dcm'), isTrue);
      expect(isDcmFileName('\tscan.dicom'), isTrue);
      expect(isDcmFileName('scan.dcm '), isFalse);
      expect(isDcmFileName('scan.dicom\n'), isFalse);
    });

    test('handles Unicode and punctuation in the basename', () {
      expect(isDcmFileName('患者 #1 — 左上.dcm'), isTrue);
      expect(isDcmFileName('scan (final)!.DICOM'), isTrue);
    });
  });

  group('isDcmPreviewName', () {
    test('recognizes .dcm.png previews', () {
      expect(isDcmPreviewName('scan.dcm.png'), isTrue);
    });

    test('recognizes .dicom.png previews', () {
      expect(isDcmPreviewName('scan.dicom.png'), isTrue);
    });

    test('is case-insensitive for the DICOM and PNG suffixes', () {
      for (final name in [
        'scan.DCM.PNG',
        'scan.Dicom.Png',
        'scan.DICOM.PNG',
        'SCAN.dCm.pNg',
      ]) {
        expect(isDcmPreviewName(name), isTrue, reason: name);
      }
    });

    test('accepts preview paths and complex basenames', () {
      expect(isDcmPreviewName(r'C:\imports\scan.dcm.png'), isTrue);
      expect(isDcmPreviewName('/imports/patient.2026.scan.dicom.png'), isTrue);
      expect(isDcmPreviewName('患者 #1 — 左上.DICOM.PNG'), isTrue);
    });

    test('accepts names beginning with a dot when the full suffix matches', () {
      expect(isDcmPreviewName('.dcm.png'), isTrue);
      expect(isDcmPreviewName('.dicom.png'), isTrue);
    });

    test('rejects empty and whitespace-only names', () {
      expect(isDcmPreviewName(''), isFalse);
      expect(isDcmPreviewName('   '), isFalse);
    });

    test('rejects original DICOM names without the PNG suffix', () {
      expect(isDcmPreviewName('scan.dcm'), isFalse);
      expect(isDcmPreviewName('scan.dicom'), isFalse);
    });

    test('rejects ordinary PNG files', () {
      expect(isDcmPreviewName('scan.png'), isFalse);
      expect(isDcmPreviewName('photo.dcm.jpg'), isFalse);
      expect(isDcmPreviewName('photo.dicom.webp'), isFalse);
    });

    test('requires the complete suffix at the end of the name', () {
      for (final name in [
        'scan.dcm.png.backup',
        'scan.dicom.png.backup',
        'scan.dcm.png.jpg',
        'scan.dicom.png.tmp',
      ]) {
        expect(isDcmPreviewName(name), isFalse, reason: name);
      }
    });

    test('does not accept malformed or partial suffixes', () {
      for (final name in [
        'scan.dcm',
        'scan.dicom',
        'scan.dc.png',
        'scan.dico.png',
        'scan.dcm.pn',
        'scan.dcmx.png',
        'scan.dicomx.png',
        'scan.dcm.pngx',
      ]) {
        expect(isDcmPreviewName(name), isFalse, reason: name);
      }
    });

    test('matches the suffix even when the basename has leading whitespace',
        () {
      expect(isDcmPreviewName(' scan.dcm.png'), isTrue);
      expect(isDcmPreviewName('\tscan.dicom.png'), isTrue);
      expect(isDcmPreviewName('scan.dcm.png '), isFalse);
      expect(isDcmPreviewName('scan.dicom.png\n'), isFalse);
    });

    test('requires PNG as the preview extension', () {
      for (final name in [
        'scan.dcm.jpeg',
        'scan.dcm.PNGX',
        'scan.dicom.gif',
        'scan.dicom.png.png',
      ]) {
        expect(isDcmPreviewName(name), isFalse, reason: name);
      }
    });
  });

  group('relationship between DICOM originals and previews', () {
    test('supported previews are not classified as DICOM originals', () {
      for (final name in [
        'scan.dcm.png',
        'scan.dicom.png',
        'scan.DCM.PNG',
        'scan.DICOM.PNG',
      ]) {
        expect(isDcmPreviewName(name), isTrue, reason: name);
        expect(isDcmFileName(name), isFalse,
            reason: 'A preview must not be classified as an original: $name');
      }
    });

    test('ordinary DICOM originals are not previews', () {
      for (final name in ['scan.dcm', 'scan.dicom', 'scan.DCM', 'scan.DICOM']) {
        expect(isDcmFileName(name), isTrue, reason: name);
        expect(isDcmPreviewName(name), isFalse, reason: name);
      }
    });
  });
}
