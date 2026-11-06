import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// The constrained RFC 8785 subset the Worker also implements.
///
/// Only null, booleans, valid Unicode strings, arrays, objects and safe
/// integers are accepted. Object keys are sorted by UTF-16 code unit — which is
/// what Dart's [String.compareTo] compares — and strings use the same minimal
/// escaping. Dart's `jsonEncode` is *not* a substitute: it escapes differently
/// and would produce different bytes, hence a different operation hash.
String canonicalJson(Object? value) => _encode(value, 0);

const int _maxDepth = 64;

String _encode(Object? value, int depth) {
  if (depth > _maxDepth) throw const FormatException("canonical_too_deep");
  if (value == null) return "null";
  if (value is bool) return value ? "true" : "false";
  if (value is int) return value.toString();
  if (value is String) return _encodeString(value);
  if (value is List) {
    return "[${value.map((item) => _encode(item, depth + 1)).join(",")}]";
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    final parts = <String>[];
    for (final key in keys) {
      parts.add("${_encodeString(key)}:${_encode(value[key], depth + 1)}");
    }
    return "{${parts.join(",")}}";
  }
  throw FormatException("canonical_unsupported_${value.runtimeType}");
}

String _encodeString(String value) {
  final buffer = StringBuffer('"');
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      final next = index + 1 < value.length ? value.codeUnitAt(index + 1) : 0;
      if (next < 0xdc00 || next > 0xdfff) {
        throw const FormatException("canonical_lone_surrogate");
      }
      buffer
        ..writeCharCode(code)
        ..writeCharCode(next);
      index++;
      continue;
    }
    if (code >= 0xdc00 && code <= 0xdfff) {
      throw const FormatException("canonical_lone_surrogate");
    }
    switch (code) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5c:
        buffer.write(r"\\");
      case 0x08:
        buffer.write(r"\b");
      case 0x09:
        buffer.write(r"\t");
      case 0x0a:
        buffer.write(r"\n");
      case 0x0c:
        buffer.write(r"\f");
      case 0x0d:
        buffer.write(r"\r");
      default:
        if (code < 0x20) {
          buffer.write("\\u${code.toRadixString(16).padLeft(4, "0")}");
        } else {
          buffer.writeCharCode(code);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

String sha256Hex(String value) =>
    crypto.sha256.convert(utf8.encode(value)).toString();

String keyHash(String key) => sha256Hex(key);

String operationHash(Map<String, Object?> fields) =>
    sha256Hex(canonicalJson(fields));

final Random _random = Random.secure();

String randomHex(int bytes) {
  final buffer = StringBuffer();
  for (var index = 0; index < bytes; index++) {
    buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, "0"));
  }
  return buffer.toString();
}

List<int> _randomBytes(int length) =>
    List<int>.generate(length, (_) => _random.nextInt(256));

/// A 256-bit CSPRNG key encoded as base64url (43 characters).
String generateBookingKey() =>
    base64Url.encode(_randomBytes(32)).replaceAll("=", "");

/// A 256-bit key encoded as base64url (43 characters).
///
/// Length and alphabet are the contract; the Worker's `isKey` checks exactly
/// the same two things. Decoding is deliberately not required here — Dart's
/// decoder rejects non-zero trailing bits, which JavaScript's `atob` accepts,
/// so a decode-based check would disagree with the server about which strings
/// are keys.
bool isBookingKey(Object? value) =>
    value is String && RegExp(r"^[A-Za-z0-9_-]{43}$").hasMatch(value);

/// NFC normalization used before hashing and before validating text.
String nfc(String value) => unorm.nfc(value);

int codePointLength(String value) => value.runes.length;
