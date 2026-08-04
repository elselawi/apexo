import 'dart:convert';

import 'package:apexo/services/ai_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('AIService constants', () {
    test('workerUrl is the correct endpoint', () {
      expect(AIService.workerUrl, 'https://dataextraction.apexo.app');
    });
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
