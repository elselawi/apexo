import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps live-backend credentials and network setup out of ordinary `flutter test` discovery.
void main() {
  test('unit tests do not import live backend credentials or helpers', () {
    final unitRoot = Directory('test/unit');
    expect(unitRoot.existsSync(), isTrue);

    final offenders = <String>[];
    for (final entity in unitRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(r'''import\s+['"][^'"]*(secret\.dart|test_utils\.dart)['"]''')
              .hasMatch(source) ||
          RegExp(r'''^\s*@Tags\(\['live_backend'\]\)''', multiLine: true)
              .hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty,
        reason:
            'Move live-credential tests under test/live_backend: $offenders');
  });

  test('live backend tests are explicitly tagged', () {
    final liveBackendRoot = Directory('test/live_backend');
    expect(liveBackendRoot.existsSync(), isTrue);

    final offenders = <String>[];
    for (final entity in liveBackendRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains("'live_backend'")) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Live backend tests must carry the live_backend tag: $offenders',
    );
  });
}
