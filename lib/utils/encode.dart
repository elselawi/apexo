import 'dart:convert';

String encode(String input) {
  final bytes = utf8.encode(input);
  final base64Str = base64Url.encode(bytes);
  return base64Str.replaceAll('=', ''); // Remove padding
}

String decode(String encoded) {
  // Add padding if missing
  final String padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
  final bytes = base64Url.decode(padded);
  return utf8.decode(bytes);
}
