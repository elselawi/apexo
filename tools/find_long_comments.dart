// Lists comment blocks spanning two or more lines; run with --help for options.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const int _slash = 0x2F;
const int _star = 0x2A;
const int _singleQuote = 0x27;
const int _doubleQuote = 0x22;
const int _backslash = 0x5C;
const int _dollar = 0x24;
const int _lBrace = 0x7B;
const int _rBrace = 0x7D;
const int _space = 0x20;
const int _tab = 0x09;
const int _lf = 0x0A;
const int _cr = 0x0D;

final RegExp _directivePattern = RegExp(
  r'^(?:ignore(?:_for_file)?\s*:|coverage\s*:\s*ignore|dart\s+format\b|noqa\b|analyzer\s*:)',
);

void main(List<String> args) {
  stdout.encoding = utf8;
  stderr.encoding = utf8;

  final options = _parseArgs(args);
  final root = p.normalize(p.absolute(options.root ?? _inferRoot()));
  if (!Directory(root).existsSync()) {
    _fail('Root directory not found: $root');
  }

  final targets = options.targets.isEmpty
      ? <String>[_defaultTarget(root)]
      : options.targets;
  final files = _collectDartFiles(targets);
  if (files.isEmpty) {
    stderr.writeln('No Dart files found in ${targets.join(', ')}.');
    exit(1);
  }

  final findings = <_Finding>[];
  var filesScanned = 0;
  var commentBlocks = 0;
  var skippedGenerated = 0;
  var skippedDoc = 0;

  for (final file in files) {
    String source;
    try {
      source = File(file.path).readAsStringSync();
    } on FileSystemException catch (error) {
      stderr.writeln('warning: cannot read ${file.path}: ${error.message}');
      continue;
    } on FormatException catch (error) {
      stderr.writeln('warning: cannot decode ${file.path}: ${error.message}');
      continue;
    }

    if (!options.includeGenerated &&
        !file.explicit &&
        _isGenerated(file.path, source)) {
      skippedGenerated++;
      continue;
    }

    filesScanned++;
    final scanner = _Scanner(source)..scan();
    commentBlocks += scanner.comments.length;

    for (final comment in scanner.comments) {
      if (comment.lineCount < options.minLines) continue;
      if (options.excludeDoc && comment.isDoc) {
        skippedDoc++;
        continue;
      }
      findings.add(_Finding(_displayPath(file.path, root), comment));
    }
  }

  findings.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0
        ? byPath
        : a.comment.startLine.compareTo(b.comment.startLine);
  });

  if (options.format == 'json') {
    _writeJson(
      findings: findings,
      root: root,
      options: options,
      filesScanned: filesScanned,
      commentBlocks: commentBlocks,
      skippedDoc: skippedDoc,
      skippedGenerated: skippedGenerated,
    );
  } else {
    _writeText(
      findings: findings,
      root: root,
      options: options,
      filesScanned: filesScanned,
      commentBlocks: commentBlocks,
      skippedDoc: skippedDoc,
      skippedGenerated: skippedGenerated,
    );
  }
}

class _Options {
  int minLines = 2;
  String format = 'text';
  bool full = false;
  bool excludeDoc = false;
  bool includeGenerated = false;
  bool color = true;
  String? root;
  final List<String> targets = <String>[];
}

class _DartFile {
  const _DartFile(this.path, {required this.explicit});

  final String path;
  final bool explicit;
}

class _Finding {
  const _Finding(this.path, this.comment);

  final String path;
  final _Comment comment;
}

enum _Style { line, block }

class _Comment {
  const _Comment({
    required this.startLine,
    required this.endLine,
    required this.style,
    required this.isDoc,
    required this.text,
    this.unterminated = false,
  });

  final int startLine;
  final int endLine;
  final _Style style;
  final bool isDoc;
  final String text;
  final bool unterminated;

  int get lineCount => endLine - startLine + 1;

  String get label {
    if (isDirective) return 'directive';
    if (isDoc) return 'doc';
    return style == _Style.line ? '//' : '/* */';
  }

  bool get isDirective {
    for (final line in text.split('\n')) {
      final content = _commentContent(line, style);
      if (content.isEmpty) continue;
      return _directivePattern.hasMatch(content);
    }
    return false;
  }
}

class _Scanner {
  _Scanner(this.source) : _lineStarts = _buildLineStarts(source);

  final String source;
  final List<int> _lineStarts;
  final List<_Comment> comments = <_Comment>[];
  final List<_LineToken> _lineTokens = <_LineToken>[];

  void scan() {
    var i = 0;
    while (i < source.length) {
      final code = source.codeUnitAt(i);
      if (code == _slash && i + 1 < source.length) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          i = _readLineComment(i);
          continue;
        }
        if (next == _star) {
          i = _readBlockComment(i);
          continue;
        }
      }
      if (code == _singleQuote || code == _doubleQuote) {
        i = _skipString(i);
        continue;
      }
      i++;
    }
    _assembleLineComments();
    comments.sort((a, b) => a.startLine.compareTo(b.startLine));
  }

  int _readLineComment(int start) {
    final line = _lineOf(start);
    var end = source.indexOf('\n', start);
    if (end < 0) end = source.length;
    if (end > start && source.codeUnitAt(end - 1) == _cr) end--;

    final prefix = source.substring(_lineStarts[line - 1], start);
    final isDoc =
        start + 2 < source.length && source.codeUnitAt(start + 2) == _slash;

    _lineTokens.add(
      _LineToken(
        line: line,
        text: source.substring(start, end),
        isDoc: isDoc,
        standalone: _isBlank(prefix),
      ),
    );
    return end;
  }

  int _readBlockComment(int start) {
    final (end, terminated) = _skipBlockComment(start);
    final lastOffset = end > start ? end - 1 : start;
    final isDoc = start + 2 < source.length &&
        source.codeUnitAt(start + 2) == _star &&
        !(start + 3 < source.length && source.codeUnitAt(start + 3) == _slash);

    comments.add(
      _Comment(
        startLine: _lineOf(start),
        endLine: _lineOf(lastOffset),
        style: _Style.block,
        isDoc: isDoc,
        text: _dedent(source.substring(start, end)),
        unterminated: !terminated,
      ),
    );
    return end;
  }

  void _assembleLineComments() {
    for (var i = 0; i < _lineTokens.length;) {
      final first = _lineTokens[i];
      var last = first;
      var next = i + 1;

      if (first.standalone) {
        while (next < _lineTokens.length) {
          final candidate = _lineTokens[next];
          if (!candidate.standalone || candidate.line != last.line + 1) break;
          last = candidate;
          next++;
        }
      }

      final group = _lineTokens.sublist(i, next);
      comments.add(
        _Comment(
          startLine: first.line,
          endLine: last.line,
          style: _Style.line,
          isDoc: group.every((token) => token.isDoc),
          text: group.map((token) => token.text).join('\n'),
        ),
      );
      i = next;
    }
  }

  int _skipString(int quote) {
    final raw = quote > 0 &&
        (source.codeUnitAt(quote - 1) == 0x72 ||
            source.codeUnitAt(quote - 1) == 0x52);
    final mark = source.codeUnitAt(quote);
    final triple = quote + 2 < source.length &&
        source.codeUnitAt(quote + 1) == mark &&
        source.codeUnitAt(quote + 2) == mark;

    var i = quote + (triple ? 3 : 1);
    while (i < source.length) {
      final code = source.codeUnitAt(i);
      if (!raw && code == _backslash) {
        i += 2;
        continue;
      }
      if (!raw && code == _dollar) {
        if (i + 1 < source.length && source.codeUnitAt(i + 1) == _lBrace) {
          i = _skipInterpolation(i + 1);
          continue;
        }
        i++;
        while (i < source.length && _isIdentifierPart(source.codeUnitAt(i))) {
          i++;
        }
        continue;
      }
      if (triple) {
        if (code == mark &&
            i + 2 < source.length &&
            source.codeUnitAt(i + 1) == mark &&
            source.codeUnitAt(i + 2) == mark) {
          return i + 3;
        }
      } else if (code == mark) {
        return i + 1;
      }
      i++;
    }
    return source.length;
  }

  int _skipInterpolation(int brace) {
    var depth = 1;
    var i = brace + 1;
    while (i < source.length) {
      final code = source.codeUnitAt(i);
      if (code == _slash && i + 1 < source.length) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          i = _readLineComment(i);
          continue;
        }
        if (next == _star) {
          i = _readBlockComment(i);
          continue;
        }
      }
      if (code == _singleQuote || code == _doubleQuote) {
        i = _skipString(i);
        continue;
      }
      if (code == _lBrace) depth++;
      if (code == _rBrace) {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return source.length;
  }

  (int, bool) _skipBlockComment(int start) {
    var depth = 1;
    var i = start + 2;
    while (i < source.length) {
      final code = source.codeUnitAt(i);
      if (code == _slash &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == _star) {
        depth++;
        i += 2;
        continue;
      }
      if (code == _star &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == _slash) {
        depth--;
        i += 2;
        if (depth == 0) return (i, true);
        continue;
      }
      i++;
    }
    return (source.length, false);
  }

  int _lineOf(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (_lineStarts[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return high + 1;
  }
}

class _LineToken {
  const _LineToken({
    required this.line,
    required this.text,
    required this.isDoc,
    required this.standalone,
  });

  final int line;
  final String text;
  final bool isDoc;
  final bool standalone;
}

class _Palette {
  const _Palette(this.enabled);

  final bool enabled;

  String bold(String text) => _apply(text, 1);
  String cyan(String text) => _apply(text, 36);
  String dim(String text) => _apply(text, 2);

  String _apply(String text, int code) =>
      enabled ? '\x1B[${code}m$text\x1B[0m' : text;
}

void _writeText({
  required List<_Finding> findings,
  required String root,
  required _Options options,
  required int filesScanned,
  required int commentBlocks,
  required int skippedDoc,
  required int skippedGenerated,
}) {
  final colors = _Palette(options.color && stdout.supportsAnsiEscapes);
  final commentLines = findings.fold<int>(
      0, (total, finding) => total + finding.comment.lineCount);
  final filesWithComments =
      findings.map((finding) => finding.path).toSet().length;

  stdout.writeln(colors.bold('Comments of ${options.minLines}+ lines'));
  stdout.writeln('${colors.dim('Root:')} ${_toSlash(root)}');

  if (findings.isNotEmpty) {
    stdout.writeln();
    var previousPath = '';
    for (final finding in findings) {
      if (previousPath.isNotEmpty && finding.path != previousPath) {
        stdout.writeln();
      }
      previousPath = finding.path;

      final comment = finding.comment;
      final range = comment.startLine == comment.endLine
          ? '${comment.startLine}'
          : '${comment.startLine}-${comment.endLine}';
      final label = comment.label;
      final unterminated = comment.unterminated ? ', unterminated' : '';
      final meta = '[$label, ${comment.lineCount} '
          '${_plural(comment.lineCount, 'line')}$unterminated]';

      stdout.writeln(
        '${colors.cyan('${finding.path}:$range')}  ${colors.dim(meta)}',
      );
      if (options.full) {
        for (final line in comment.text.split('\n')) {
          stdout.writeln(line.isEmpty ? '' : '    $line');
        }
      } else {
        stdout.writeln('    ${_preview(comment)}');
      }
    }
  }

  stdout.writeln();
  stdout.writeln(
    'Scanned $filesScanned ${_plural(filesScanned, 'Dart file')} '
    '($commentBlocks ${_plural(commentBlocks, 'comment block')}).',
  );
  if (findings.isEmpty) {
    stdout.writeln(
      'No comments of ${options.minLines}+ lines found.',
    );
  } else {
    stdout.writeln(
      '${findings.length} ${_plural(findings.length, 'comment')} of '
      '${options.minLines}+ lines in $filesWithComments '
      '${_plural(filesWithComments, 'file')} '
      '($commentLines comment ${_plural(commentLines, 'line')}).',
    );
  }
  if (skippedGenerated > 0) {
    stdout.writeln(
      'Skipped $skippedGenerated generated ${_plural(skippedGenerated, 'file')} '
      '(--include-generated to audit).',
    );
  }
  if (skippedDoc > 0) {
    stdout.writeln(
      'Skipped $skippedDoc documentation ${_plural(skippedDoc, 'comment')} '
      '(--exclude-doc).',
    );
  }
}

void _writeJson({
  required List<_Finding> findings,
  required String root,
  required _Options options,
  required int filesScanned,
  required int commentBlocks,
  required int skippedDoc,
  required int skippedGenerated,
}) {
  final commentLines = findings.fold<int>(
      0, (total, finding) => total + finding.comment.lineCount);
  final payload = <String, Object?>{
    'root': _toSlash(root),
    'minLines': options.minLines,
    'summary': <String, Object?>{
      'filesScanned': filesScanned,
      'commentBlocks': commentBlocks,
      'commentCount': findings.length,
      'fileCount': findings.map((finding) => finding.path).toSet().length,
      'commentLines': commentLines,
      'skippedDocComments': skippedDoc,
      'skippedGeneratedFiles': skippedGenerated,
    },
    'comments': <Map<String, Object?>>[
      for (final finding in findings)
        <String, Object?>{
          'path': finding.path,
          'startLine': finding.comment.startLine,
          'endLine': finding.comment.endLine,
          'lineCount': finding.comment.lineCount,
          'style': finding.comment.style.name,
          'doc': finding.comment.isDoc,
          'directive': finding.comment.isDirective,
          'unterminated': finding.comment.unterminated,
          'text': finding.comment.text,
        },
    ],
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
}

void _printUsage() {
  stdout.writeln('''
Lists comment blocks that span two or more source lines.

A run of adjacent standalone // lines counts as one comment; a trailing //
comment after code counts on its own.

Usage: dart run tools/find_long_comments.dart [options] [paths...]

Paths may be files or directories and are resolved from the current directory.
With no paths, scans <root>/lib. Output paths are relative to the repository
root; paths outside it stay absolute.

Options:
      --min-lines=<n>       Minimum line span (default: 2)
      --format=<text|json>  Output format (default: text)
      --full                Print every comment line instead of a preview
      --exclude-doc         Skip /// and /** */ documentation comments
      --include-generated   Include generated files (skipped by default)
      --root=<path>         Repository root for relative paths
      --no-color            Disable ANSI color
  -h, --help                Show this help

Examples:
  dart run tools/find_long_comments.dart
  dart run tools/find_long_comments.dart lib/features test
  dart run tools/find_long_comments.dart --format=json
''');
}

_Options _parseArgs(List<String> args) {
  final options = _Options();

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') {
      options.targets.addAll(args.skip(i + 1));
      break;
    }
    if (arg == '-h' || arg == '--help') {
      _printUsage();
      exit(0);
    }
    if (!arg.startsWith('-')) {
      options.targets.add(arg);
      continue;
    }

    final equals = arg.indexOf('=');
    final name = equals < 0 ? arg : arg.substring(0, equals);
    final inline = equals < 0 ? null : arg.substring(equals + 1);

    String valueFor() {
      if (inline != null) return inline;
      if (i + 1 >= args.length) _fail('$name requires a value.');
      i++;
      return args[i];
    }

    void rejectValue() {
      if (inline != null) _fail('$name does not take a value.');
    }

    if (name == '--min-lines') {
      final value = valueFor();
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 1) {
        _fail('$name must be a positive integer.');
      }
      options.minLines = parsed;
    } else if (name == '--format') {
      final value = valueFor();
      if (value != 'text' && value != 'json') {
        _fail('$name must be "text" or "json".');
      }
      options.format = value;
    } else if (name == '--root') {
      options.root = valueFor();
    } else if (name == '--full') {
      rejectValue();
      options.full = true;
    } else if (name == '--exclude-doc') {
      rejectValue();
      options.excludeDoc = true;
    } else if (name == '--include-generated') {
      rejectValue();
      options.includeGenerated = true;
    } else if (name == '--no-color') {
      rejectValue();
      options.color = false;
    } else {
      _fail('Unknown option: $name');
    }
  }

  return options;
}

List<_DartFile> _collectDartFiles(List<String> targets) {
  final files = <_DartFile>[];
  final indexByPath = <String, int>{};

  for (final raw in targets) {
    final target = p.normalize(p.absolute(raw));
    final type = FileSystemEntity.typeSync(target);
    if (type == FileSystemEntityType.notFound) {
      _fail('Path not found: $raw');
    }
    if (type == FileSystemEntityType.directory) {
      _walk(Directory(target), files, indexByPath);
    } else if (type == FileSystemEntityType.file) {
      if (!target.toLowerCase().endsWith('.dart')) {
        _fail('Not a Dart file: $raw');
      }
      _addFile(target, explicit: true, files: files, indexByPath: indexByPath);
    } else {
      _fail('Not a file or directory: $raw');
    }
  }

  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void _walk(
  Directory directory,
  List<_DartFile> files,
  Map<String, int> indexByPath,
) {
  try {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (_skipDirectory(entity.path)) continue;
        _walk(entity, files, indexByPath);
      } else if (entity is File &&
          entity.path.toLowerCase().endsWith('.dart')) {
        _addFile(
          entity.path,
          explicit: false,
          files: files,
          indexByPath: indexByPath,
        );
      }
    }
  } on FileSystemException catch (error) {
    stderr.writeln('warning: cannot list ${directory.path}: ${error.message}');
  }
}

void _addFile(
  String path, {
  required bool explicit,
  required List<_DartFile> files,
  required Map<String, int> indexByPath,
}) {
  final normalized = p.normalize(p.absolute(path));
  final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
  final existing = indexByPath[key];
  if (existing != null) {
    if (explicit && !files[existing].explicit) {
      files[existing] = _DartFile(normalized, explicit: true);
    }
    return;
  }
  indexByPath[key] = files.length;
  files.add(_DartFile(normalized, explicit: explicit));
}

bool _skipDirectory(String path) {
  final name = p.basename(path);
  return name.startsWith('.') || name == 'build' || name == 'node_modules';
}

bool _isGenerated(String path, String source) {
  final name = p.basename(path).toLowerCase();
  if (name == 'firebase_options.dart' ||
      name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.mocks.dart') ||
      name.endsWith('.gen.dart')) {
    return true;
  }

  for (final line in source.split('\n').take(3)) {
    final normalized = line.trim().toLowerCase();
    if (normalized.startsWith('// generated') ||
        normalized.startsWith('// file generated') ||
        normalized.startsWith('// auto-generated') ||
        (normalized.contains('generated') &&
            (normalized.contains('do not edit') ||
                normalized.contains('do not modify')))) {
      return true;
    }
  }
  return false;
}

String _defaultTarget(String root) {
  final lib = p.join(root, 'lib');
  return Directory(lib).existsSync() ? lib : root;
}

String _inferRoot() {
  if (Platform.script.isScheme('file')) {
    final scriptPath = p.fromUri(Platform.script);
    return p.dirname(p.dirname(scriptPath));
  }
  return Directory.current.path;
}

String _displayPath(String path, String root) {
  final relative = p.relative(path, from: root);
  if (p.isAbsolute(relative) ||
      relative == '..' ||
      relative.startsWith('..${p.separator}') ||
      relative.startsWith('../')) {
    return _toSlash(p.normalize(path));
  }
  return _toSlash(relative);
}

String _toSlash(String path) => path.replaceAll(r'\', '/');

String _preview(_Comment comment) {
  for (final line in comment.text.split('\n')) {
    final content = _commentContent(line, comment.style);
    if (content.isEmpty) continue;
    final runes = content.runes.toList();
    if (runes.length > 100) {
      return '${String.fromCharCodes(runes.take(100))}...';
    }
    return content;
  }
  return '(empty)';
}

String _commentContent(String line, _Style style) {
  var text = line.trim();
  if (text.startsWith('///')) {
    text = text.substring(3);
  } else if (text.startsWith('//')) {
    text = text.substring(2);
  } else if (text.startsWith('/**')) {
    text = text.substring(3);
  } else if (text.startsWith('/*')) {
    text = text.substring(2);
  }
  if (text.endsWith('*/')) text = text.substring(0, text.length - 2);
  text = text.trim();
  if (style == _Style.block && text.startsWith('*')) {
    text = text.substring(1).trim();
  }
  return text;
}

String _dedent(String text) {
  final lines = text.split('\n');
  var indent = -1;

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    var leading = 0;
    while (leading < line.length) {
      final code = line.codeUnitAt(leading);
      if (code != _space && code != _tab) break;
      leading++;
    }
    if (indent < 0 || leading < indent) indent = leading;
  }

  if (indent <= 0) {
    return lines.map((line) => line.trimRight()).join('\n');
  }
  return lines
      .map((line) => line.length > indent
          ? line.substring(indent).trimRight()
          : line.trimRight())
      .join('\n');
}

bool _isBlank(String text) {
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (code != _space && code != _tab && code != _cr && code != 0xFEFF) {
      return false;
    }
  }
  return true;
}

bool _isIdentifierPart(int code) =>
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    code == 0x5F ||
    code == _dollar;

List<int> _buildLineStarts(String source) {
  final starts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == _lf) starts.add(i + 1);
  }
  return starts;
}

String _plural(int count, String singular, [String? plural]) =>
    count == 1 ? singular : (plural ?? '${singular}s');

Never _fail(String message) {
  stderr.writeln('error: $message');
  stderr.writeln('Run with --help for usage.');
  exit(2);
}
