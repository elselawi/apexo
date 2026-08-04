import 'dart:convert';

import 'package:apexo/utils/country_code_iso_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('getCountryCode', () {
    test('returns the decoded country code', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': 'US'}), 200),
      );
      expect(await getCountryCode(client: client), 'US');
    });

    test('requests the country.is endpoint', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'country': 'IQ'}), 200);
      });

      await getCountryCode(client: client);

      expect(requested, Uri.parse(countryCodeApiUrl));
      expect(requested.toString(), 'https://api.country.is/');
    });

    test('preserves case of a valid country code', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': 'gb'}), 200),
      );

      // Length check only — the function does not normalize case.
      expect(await getCountryCode(client: client), 'gb');
    });

    test('falls back to US when country is missing', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'ip': '1.2.3.4'}), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US when country is null', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': null}), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US when country is not a string', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': 964}), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US when country is shorter than 2 characters',
        () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': 'I'}), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US when country is longer than 2 characters', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': 'IRQ'}), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US when country is an empty string', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': ''}), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US when response body is not valid JSON', () async {
      final client = MockClient(
        (_) async => http.Response('not-json', 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US for a JSON array response', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(['IQ']), 200),
      );

      expect(await getCountryCode(client: client), 'US');
    });

    test('falls back to US for JSON scalar responses', () async {
      for (final body in [
        jsonEncode(null),
        jsonEncode('US'),
        jsonEncode(123)
      ]) {
        final client = MockClient((_) async => http.Response(body, 200));

        expect(await getCountryCode(client: client), 'US');
      }
    });

    test('falls back to US after one HTTP client failure without retrying',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        throw http.ClientException('network down');
      });

      expect(await getCountryCode(client: client), 'US');
      expect(calls, 1);
    });

    test('falls back to US for a non-success status code', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'country': 'FR'}), 500),
      );

      expect(await getCountryCode(client: client), 'US');
    });
  });
}
