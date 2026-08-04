import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the boundary between deterministic unit tests and live backend
/// tests. This prevents credentials and network setup from being pulled into
/// ordinary `flutter test` discovery by accident.
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
      if (!source.contains("@Tags(['live_backend'])")) {
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
