import 'dart:convert';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:http/http.dart' as http;

/// Base for Worker-backed AI services; they share one persisted 24h bearer token.
class AIService {
  /// The fixed Worker endpoint for all AI features.
  static const String workerUrl = 'https://dataextraction.apexo.app';

  // Keep track of any in-flight authentication request to deduplicate concurrent calls
  static Future<String>? _authFuture;
  static String? _authServer;
  static String? _authCredential;

  /// Authenticates with the Worker and returns a bearer token valid for 24h.
  static Future<String> _authenticate(String server, String credential) async {
    final key = await PushRelay.ensureKey();
    if (login.url != server || login.token != credential) {
      throw StateError('Session changed while authenticating AI services');
    }
    final r = await http.post(
      Uri.parse('$workerUrl/auth'),
      headers: {'x-server': server, 'x-worker-key': key},
    );
    if (r.statusCode != 200) {
      // The worker may return non-JSON on failure; fall back to a generic message.
      Map<String, dynamic> parsed = {};
      try {
        parsed = jsonDecode(r.body) as Map<String, dynamic>;
      } catch (_) {
        // body is not valid JSON; keep empty parsed map
      }
      throw Exception(parsed['error'] ?? 'Auth failed (${r.statusCode})');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return body['token'] as String;
  }

  /// Returns a valid bearer token, re-authenticating if expired or missing.
  static Future<String> getToken() async {
    final server = login.url;
    final credential = login.token;
    if (localSettings.hasValidAiToken && localSettings.aiTokenServer == server) {
      return localSettings.aiToken!;
    }

    if (_authFuture != null && _authServer == server && _authCredential == credential) {
      return _authFuture!;
    }
    final future = _authenticate(server, credential);
    _authFuture = future;
    _authServer = server;
    _authCredential = credential;

    try {
      final token = await future;
      if (login.url != server || login.token != credential) {
        throw StateError('Session changed while authenticating AI services');
      }
      localSettings.aiTokenServer = server;
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
    if (r.statusCode == 200) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return fromJson(body);
    }
    // Non-200: parse error body gracefully — server may return non-JSON.
    Map<String, dynamic> parsed = {};
    try {
      parsed = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      // body is not valid JSON; keep empty parsed map
    }
    throw Exception(parsed['error'] ?? 'Request failed (${r.statusCode})');
  }
}
