import 'package:apexo/services/changelog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangelogVersion', () {
    test('constructor sets version and changes', () {
      const cv = ChangelogVersion(
        version: '1.0.0',
        changes: ['Fix bug', 'Add feature'],
      );
      expect(cv.version, '1.0.0');
      expect(cv.changes, ['Fix bug', 'Add feature']);
    });

    test('empty changes list', () {
      const cv = ChangelogVersion(version: '1.0.0', changes: []);
      expect(cv.changes, isEmpty);
    });

    test('multiple changes', () {
      const cv = ChangelogVersion(
        version: '2.0.0',
        changes: ['Feature A', 'Feature B', 'Fix C'],
      );
      expect(cv.changes.length, 3);
    });
  });

  group('ChangelogService — real asset', () {
    test('singleton exists', () {
      expect(changelog, isNotNull);
      expect(changelog, isA<ChangelogService>());
    });

    test('load() parses CHANGELOG.md and returns versions', () async {
      final versions = await changelog.load();
      expect(versions, isNotEmpty);
      expect(versions.first.version, isNotEmpty);
      expect(versions.first.changes, isNotEmpty);
    });

    test('all loaded versions have valid semver format', () async {
      final versions = await changelog.load();
      for (final v in versions) {
        expect(v.version, matches(RegExp(r'^\d+\.\d+\.\d+$')),
            reason: 'Version "${v.version}" is not semver');
      }
    });

    test('all loaded versions have non-empty changes', () async {
      final versions = await changelog.load();
      for (final v in versions) {
        expect(v.changes, isNotEmpty,
            reason: 'Version ${v.version} has no changes');
      }
    });

    test('changes are properly formatted bullet points', () async {
      final versions = await changelog.load();
      for (final v in versions) {
        for (final change in v.changes) {
          expect(change.trim(), startsWith('•'),
              reason: 'Change "$change" is not a bullet');
        }
      }
    });

    test('forVersion() finds existing version', () async {
      final versions = await changelog.load();
      if (versions.isNotEmpty) {
        final found = await changelog.forVersion(versions.first.version);
        expect(found, isNotNull);
        expect(found!.version, versions.first.version);
        expect(found.changes, versions.first.changes);
      }
    });

    test('forVersion() returns null for nonexistent version', () async {
      expect(await changelog.forVersion('999.999.999'), isNull);
      expect(await changelog.forVersion('0.0.0'), isNull);
    });

    test('forVersion() returns null for empty string', () async {
      expect(await changelog.forVersion(''), isNull);
    });

    test('latest() returns first (most recent) version', () async {
      final versions = await changelog.load();
      if (versions.isNotEmpty) {
        final latest = await changelog.latest();
        expect(latest, isNotNull);
        expect(latest!.version, versions.first.version);
      }
    });

    test('load() caches — second call returns same reference', () async {
      final v1 = await changelog.load();
      final v2 = await changelog.load();
      expect(identical(v1, v2), true);
    });

    test('load() cached after failed forVersion()', () async {
      await changelog.forVersion('999.999.999');
      final v1 = await changelog.load();
      final v2 = await changelog.load();
      expect(identical(v1, v2), true);
    });
  });

  group('CHANGELOG.md asset', () {
    test('exists in bundle', () async {
      final raw = await rootBundle.loadString('CHANGELOG.md');
      expect(raw, isNotEmpty);
      expect(raw, contains('###'));
    });
  });
}
