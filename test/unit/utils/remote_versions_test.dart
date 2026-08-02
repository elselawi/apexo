import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/utils/remote_versions.dart';

void main() {
  group('Remote Versions Tests', () {
    test('getLatestVersion fetches real data from GitHub', () async {
      final result = await getLatestVersion('elselawi', 'apexo', 'dist');

      expect(result, isA<GithubContent>());
      expect(result.name, contains('.apk'));
      expect(result.downloadUrl, isNotNull);
      expect(result.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('GithubContent.fromJson creates valid object', () {
      final json = {
        'name': 'apexo-1.2.3.apk',
        'download_url': 'https://example.com/download',
      };

      final content = GithubContent.fromJson(json);

      expect(content.name, equals('apexo-1.2.3.apk'));
      expect(content.downloadUrl, equals('https://example.com/download'));
      expect(content.version, equals('1.2.3'));
    });

    test('Version extraction works with different filename patterns', () {
      final testCases = [
        {'name': 'app-v1.2.3.apk', 'expected': '1.2.3'},
        {'name': 'release_2.3.4.apk', 'expected': '2.3.4'},
        {'name': 'apexo-3.4.5-release.apk', 'expected': '3.4.5'},
      ];

      for (var testCase in testCases) {
        final content = GithubContent.fromJson({'name': testCase['name'], 'download_url': 'https://example.com'});
        expect(content.version, equals(testCase['expected']));
      }
    });

    test('Version comparison sorts correctly', () async {
      final versions = [
        GithubContent.fromJson({'name': 'app-1.0.0.apk', 'download_url': 'url1'}),
        GithubContent.fromJson({'name': 'app-2.0.0.apk', 'download_url': 'url2'}),
        GithubContent.fromJson({'name': 'app-1.5.0.apk', 'download_url': 'url3'}),
        GithubContent.fromJson({'name': 'app-1.0.1.apk', 'download_url': 'url4'}),
        GithubContent.fromJson({'name': 'app-1.0.0-beta.apk', 'download_url': 'url5'}),
        GithubContent.fromJson({'name': 'app-1.0.0-rc.apk', 'download_url': 'url6'}),
      ];

      versions.sort((a, b) {
        final List<int> versionA = a.version.split('.').map(int.parse).toList();
        final List<int> versionB = b.version.split('.').map(int.parse).toList();

        for (int i = 0; i < versionA.length; i++) {
          if (versionA[i] != versionB[i]) {
            return versionB[i].compareTo(versionA[i]);
          }
        }
        return 0;
      });

      expect(versions[0].version, equals('2.0.0'));
      expect(versions[1].version, equals('1.5.0'));
      expect(versions[2].version, equals('1.0.1'));
    });
  });
}
