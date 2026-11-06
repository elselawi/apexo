import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'booking_models.dart';

/// Stable, typed booking Worker errors. Codes mirror the Worker's response and
/// are the only text the UI may show (never a submitted value).
class BookingApiException implements Exception {
  BookingApiException({
    required this.code,
    this.statusCode,
    this.fields = const {},
    this.suggestions = const [],
    this.retryAfter,
    this.network = false,
  });

  final String code;
  final int? statusCode;
  final Map<String, String> fields;
  final List<String> suggestions;
  final Duration? retryAfter;
  final bool network;

  bool get unauthorized => statusCode == 401;
  bool get forbidden => statusCode == 403;
  bool get notFound => statusCode == 404;
  bool get conflict => statusCode == 409;
  bool get rateLimited => statusCode == 429;

  /// The clinic key was revoked or the clinic was erased: stop polling.
  bool get keyRevoked => unauthorized || forbidden;

  @override
  String toString() => "BookingApiException($code, status: $statusCode)";
}

class BookingDiagnostics {
  factory BookingDiagnostics.fromJson(Map<String, Object?> json) =>
      BookingDiagnostics(
        handle: (json["handle"] ?? "").toString(),
        publicUrl: (json["publicUrl"] ?? "").toString(),
        status: (json["status"] ?? "live").toString(),
        enabled: json["enabled"] == true,
        pending: (json["pending"] as num?)?.toInt() ?? 0,
        lastPullAt: (json["lastPullAt"] as num?)?.toInt(),
        configRevision: (json["configRevision"] as num?)?.toInt() ?? 0,
        keyRevision: (json["keyRevision"] as num?)?.toInt() ?? 1,
      );
  BookingDiagnostics({
    required this.handle,
    required this.publicUrl,
    required this.status,
    required this.enabled,
    required this.pending,
    required this.lastPullAt,
    required this.configRevision,
    required this.keyRevision,
  });

  final String handle;
  final String publicUrl;
  final String status;
  final bool enabled;
  final int pending;
  final int? lastPullAt;
  final int configRevision;
  final int keyRevision;
}

class BookingPullPage {
  factory BookingPullPage.fromJson(Map<String, Object?> json) =>
      BookingPullPage(
        items: (json["items"] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((entry) =>
                BookingRequest.fromJson(entry.cast<String, Object?>()))
            .toList(),
        nextBeforeSeq: (json["nextBeforeSeq"] as num?)?.toInt(),
        snapshot: json["snapshot"]?.toString(),
        pending: (json["pending"] as num?)?.toInt() ?? 0,
      );
  BookingPullPage({
    required this.items,
    required this.nextBeforeSeq,
    required this.snapshot,
    required this.pending,
  });

  final List<BookingRequest> items;
  final int? nextBeforeSeq;
  final String? snapshot;
  final int pending;
}

class BookingConfigSnapshot {
  BookingConfigSnapshot({
    required this.config,
    required this.revision,
    required this.handle,
    required this.publicUrl,
  });

  final BookingClinicConfig config;
  final int revision;
  final String handle;
  final String publicUrl;
}

class BookingRegistrationResult {
  BookingRegistrationResult({required this.clinicId, required this.publicUrl,
      this.keyRevision = 1});

  final String clinicId;
  final String publicUrl;
  final int keyRevision;
}

/// Thin client for the booking Worker. Every call has a bounded timeout and
/// surfaces a typed error instead of a raw transport exception.
class BookingApi {
  BookingApi({
    required String origin,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  })  : origin = origin.replaceAll(RegExp(r"/+$"), ""),
        _client = client ?? http.Client();

  final String origin;
  final Duration timeout;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse("$origin$path");

  Map<String, String> _headers(String? key) => {
        "content-type": "application/json",
        "accept": "application/json",
        if (key != null) "authorization": "Bearer $key",
      };

  Future<Map<String, Object?>> _send(
    String path,
    Map<String, Object?> body, {
    String? key,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(_uri(path), headers: _headers(key), body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw BookingApiException(code: "timeout", network: true);
    } catch (_) {
      throw BookingApiException(code: "network", network: true);
    }
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      payload = decoded is Map
          ? decoded.cast<String, Object?>()
          : <String, Object?>{};
    } catch (_) {
      payload = <String, Object?>{};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }
    final error = (payload["error"] as Map?)?.cast<String, Object?>();
    final fields = <String, String>{};
    final rawFields = error?["fields"];
    if (rawFields is Map) {
      rawFields
          .forEach((key, value) => fields[key.toString()] = value.toString());
    }
    final retryAfter = int.tryParse(response.headers["retry-after"] ?? "");
    final suggestions = (response.headers["x-suggested-handles"] ?? "")
        .split(",")
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    throw BookingApiException(
      code: (error?["code"] ?? "unavailable").toString(),
      statusCode: response.statusCode,
      fields: fields,
      suggestions: suggestions,
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
    );
  }

  Future<BookingRegistrationResult> register(Map<String, Object?> body) async {
    final payload = await _send("/v1/register", body);
    return BookingRegistrationResult(
      clinicId: (payload["clinicId"] ?? "").toString(),
      publicUrl: (payload["publicUrl"] ?? "").toString(),
      keyRevision: (payload["keyRevision"] as num?)?.toInt() ?? 1,
    );
  }

  Future<BookingRegistrationResult> recover(Map<String, Object?> body) async {
    final payload = await _send("/v1/recover", body);
    return BookingRegistrationResult(
      clinicId: (payload["clinicId"] ?? "").toString(),
      publicUrl: (payload["publicUrl"] ?? "").toString(),
      keyRevision: (payload["keyRevision"] as num?)?.toInt() ?? 1,
    );
  }

  Future<BookingDiagnostics> diagnostics(String key) async {
    final payload = await _send("/v1/clinic/diagnostics", const {}, key: key);
    return BookingDiagnostics.fromJson(payload);
  }

  Future<BookingConfigSnapshot> readConfig(String adminKey) async {
    final payload =
        await _send("/v1/clinic/config/read", const {}, key: adminKey);
    return BookingConfigSnapshot(
      config: BookingClinicConfig.fromJson(
          (payload["config"] as Map?)?.cast<String, Object?>() ?? const {}),
      revision: (payload["revision"] as num?)?.toInt() ?? 0,
      handle: (payload["handle"] ?? "").toString(),
      publicUrl: (payload["publicUrl"] ?? "").toString(),
    );
  }

  Future<int> writeConfig(
    String adminKey,
    BookingClinicConfig config,
    int expectedRevision,
  ) async {
    final payload = await _send(
      "/v1/clinic/config",
      {"expectedRevision": expectedRevision, "config": config.toJson()},
      key: adminKey,
    );
    return (payload["revision"] as num?)?.toInt() ?? expectedRevision + 1;
  }


  Future<int> rotate(
    String adminKey, {
    required int expectedKeyRevision,
    required String newAdminKey,
    required String newInboxKey,
  }) async {
    final payload = await _send(
      "/v1/clinic/rotate",
      {
        "expectedKeyRevision": expectedKeyRevision,
        "adminKey": newAdminKey,
        "inboxKey": newInboxKey,
      },
      key: adminKey,
    );
    return (payload["keyRevision"] as num?)?.toInt() ?? expectedKeyRevision + 1;
  }

  /// Leaves the platform. The handle must be spelled out to confirm.
  Future<void> deleteClinic(String adminKey, String handle) async {
    await _send("/v1/clinic/delete", {"confirmHandle": handle}, key: adminKey);
  }

  Future<BookingPullPage> pull(
    String key, {
    String status = "pending",
    int? beforeSeq,
    String? snapshot,
    int limit = 50,
  }) async {
    final payload = await _send(
      "/v1/clinic/requests/pull",
      {
        "status": status,
        "beforeSeq": beforeSeq,
        "snapshot": snapshot,
        "limit": limit,
      },
      key: key,
    );
    return BookingPullPage.fromJson(payload);
  }

  Future<int> setRequestState(
    String key, {
    required String requestId,
    required int expectedVersion,
    required String state,
    String? linkedId,
  }) async {
    final payload = await _send(
      "/v1/clinic/requests/state",
      {
        "requestId": requestId,
        "expectedVersion": expectedVersion,
        "state": state,
        if (linkedId != null) "linkedId": linkedId,
      },
      key: key,
    );
    return (payload["version"] as num?)?.toInt() ?? expectedVersion + 1;
  }

  Future<void> deleteRequest(String adminKey, String requestId) async {
    await _send("/v1/clinic/requests/delete", {"requestId": requestId},
        key: adminKey);
  }

  Future<Map<String, Object?>> publicClinic(String handle) async {
    http.Response response;
    try {
      response = await _client.get(
          _uri("/v1/clinics/${Uri.encodeComponent(handle)}"),
          headers: const {"accept": "application/json"}).timeout(timeout);
    } on TimeoutException {
      throw BookingApiException(code: "timeout", network: true);
    } catch (_) {
      throw BookingApiException(code: "network", network: true);
    }
    return _decode(response);
  }

  void dispose() => _client.close();
}
