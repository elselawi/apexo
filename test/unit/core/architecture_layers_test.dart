import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The layers the window work introduced, and the edges neither may cross.
///
/// The window system is a framework: features open panels through it, it opens
/// nothing of theirs. Keeping that one-way is what lets the layer sit below the
/// app and be tested without a store, a feature or a session — and it is the
/// edge that made a 56-line preference helper reach 268 of the 281 files under
/// `lib/`.
void main() {
  Set<String> importsUnder(String root) {
    final dir = Directory(root);
    expect(dir.existsSync(), isTrue, reason: root);
    final found = <String>{};
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match
          in RegExp(r'''import\s+['"]([^'"]+)['"]''').allMatches(source)) {
        found.add(match.group(1)!);
      }
    }
    return found;
  }

  test('the window system does not import the app or a feature', () {
    final imports = importsUnder(p.join('lib', 'ui'));
    expect(imports, isNotEmpty);
    expect(
      imports.where((uri) =>
          uri.startsWith('package:apexo/app/') ||
          uri.startsWith('package:apexo/features/')),
      isEmpty,
      reason: 'lib/ui/ is below the app and the features: it may use core, '
          'services, common widgets and itself, and nothing above it.',
    );
  });

  test('a shared editor does not import a feature', () {
    final imports = importsUnder(p.join('lib', 'shared'));
    expect(imports, isNotEmpty);
    expect(
      imports.where((uri) =>
          uri.startsWith('package:apexo/features/') ||
          uri.startsWith('package:apexo/app/')),
      isEmpty,
      reason: 'A shared editor is used by more than one feature, so it may not '
          'know any of them: the feature supplies what the editor needs.',
    );
  });

  test('a service does not import the app widget or the window system', () {
    final imports = importsUnder(p.join('lib', 'services'));
    expect(
      imports.where((uri) =>
          uri == 'package:apexo/app/app.dart' ||
          uri.startsWith('package:apexo/ui/')),
      isEmpty,
      reason: 'A service announces what happened (see SessionEvents); the app '
          'decides what to do about it.',
    );
  });

  test('a window opener is not named like a panel opener', () {
    final offenders = <String>[];
    for (final entity
        in Directory(p.join('lib', 'features')).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = p.basename(entity.path);
      final source = entity.readAsStringSync();
      if (name.endsWith('_panel.dart') &&
          !source.contains('PanelsManager.open')) {
        offenders.add('${entity.path}: a panel opener must open a panel');
      }
      if (name.endsWith('_window.dart') && !source.contains('showStandalone')) {
        offenders.add('${entity.path}: a window opener must show a window');
      }
    }
    expect(offenders, isEmpty);
  });

  test('the language service does not import a feature', () {
    final source = File(
      p.join('lib', 'services', 'localization', 'locale.dart'),
    ).readAsStringSync();
    expect(source, isNot(contains('package:apexo/features/')));
  });
}
