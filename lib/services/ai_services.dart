import 'dart:convert';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:http/http.dart' as http;

/// Base class for all AI-powered services that use the Apexo AI Worker.
///
/// Provides shared token management (24h bearer token with auto-renewal)
/// and common request helpers. Subclasses extend this for specific
/// features like receipt scanning, post-op notes, dental history, etc.
class AIService {
  /// The fixed Worker endpoint for all AI features.
  static const String workerUrl = 'https://dataextraction.apexo.app';

  // Keep track of any in-flight authentication request to deduplicate concurrent calls
  static Future<String>? _authFuture;

  // ---------------------------------------------------------------------------
  //  Token management (shared across all AI services)
  // ---------------------------------------------------------------------------

  /// Authenticates with the Worker and returns a bearer token valid for 24h.
  static Future<String> _authenticate() async {
    final key = await PushRelay.ensureKey();
    final r = await http.post(
      Uri.parse('$workerUrl/auth'),
      headers: {'x-server': login.url, 'x-worker-key': key},
    );
    if (r.statusCode != 200) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Auth failed (${r.statusCode})');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return body['token'] as String;
  }

  /// Returns a valid bearer token, re-authenticating if expired or missing.
  static Future<String> getToken() async {
    if (localSettings.hasValidAiToken) {
      return localSettings.aiToken!;
    }

    if (_authFuture != null) {
      return _authFuture!;
    }
    final future = _authenticate();
    _authFuture = future;

    try {
      final token = await future;
      localSettings.aiToken = token;
      localSettings.aiTokenExpiry =
          DateTime.now().add(const Duration(hours: 24));
      localSettings.notifyAndPersist();
      return token;
    } finally {
      if (_authFuture == future) {
        _authFuture = null;
      }
    }
  }

  // ---------------------------------------------------------------------------
  //  Helpers
  // ---------------------------------------------------------------------------

  /// Creates a [http.MultipartRequest] with the bearer token attached.
  static Future<http.MultipartRequest> createMultipartRequest(
    String endpoint,
  ) async {
    final token = await getToken();
    final r = http.MultipartRequest('POST', Uri.parse('$workerUrl/$endpoint'));
    r.headers['Authorization'] = 'Bearer $token';
    return r;
  }

  /// Parses a response JSON body into [T], throwing on non-200 status.
  static T parseResponse<T>(
    http.Response r,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode == 200) return fromJson(body);
    throw Exception(body['error'] ?? 'Request failed (${r.statusCode})');
  }
}
