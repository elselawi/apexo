import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/encode.dart';

void main() {
  group('Encode and Decode Tests', () {
    test('Encode should convert string to base64Url without padding', () {
      String input = 'Hello, World!';
      String encoded = encode(input);
      expect(encoded, 'SGVsbG8sIFdvcmxkIQ');
    });

    test('Decode should convert base64Url string back to original string', () {
      String encoded = 'SGVsbG8sIFdvcmxkIQ';
      String decoded = decode(encoded);
      expect(decoded, 'Hello, World!');
    });

    test('Encode and Decode should be reversible', () {
      String input = 'Flutter is awesome!';
      String encoded = encode(input);
      String decoded = decode(encoded);
      expect(decoded, input);
    });

    test('Decode should handle padding correctly', () {
      String encoded = 'SGVsbG8sIFdvcmxkIQ==';
      String decoded = decode(encoded);
      expect(decoded, 'Hello, World!');
    });

    test('round-trips Unicode, emoji, and newlines', () {
      const input = 'مرحبا 🌍\nこんにちは\nGrüße';

      expect(decode(encode(input)), input);
    });

    test('uses URL-safe unpadded Base64 output', () {
      final encoded = encode(String.fromCharCodes([251, 255, 255]));

      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(encoded, isNot(contains('=')));
      expect(decode(encoded), String.fromCharCodes([251, 255, 255]));
    });

    test('round-trips the empty string', () {
      expect(encode(''), '');
      expect(decode(''), '');
    });

    test('rejects malformed Base64 input', () {
      expect(() => decode('%%%'), throwsFormatException);
      expect(() => decode('a'), throwsFormatException);
    });
  });
}
