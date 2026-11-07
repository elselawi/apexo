import 'dart:convert';
import 'package:http/http.dart' as http;

const String countryCodeApiUrl = 'https://api.country.is/';

/// Fetches the caller's ISO country code, falling back to "US"; failures are
/// non-fatal because the lookup must never block sign-in.
Future<String> getCountryCode({
  http.Client? client,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final response = await (client?.get(Uri.parse(countryCodeApiUrl)) ??
            http.get(Uri.parse(countryCodeApiUrl)))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return "US";
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) return "US";
    final res = data['country'];
    return (res is String && res.length == 2) ? res : "US";
  } catch (_) {
    return "US";
  }
}
