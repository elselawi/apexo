import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Set<String> dependencies(String entry) {
  final visited = <String>{};
  void visit(String file) {
    file = p.normalize(file);
    if (!visited.add(file)) return;
    final source = File(file).readAsStringSync();
    for (final match in RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''')
        .allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:') && !uri.startsWith('package:apexo/')) {
        continue;
      }
      visit(uri.startsWith('package:apexo/')
          ? p.join('lib', uri.substring('package:apexo/'.length))
          : p.join(p.dirname(file), uri));
    }
  }

  visit(entry);
  return visited.map((file) => p.split(file).join('/')).toSet();
}

void main() {
  test(
      'standalone observables and sync policies have no application or persistence dependencies',
      () {
    for (final entry in [
      p.join('lib', 'core', 'reactive', 'observable_base.dart'),
      p.join('lib', 'core', 'synchronization', 'conflict_merge.dart'),
      p.join('lib', 'core', 'synchronization', 'deferred_file_keys.dart'),
      p.join('lib', 'core', 'synchronization', 'push_data.dart'),
      p.join('lib', 'core', 'persistence', 'serial_operation_queue.dart'),
      p.join('lib', 'core', 'lifecycle', 'session_callbacks.dart'),
    ]) {
      expect(dependencies(entry), {p.split(entry).join('/')}, reason: entry);
    }
  });

  test(
      'store and adapters cannot transitively initialize application singletons',
      () {
    final graph = dependencies(p.join('lib', 'core', 'store.dart'));
    expect(
        graph.where((file) =>
            file.startsWith('lib/app/') ||
            file.startsWith('lib/features/') ||
            file.startsWith('lib/services/notifications/') ||
            file == 'lib/services/login.dart' ||
            file == 'lib/services/network.dart' ||
            file == 'lib/utils/logger.dart'),
        isEmpty);
  });

  test(
      'the reactive dictionary does not depend on Hive or persisted observables',
      () {
    final graph =
        dependencies(p.join('lib', 'core', 'reactive', 'observable.dart'));
    expect(graph.where((file) => file.startsWith('lib/core/persistence/')),
        isEmpty);
  });

  test('feature session registrations belong to the application binding', () {
    for (final feature in [
      'patients',
      'appointments',
      'expenses',
      'notes',
      'settings'
    ]) {
      final file = p.join('lib', 'features', feature,
          '${feature}_store${feature == 'settings' ? 's' : ''}.dart');
      final source = File(file).readAsStringSync();
      expect(source, contains('StoreSessionBinding<'));
      expect(source, isNot(contains('login.activators')));
      expect(source, isNot(contains('network.onOnline')));
      expect(source, isNot(contains('onLogoutCallbacks.add')));
    }
  });
}
