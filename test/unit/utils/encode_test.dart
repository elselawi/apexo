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
  });
}
