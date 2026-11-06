import 'dart:convert';

import 'package:apexo/services/ai_services.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('AIService constants', () {
    test('workerUrl is the correct endpoint', () {
      expect(AIService.workerUrl, 'https://dataextraction.apexo.app');
    });
  });

  test('cached AI tokens belong to their clinic server', () async {
    final saved = localSettings.toJson();
    final oldServer = login.url;
    final oldPocketBase = login.pb;
    try {
      login.url = 'https://clinic-a.test';
      localSettings.aiToken = 'cached-ai-token';
      localSettings.aiTokenServer = login.url;
      localSettings.aiTokenExpiry = DateTime.now().add(const Duration(hours: 24));
      expect(await AIService.getToken(), 'cached-ai-token');
      login.url = 'https://clinic-b.test';
      login.pb = null;
      await expectLater(AIService.getToken(), throwsA(anything));
      expect(localSettings.aiTokenServer, 'https://clinic-a.test');
    } finally {
      localSettings.fromJson(saved);
      login.url = oldServer;
      login.pb = oldPocketBase;
    }
  });

  group('AIService.parseResponse', () {
    test('parses 200 response correctly', () {
      final response = _mockResponse(200, {'result': 'success', 'data': 42});

      final result = AIService.parseResponse<int>(
        response,
        (json) => json['data'] as int,
      );

      expect(result, 42);
    });

    test('throws on non-200 response', () {
      final response = _mockResponse(500, {'error': 'Server error'});

      expect(
        () => AIService.parseResponse<int>(response, (_) => 0),
        throwsA(predicate((error) => '$error' == 'Exception: Server error')),
      );
    });

    test('throws on 400 response', () {
      final response = _mockResponse(400, {'error': 'Bad request'});

      expect(
        () => AIService.parseResponse<int>(response, (_) => 0),
        throwsA(predicate((error) => '$error' == 'Exception: Bad request')),
      );
    });

    test('throws on 401 unauthorized', () {
      final response = _mockResponse(401, {'error': 'Invalid token'});

      expect(
        () => AIService.parseResponse<int>(response, (_) => 0),
        throwsA(predicate((error) => '$error' == 'Exception: Invalid token')),
      );
    });

    for (final body in ['<html>Bad Gateway</html>', '', '[]', 'null', '"error"']) {
      test('uses status fallback for non-object error body: $body', () {
        var parsed = false;
        expect(
          () => AIService.parseResponse<int>(http.Response(body, 502), (_) {
            parsed = true;
            return 0;
          }),
          throwsA(predicate((e) => '$e' == 'Exception: Request failed (502)')),
        );
        expect(parsed, isFalse);
      });
    }

    test('still rejects malformed successful responses', () {
      expect(
        () => AIService.parseResponse<int>(
          http.Response('not JSON', 200),
          (_) => 0,
        ),
        throwsFormatException,
      );
    });

    test('error message includes status code when no error field', () {
      final response = _mockResponse(503, {});

      expect(
        () => AIService.parseResponse<int>(response, (_) => 0),
        throwsA(predicate((e) => '$e'.contains('503'))),
      );
    });
  });
}

http.Response _mockResponse(int statusCode, Map<String, dynamic> body) {
  return http.Response(jsonEncode(body), statusCode);
}
