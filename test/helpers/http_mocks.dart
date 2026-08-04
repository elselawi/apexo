import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ──────────────────────────────────────────────────────────────────────────────
// HTTP Mock Helpers
//
// Use `http.MockClient` (from the `http` package) to mock external HTTP
// endpoints that we should NOT hit from tests: the AI data-extraction worker,
// the version-check metadata endpoint, and the country-code API.
//
// PocketBase is intentionally not mocked here. Live PocketBase coverage lives
// under test/live_backend/ and is excluded from the normal unit suite.
// ──────────────────────────────────────────────────────────────────────────────

/// Creates a [MockClient] that responds with [body] (JSON-encoded) and
/// [statusCode] for every request. Useful for simple one-off mocks.
MockClient mockClientWith(
  dynamic body, {
  int statusCode = 200,
}) {
  return MockClient((request) async {
    return http.Response(
      body is String ? body : jsonEncode(body),
      statusCode,
    );
  });
}

/// Creates a [MockClient] that routes requests to different handlers based
/// on the URL hostname or path prefix.
///
/// [handlers] is a map of host/path → `(http.Request) → http.Response`.
/// Keys are matched as prefixes (e.g. `"dataextraction.apexo.app"` matches
/// any URL with that host).
MockClient mockRoutedClient(
  Map<String, http.Response Function(http.Request)> handlers,
) {
  return MockClient((request) async {
    final url = request.url.toString();
    for (final entry in handlers.entries) {
      if (url.contains(entry.key)) {
        return entry.value(request);
      }
    }
    return http.Response('Unhandled: $url', 404);
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// Pre-built error responses
// ──────────────────────────────────────────────────────────────────────────────

http.Response error404(http.Request _) =>
    http.Response('{"error":"Not Found"}', 404);

http.Response error500(http.Request _) =>
    http.Response('{"error":"Internal Server Error"}', 500);

http.Response errorTimeout(http.Request _) =>
    http.Response('', 408, headers: {'x-timeout': 'true'});

http.Response errorNetwork(http.Request _) =>
    throw http.ClientException('Connection refused');

// ──────────────────────────────────────────────────────────────────────────────
// AI Worker mock — https://dataextraction.apexo.app
// ──────────────────────────────────────────────────────────────────────────────

/// Returns a token response the AI worker would send.
http.Response mockAITokenResponse(http.Request _) => http.Response(
      jsonEncode({'token': 'mock-ai-token-24h', 'expires_in': 86400}),
      200,
    );

/// Returns a dental history transcription response.
http.Response mockDentalHistoryResponse(http.Request _) => http.Response(
      jsonEncode({
        'data': {
          'teeth': {'11': 'filling', '21': 'crown'},
          'extra_notes': 'Patient reports sensitivity on upper right.',
        }
      }),
      200,
    );

/// Returns a post-op notes generation response.
http.Response mockPostOpNotesResponse(http.Request _) => http.Response(
      jsonEncode({
        'data': {
          'notes': 'Procedure completed successfully.',
          'prescriptions': 'Amoxicillin 500mg 3x/day for 7 days',
          'price': 150.0,
          'paid': 150.0,
          'teeth': {'36': 'extraction'},
          'labwork': {'name': 'Crown Lab', 'notes': 'PFM crown #11'},
        }
      }),
      200,
    );

/// Returns a receipt scan response.
http.Response mockReceiptScanResponse(http.Request _) => http.Response(
      jsonEncode({
        'data': {
          'supplierName': 'Dental Supplies Co.',
          'date': '2026-01-15',
          'items': [
            {
              'name': 'Composite Kit',
              'quantity': 2,
              'unitPrice': 45.0,
              'total': 90.0
            },
            {
              'name': 'Gloves Box',
              'quantity': 5,
              'unitPrice': 8.0,
              'total': 40.0
            },
          ],
          'total': 130.0,
        }
      }),
      200,
    );

/// Convenience: a MockClient pre-configured for all AI worker endpoints.
MockClient mockAIWorker() => mockRoutedClient({
      'token': (_) => mockAITokenResponse(_),
      'dental-history': (_) => mockDentalHistoryResponse(_),
      'post-op': (_) => mockPostOpNotesResponse(_),
      'receipt': (_) => mockReceiptScanResponse(_),
    });

// ──────────────────────────────────────────────────────────────────────────────
// Version check mock — https://download.apexo.app/metadata.json
// ──────────────────────────────────────────────────────────────────────────────

http.Response mockVersionResponse(http.Request _) => http.Response(
      jsonEncode({
        'latest_version': '2.0.0',
        'changelog': ['Fix crash on login', 'Add dark mode'],
        'downloads': {
          'ms_store': 'https://store.example.com',
          'macos': 'https://mac.example.com',
          'ios': 'https://ios.example.com',
          'android': 'https://android.example.com',
          'web': 'https://web.example.com',
        },
      }),
      200,
    );

// ──────────────────────────────────────────────────────────────────────────────
// Country API mock — https://api.country.is/
// ──────────────────────────────────────────────────────────────────────────────

http.Response mockCountryResponse(http.Request _) =>
    http.Response(jsonEncode({'country': 'US'}), 200);
