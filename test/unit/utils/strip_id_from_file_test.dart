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
  });
}
