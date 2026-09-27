import 'package:test/test.dart';
import 'package:apexo/utils/strip_id_from_file.dart';

void main() {
  group('stripIDFromFileName', () {
    test('removes ID from a valid file name', () {
      final result = stripIDFromFileName('file_12345.txt');
      expect(result, equals('file.txt'));
    });

    test('returns original name if no ID is present', () {
      final result = stripIDFromFileName('file.txt');
      expect(result, equals('file.txt'));
    });

    test('handles empty string input', () {
      final result = stripIDFromFileName('');
      expect(result, equals(''));
    });

    test('handles file names with multiple underscores', () {
      final result = stripIDFromFileName('file__12345.txt');
      expect(result, equals('file_.txt'));
    });

    test('handles file names without ID', () {
      final result = stripIDFromFileName('12345.txt');
      expect(result, equals('12345.txt'));
    });

    test('handles file names with special characters', () {
      final result = stripIDFromFileName('file_!@#\$.txt');
      expect(result, equals('file_!@#\$.txt'));
    });

    test('supports alphanumeric IDs and multi-dot file names', () {
      expect(stripIDFromFileName('report.final_aB19.pdf'), 'report.final.pdf');
      expect(stripIDFromFileName('résumé_X9.docx'), 'résumé.docx');
    });

    test('leaves extensionless, trailing-dot, and malformed IDs unchanged', () {
      expect(stripIDFromFileName('file_123'), 'file_123');
      expect(stripIDFromFileName('file_123.'), 'file_123.');
      expect(stripIDFromFileName('file_a-b.txt'), 'file_a-b.txt');
    });

    test(
        'removes final IDs in paths and URL-like names when an extension follows',
        () {
      expect(stripIDFromFileName(r'C:\photos_123\file_abc.png'),
          r'C:\photos_123\file.png');
      expect(stripIDFromFileName('https://host/file_abc.png?x=1'),
          'https://host/file.png?x=1');
    });
  });

  group('sameStoredFileName', () {
    test('matches a name to itself', () {
      expect(sameStoredFileName('photo.jpg', 'photo.jpg'), isTrue);
    });

    test("matches a name to PocketBase's suffixed spelling of it", () {
      // The exact case from the field: the record's column held the name from
      // before the upload was reported back, the reference PocketBase's.
      expect(
        sameStoredFileName(
            'heyg28i6whd4xnsun.jpg', 'heyg28i6whd4xnsun_avvm29b32h.jpg'),
        isTrue,
      );
      // …and the other way round.
      expect(
        sameStoredFileName(
            'heyg28i6whd4xnsun_avvm29b32h.jpg', 'heyg28i6whd4xnsun.jpg'),
        isTrue,
      );
    });

    test('matches a DICOM preview that carries a second suffix', () {
      // Also from the field: `dcmImgs` holds the original, the app derives the
      // preview's name from it, and PocketBase stored the preview with the
      // suffix of the *already suffixed* original.
      expect(
        sameStoredFileName(
          'dcm_h2bf0s59j7h6j5by1_18hy0rnie6.dcm.png',
          'dcm_h2bf0s59j7h6j5by1_18hy0rnie6_0cizfojiej.dcm.png',
        ),
        isTrue,
      );
    });

    test('does not match different files', () {
      expect(sameStoredFileName('photo.jpg', 'xray.jpg'), isFalse);
      expect(sameStoredFileName('photo.jpg', 'photo.png'), isFalse);
      expect(sameStoredFileName('photo.jpg', ''), isFalse);
    });
  });

  group('withoutStoredFileSuffix', () {
    test('takes the suffix off wherever a dot follows it', () {
      expect(withoutStoredFileSuffix('x_ab12cd34ef.png'), 'x.png');
      expect(
        withoutStoredFileSuffix('dcm_h2bf0s59j7h6j5by1_18hy0rnie6.dcm'),
        'dcm_h2bf0s59j7h6j5by1.dcm',
      );
      // The doubly-suffixed preview: only the first suffix is taken off, and
      // that is enough to recognise the name the column derives.
      expect(
        withoutStoredFileSuffix(
            'dcm_h2bf0s59j7h6j5by1_18hy0rnie6_0cizfojiej.dcm.png'),
        'dcm_h2bf0s59j7h6j5by1_18hy0rnie6.dcm.png',
      );
    });

    test('is null when there is no suffix to take off', () {
      expect(withoutStoredFileSuffix('photo.jpg'), isNull);
      expect(withoutStoredFileSuffix('dcm_x.dcm'), isNull);
    });
  });
}
