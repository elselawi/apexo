// Adds `import 'dart:async';` to the files whose analysis reports `unawaited`
// as undefined, placing it before the first import so `dart:` sorts first.
//
// Usage:  dart run tools/add_dart_async_import.dart <analyze.log> [--apply]
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln("usage: dart run tools/add_dart_async_import.dart "
        "<flutter-analyze-output> [--apply]");
    exit(2);
  }

  final logPath = args.first;
  final apply = args.contains('--apply');
  final pattern = RegExp(
      r'^\s*(error|warning|info)\s+-\s+.*?\s+-\s+(.+?):(\d+):(\d+)\s+-\s+(\S+)\s*$');

  final files = <String>{};
  for (final line in File(logPath).readAsLinesSync()) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    final rule = match.group(5);
    if (rule != 'undefined_method' && rule != 'undefined_function') continue;
    if (!line.contains("'unawaited'")) continue;
    files.add(match.group(2)!);
  }

  var changed = 0;
  final sorted = files.toList()..sort();
  for (final path in sorted) {
    if (!File(path).existsSync()) continue;
    final src = File(path).readAsStringSync();
    if (src.contains("import 'dart:async';") ||
        src.contains('import "dart:async";')) {
      continue;
    }

    final lines = src.split('\n');
    var insertAt = lines.length;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trimLeft();
      if (t.startsWith('import ') || t.startsWith('export ')) {
        insertAt = i;
        break;
      }
    }

    lines.insert(insertAt, "import 'dart:async';");
    if (apply) File(path).writeAsStringSync(lines.join('\n'));
    changed++;
    stdout.writeln('  $path  (inserted before line ${insertAt + 1})');
  }

  stdout.writeln('');
  stdout.writeln(apply
      ? 'APPLIED to $changed file(s).'
      : 'DRY RUN: would update $changed file(s).');
}
