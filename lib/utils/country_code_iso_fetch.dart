import 'dart:convert';
import 'package:http/http.dart' as http;

const String countryCodeApiUrl = 'https://api.country.is/';

/// Fetches the caller's ISO country code from [countryCodeApiUrl].
///
/// Returns the two-letter `country` field when present and valid; otherwise
/// falls back to `"US"`. Network and malformed-response failures are also
/// non-fatal because this lookup must never block sign-in.
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
