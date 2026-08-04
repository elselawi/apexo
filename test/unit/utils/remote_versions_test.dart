import 'package:apexo/services/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReleaseMetadata (was GithubContent)', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'latest_version': '2.0.0',
        'changelog': ['Fix bug', 'Add feature', 'Performance improvement'],
        'downloads': {
          'ms_store': 'https://store.example.com',
          'macos': 'https://mac.example.com',
          'ios': 'https://ios.example.com',
          'android': 'https://android.example.com',
          'web': 'https://web.example.com',
        },
      };

      final meta = ReleaseMetadata.fromJson(json);

      expect(meta.latestVersion, '2.0.0');
      expect(meta.changelog, hasLength(3));
      expect(meta.changelog, containsAll(['Fix bug', 'Add feature']));
      expect(meta.msStoreUrl, 'https://store.example.com');
      expect(meta.macosUrl, 'https://mac.example.com');
      expect(meta.iosUrl, 'https://ios.example.com');
      expect(meta.androidUrl, 'https://android.example.com');
      expect(meta.webUrl, 'https://web.example.com');
    });

    test('fromJson handles empty downloads map', () {
      final meta = ReleaseMetadata.fromJson({
        'latest_version': '0.0.0',
        'downloads': <String, dynamic>{},
      });

      expect(meta.latestVersion, '0.0.0');
      expect(meta.changelog, isEmpty);
      expect(meta.msStoreUrl, isEmpty);
      expect(meta.macosUrl, isEmpty);
      expect(meta.iosUrl, isEmpty);
      expect(meta.androidUrl, isEmpty);
      expect(meta.webUrl, isEmpty);
    });

    test('fromJson handles missing keys in downloads', () {
      final meta = ReleaseMetadata.fromJson({
        'latest_version': '1.0.0',
        'downloads': {'android': 'https://android.example.com'},
      });

      expect(meta.androidUrl, 'https://android.example.com');
      expect(meta.macosUrl, isEmpty);
    });

    test('defaults a missing changelog while retaining metadata fields', () {
      final meta = ReleaseMetadata.fromJson({
        'latest_version': '1.2.3',
        'downloads': {'web': 'https://web.example.com'},
      });

      expect(meta.changelog, isEmpty);
      expect(meta.webUrl, 'https://web.example.com');
    });

    test('rejects malformed downloads and changelog payloads', () {
      expect(() => ReleaseMetadata.fromJson({'latest_version': '1.0.0'}),
          throwsA(isA<TypeError>()));
      expect(
          () => ReleaseMetadata.fromJson(
              {'downloads': <String, dynamic>{}, 'changelog': 'not-a-list'}),
          throwsA(isA<TypeError>()));
    });
  });

  group('Version service', () {
    test('version service singleton exists', () {
      expect(version, isNotNull);
      expect(version.current(), isNotEmpty);
      expect(version.isOutdated(), false);
    });
  });
}
