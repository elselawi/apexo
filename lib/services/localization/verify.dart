#!/usr/bin/env dart run
// Localization Auditor — comprehensive i18n health check for Apexo
// Usage: dart run lib/services/localization/verify.dart
//   or:  cd lib/services/localization && dart run verify.dart

import 'dart:io';

final _green = _ansi(32);
final _red = _ansi(31);
final _yellow = _ansi(33);
final _cyan = _ansi(36);
final _bold = _ansi(1);
final _dim = _ansi(2);
final _reset = _ansi(0);

String _ansi(int code) => '\x1B[${code}m';

void main() {
  final scriptDir = Directory(Platform.script.toFilePath()).parent;
  final localizationDir = Directory(scriptDir.path);

  if (!localizationDir.existsSync()) {
    print(
        '${_red}ERROR: Could not find localization directory at ${localizationDir.path}$_reset');
    exit(1);
  }

  // ── 1. Discover all locale files ──
  final localeFiles = _discoverLocaleFiles(localizationDir);
  if (localeFiles.isEmpty) {
    print('${_red}No locale files found.$_reset');
    exit(1);
  }
  print('${_bold}📁 Found ${localeFiles.length} locale files:$_reset');
  for (final f in localeFiles) {
    final marker =
        _basename(f.path) == 'en.dart' ? ' ${_green}(reference)$_reset' : '';
    print('   ${_dim}${_basename(f.path)}$_reset$marker');
  }

  // Use en.dart as the canonical reference
  final referenceFile = localeFiles.firstWhere(
    (f) => _basename(f.path) == 'en.dart',
    orElse: () => localeFiles.first,
  );

  // ── 2. Extract dictionaries ──
  final locales = <String, Map<String, String>>{};
  for (final file in localeFiles) {
    locales[_basename(file.path)] = _extractDictionary(file);
  }

  // ── 3. Cross-reference keys across ALL files ──
  print('\n${_bold}🔍 CROSS-REFERENCING KEYS ACROSS ALL LOCALES$_reset');
  print('${_dim}${'─' * 60}$_reset');

  final allKeySets = <String, Set<String>>{};
  for (final e in locales.entries) {
    allKeySets[e.key] = e.value.keys.toSet();
  }

  final refName = _basename(referenceFile.path);
  final refKeys = allKeySets[refName]!;
  bool allMatch = true;

  for (final entry in allKeySets.entries) {
    if (entry.key == refName) continue;
    final missing = refKeys.difference(entry.value);
    final extra = entry.value.difference(refKeys);

    if (missing.isNotEmpty) {
      allMatch = false;
      print(
          '${_red}  ✗ $refName → ${entry.key}: MISSING ${missing.length} key(s)$_reset');
      for (final k in missing) {
        print(
            '     ${_red}- "$k"$_reset  ${_dim}($refName = "${locales[refName]![k]}")$_reset');
      }
    }
    if (extra.isNotEmpty) {
      allMatch = false;
      print(
          '${_yellow}  ⚠ ${entry.key}: ${extra.length} extra key(s) not in $refName$_reset');
      for (final k in extra) {
        print(
            '     ${_yellow}+ "$k"$_reset  ${_dim}= "${locales[entry.key]![k]}"$_reset');
      }
    }
  }

  if (allMatch) {
    print(
        '${_green}  ✓ All ${localeFiles.length} files have identical keys (${refKeys.length} keys)$_reset');
  }

  // ── 4. Scan codebase for txt("...") calls ──
  print('\n${_bold}🔎 SCANNING CODEBASE FOR UNLOCALIZED STRINGS$_reset');
  print('${_dim}${'─' * 60}$_reset');

  final workspaceRoot = _findWorkspaceRoot(localizationDir);
  final txtCalls = _scanCodebaseForTxtCalls(workspaceRoot);
  final usedKeys = <String>{};
  final dynamicUsages = <_TxtCall>[];

  for (final call in txtCalls) {
    if (call.key != null) {
      usedKeys.add(call.key!);
    } else {
      dynamicUsages.add(call);
    }
  }

  final unlocalized = usedKeys.difference(refKeys);
  if (unlocalized.isNotEmpty) {
    print(
        '${_yellow}  ⚠ ${unlocalized.length} string(s) used via txt() but NOT localized:$_reset');
    for (final s in unlocalized) {
      final locations = txtCalls
          .where((c) => c.key == s)
          .map((c) => '${_relativePath(c.file, workspaceRoot)}:${c.line}')
          .toSet()
          .take(3);
      print(
          '  ${_yellow}  "$s"$_reset  ${_dim}→ ${locations.join(', ')}$_reset');
    }
  } else {
    print(
        '${_green}  ✓ All txt() calls reference existing dictionary keys$_reset');
  }

  // ── 5. Unused localization strings: blind search for definitively unused ──
  print('\n${_bold}🧹 UNUSED LOCALIZATION STRINGS$_reset');
  print('${_dim}${'─' * 60}$_reset');

  final initiallyUnused = refKeys.difference(usedKeys);
  var definitelyUnused = <String>[];
  var maybeDynamic = <String>[];

  if (initiallyUnused.isNotEmpty) {
    // Blind search: for each key not seen as txt("..."), check if the raw
    // key string appears ANYWHERE in the codebase (variable, comment, etc.)
    final codeFiles = _collectCodeFiles(workspaceRoot);

    for (final key in initiallyUnused) {
      if (_keyAppearsInCodebase(key, codeFiles)) {
        maybeDynamic.add(key);
      } else {
        definitelyUnused.add(key);
      }
    }

    if (definitelyUnused.isNotEmpty) {
      print(
          '${_red}  ✗ ${definitelyUnused.length} key(s) DEFINITIVELY UNUSED (string not found anywhere in code):$_reset');
      for (final k in definitelyUnused) {
        print(
            '  ${_red}  "$k"$_reset  ${_dim}= "${locales[refName]![k]}"$_reset');
      }
    }

    if (maybeDynamic.isNotEmpty) {
      print(
          '${_yellow}  ⚠ ${maybeDynamic.length} key(s) may be used dynamically (string found in code, but not as txt("...")):$_reset');
      for (final k in maybeDynamic) {
        print(
            '  ${_yellow}  "$k"$_reset  ${_dim}= "${locales[refName]![k]}"$_reset');
      }
    }

    if (definitelyUnused.isEmpty && maybeDynamic.isEmpty) {
      print(
          '${_green}  ✓ All ${refKeys.length} keys are referenced in code$_reset');
    }
  } else {
    print(
        '${_green}  ✓ All ${refKeys.length} keys are referenced in code$_reset');
  }

  // ── 6. Dynamic txt() calls (variable / interpolation) ──
  print('\n${_bold}🔄 DYNAMIC txt() CALLS (cannot statically verify)$_reset');
  print('${_dim}${'─' * 60}$_reset');
  if (dynamicUsages.isNotEmpty) {
    final seen = <String>{};
    for (final call in dynamicUsages) {
      final loc =
          '${_relativePath(call.file, workspaceRoot)}:${call.line}  ${_dim}→ ${call.excerpt}$_reset';
      if (seen.add(loc)) {
        print('  ${_cyan}  $loc$_reset');
      }
    }
  } else {
    print('${_green}  ✓ None$_reset');
  }

  // ── 7. Summary ──
  print('\n${_bold}📊 SUMMARY$_reset');
  print('${_dim}${'─' * 60}$_reset');
  print('  Locale files          : ${localeFiles.length}');
  print('  Reference keys        : ${refKeys.length}');
  print('  Keys used in code     : ${usedKeys.length}');
  print(
      '  Keys match across all : ${allMatch ? '${_green}YES$_reset' : '${_red}NO$_reset'}');
  print('  Unlocalized strings   : ${unlocalized.length}');
  print('  Definitively unused   : ${definitelyUnused.length}');
  print('  Possibly dynamic      : ${maybeDynamic.length}');

  // ── 8. Per-file coverage ──
  print('\n${_bold}📋 PER-FILE COVERAGE$_reset');
  print('${_dim}${'─' * 60}$_reset');
  for (final entry in locales.entries) {
    final coverage = refKeys.isEmpty
        ? 100.0
        : (entry.value.keys.where(refKeys.contains).length /
            refKeys.length *
            100);
    final c = coverage == 100.0 ? _green : _yellow;
    print(
        '  ${entry.key.padRight(30)} ${entry.value.length.toString().padLeft(4)} entries   coverage: ${c}${coverage.toStringAsFixed(1)}%$_reset');
  }

  print('');
}

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────

/// Discover locale Dart files (exclude utility files).
List<File> _discoverLocaleFiles(Directory dir) {
  const exclude = {'locale.dart', 'test.dart', 'verify.dart'};
  return dir
      .listSync()
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') && !exclude.contains(_basename(f.path)))
      .toList()
    ..sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
}

/// Extract string key-value pairs from a locale dictionary file.
Map<String, String> _extractDictionary(File file) {
  final content = file.readAsStringSync();
  final map = <String, String>{};
  final regex = RegExp(r'"([^"\\]*(?:\\.[^"\\]*)*)"\s*:\s*"((?:[^"\\]|\\.)*)"');
  for (final m in regex.allMatches(content)) {
    final key = m.group(1)!;
    final value = m.group(2)!;
    map[key] = value
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t');
  }
  return map;
}

class _TxtCall {
  final String file;
  final int line;
  final String? key; // null if argument is not a plain string literal
  final String excerpt; // the matched txt(...) call snippet
  _TxtCall(this.file, this.line, this.key, this.excerpt);
}

/// Scan all .dart files under [root] for txt(...) calls.
/// Captures both literal txt("key") and dynamic txt(variable) / txt("${...}").
List<_TxtCall> _scanCodebaseForTxtCalls(Directory root) {
  final results = <_TxtCall>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Skip build artifacts, tests, the verify script itself, and locale.dart (txt definition)
    if (entity.path.contains('/build/') ||
        entity.path.contains('/.dart_tool/') ||
        entity.path.contains('/generated/') ||
        entity.path.contains('/test/') ||
        _basename(entity.path) == 'verify.dart' ||
        _basename(entity.path) == 'locale.dart') {
      continue;
    }
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Match txt("literal")
      final literalRegex = RegExp(r'''txt\(\s*"((?:[^"\\]|\\.)*)"\s*\)''');
      for (final m in literalRegex.allMatches(line)) {
        results.add(_TxtCall(entity.path, i + 1, m.group(1)!, m.group(0)!));
      }

      // Match txt(variable) or txt("${...}") — non-literal argument
      final dynamicRegex = RegExp(r'''txt\(\s*([^"][^)]*?)\s*\)''');
      for (final m in dynamicRegex.allMatches(line)) {
        final arg = m.group(1)!.trim();
        // Skip if it was already matched as literal
        if (arg.startsWith('"')) continue;
        // Truncate long arguments
        final excerpt = arg.length > 50 ? '${arg.substring(0, 47)}...' : arg;
        results.add(_TxtCall(entity.path, i + 1, null, 'txt($excerpt)'));
      }
    }
  }
  return results;
}

/// Walk up to find the workspace root (where pubspec.yaml lives).
Directory _findWorkspaceRoot(Directory dir) {
  var current = dir;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync()) return current;
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return dir;
}

/// Make a path relative to [root].
String _relativePath(String fullPath, Directory root) {
  final rp = root.path;
  if (fullPath.startsWith(rp)) return fullPath.substring(rp.length + 1);
  return fullPath;
}

/// Extract filename from a path (equivalent to File.name in newer Dart).
String _basename(String path) => path.split(Platform.pathSeparator).last;

/// Collect all non-excluded .dart source files under [root].
List<File> _collectCodeFiles(Directory root) {
  final files = <File>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/build/') ||
        entity.path.contains('/.dart_tool/') ||
        entity.path.contains('/generated/') ||
        entity.path.contains('/test/') ||
        entity.path.contains('/localization/') ||
        _basename(entity.path) == 'verify.dart') {
      continue;
    }
    files.add(entity);
  }
  return files;
}

/// Check whether [key] appears as a raw substring anywhere in [codeFiles].
bool _keyAppearsInCodebase(String key, List<File> codeFiles) {
  for (final file in codeFiles) {
    final content = file.readAsStringSync();
    if (content.contains(key)) return true;
  }
  return false;
}
