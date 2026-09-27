// Wraps the statements the analyzer flagged with `unawaited_futures` in
// `unawaited(...)`.
//
// The diagnostic points at the start of the offending expression, so the
// wrapper has to enclose the whole *statement* — which means finding the `;`
// that ends it. These call sites span several lines (`showDialog(` with a
// builder, a queued closure), so this walks the source instead of matching a
// line: it counts brackets and steps over string literals and comments.
//
// Usage:  dart run tools/wrap_unawaited.dart <analyze.log> [--apply]
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tools/wrap_unawaited.dart '
        '<flutter-analyze-output> [--apply]');
    exit(2);
  }

  final logPath = args.first;
  final apply = args.contains('--apply');
  final pattern = RegExp(
      r'^\s*(error|warning|info)\s+-\s+.*?\s+-\s+(.+?):(\d+):(\d+)\s+-\s+(\S+)\s*$');

  // file -> sorted set of offsets to wrap
  final targets = <String, Set<int>>{};

  for (final line in File(logPath).readAsLinesSync()) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    final rule = match.group(5);
    if (rule != 'unawaited_futures' && rule != 'discarded_futures') continue;

    final path = match.group(2)!;
    final lineNo = int.parse(match.group(3)!);
    final col = int.parse(match.group(4)!);

    if (!File(path).existsSync()) continue;

    final src = File(path).readAsStringSync();
    final offset = _offsetOf(src, lineNo, col);
    if (offset == null) continue;

    targets.putIfAbsent(path, () => <int>{}).add(offset);
  }

  var changed = 0;
  var skipped = 0;

  for (final entry in targets.entries) {
    final path = entry.key;
    var src = File(path).readAsStringSync();
    final offsets = entry.value.toList()..sort((a, b) => b.compareTo(a));

    for (final offset in offsets) {
      final scanner = _Scanner(src);
      // The diagnostic's column is the *selector* for a member call
      // (`_dcmPngQue.add(…)` reports `add`), so step back to the start of the
      // whole expression before wrapping it.
      final start = _expressionStart(src, offset);
      if (src.substring(start).startsWith('unawaited(')) {
        skipped++;
        continue;
      }
      if (!_safeInsertionPoint(src, start)) {
        stdout.writeln('  SKIP (unsafe context): $path@$offset  '
            '${src.substring(start, _min(start + 60, src.length)).trim()}');
        skipped++;
        continue;
      }
      final end = scanner.statementEnd(start);
      if (end == null) {
        stdout.writeln('  SKIP (no statement end): $path@$offset');
        skipped++;
        continue;
      }

      final statement = src.substring(start, end).trim();
      final wrapped = 'unawaited(${src.substring(start, end)})';
      src = src.substring(0, start) + wrapped + src.substring(end);

      changed++;
      final preview =
          statement.length > 90 ? '${statement.substring(0, 90)}…' : statement;
      stdout.writeln('  $path:  $preview');
    }

    if (apply) File(path).writeAsStringSync(src);
  }

  stdout.writeln('');
  stdout.writeln(apply
      ? 'APPLIED $changed wrap(s); skipped $skipped.'
      : 'DRY RUN: would wrap $changed statement(s); skipped $skipped.');
}

/// 1-based [line]/[col] to a 0-based offset, or null when out of range.
int? _offsetOf(String src, int line, int col) {
  var offset = 0;
  var current = 1;
  while (current < line) {
    final nl = src.indexOf('\n', offset);
    if (nl < 0) return null;
    offset = nl + 1;
    current++;
  }
  final result = offset + col - 1;
  return result < src.length ? result : null;
}

int _min(int a, int b) => a < b ? a : b;

bool _isNameChar(String s, int i) {
  final c = s.codeUnitAt(i);
  return (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F || // _
      c == 0x24; // $
}

/// The start of the expression an offset inside it refers to.
///
/// The diagnostics point at the *selector* of a member call
/// (`_dcmPngQue.add(…)` reports `add`), so this walks back through
/// `receiver.selector` pairs. It gives up — returning [offset] unchanged, which
/// the caller's context guard then rejects — when the receiver is anything
/// other than a plain name (`foo().bar(…)`).
int _expressionStart(String src, int offset) {
  var start = offset;

  while (start > 0) {
    var i = start;
    if (src.codeUnitAt(i - 1) == 0x2E /* . */) {
      i--;
      if (i > 0 && src.codeUnitAt(i - 1) == 0x3F /* ? */) i--; // `?.`
    } else {
      break;
    }

    if (i > 0 && src.codeUnitAt(i - 1) == 0x21 /* ! */) i--; // `x!.`
    final nameEnd = i;
    while (i > 0 && _isNameChar(src, i - 1)) {
      i--;
    }
    if (i == nameEnd) return offset; // receiver is not a plain name
    start = i;
  }

  return start;
}

/// Whether a statement may start at [offset].
///
/// Everything after these characters begins a fresh expression; anything else
/// (`return foo();`, `x = y.foo();`) means the wrapper would not enclose a whole
/// statement, so the site is left for a human.
bool _safeInsertionPoint(String src, int offset) {
  var i = offset;
  while (i > 0) {
    final c = src.codeUnitAt(i - 1);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i--;
      continue;
    }
    // A `//` comment may sit between the previous statement and this one; step
    // over it rather than mistaking its closing punctuation for an operator.
    final lineStart = src.lastIndexOf('\n', i - 1) + 1;
    if (src.substring(lineStart, i).contains('//')) {
      i = lineStart;
      continue;
    }
    return c == 0x3B || // ;
        c == 0x7B || // {
        c == 0x7D || // }
        c == 0x28 || // (
        c == 0x29 || // )
        c == 0x2C || // ,
        c == 0x3A || // :
        c == 0x3E || // >  (arrow body)
        c == 0x3F; // ?   (ternary)
  }
  return true;
}

class _Scanner {
  _Scanner(this.src);

  final String src;

  /// The index of the `;` closing the statement that starts at [start].
  int? statementEnd(int start) {
    var i = start;
    var depth = 0;

    while (i < src.length) {
      final c = src[i];

      if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
        i = _endOfLineComment(i);
        continue;
      }
      if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
        i = _endOfBlockComment(i);
        continue;
      }
      if (c == "'" || c == '"') {
        i = _endOfString(i);
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth++;
        i++;
        continue;
      }
      if (c == ')' || c == ']' || c == '}') {
        depth--;
        i++;
        continue;
      }
      if (c == ';' && depth == 0) return i;
      i++;
    }
    return null;
  }

  int _endOfLineComment(int from) {
    final nl = src.indexOf('\n', from);
    return nl < 0 ? src.length : nl;
  }

  int _endOfBlockComment(int from) {
    var i = from;
    var depth = 0;
    while (i < src.length) {
      if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
        depth++;
        i += 2;
        continue;
      }
      if (src[i] == '*' && i + 1 < src.length && src[i + 1] == '/') {
        depth--;
        i += 2;
        if (depth == 0) return i;
        continue;
      }
      i++;
    }
    return src.length;
  }

  /// The index just past the string literal that opens at [from].
  ///
  /// Interpolations are stepped over with [_endOfInterpolation] so a nested
  /// literal that reuses the outer quote character (`"${map["k"]}"`) does not
  /// end the outer string early.
  int _endOfString(int from) {
    final quote = src[from];
    final raw = from > 0 && (src[from - 1] == 'r' || src[from - 1] == 'R');
    final triple = from + 2 < src.length &&
        src[from + 1] == quote &&
        src[from + 2] == quote;

    var i = from + (triple ? 3 : 1);
    while (i < src.length) {
      if (!raw && src[i] == '\\') {
        i += 2;
        continue;
      }
      if (!raw && src[i] == r'$' && i + 1 < src.length && src[i + 1] == '{') {
        i = _endOfInterpolation(i + 1);
        continue;
      }
      if (triple) {
        if (src[i] == quote &&
            i + 2 < src.length &&
            src[i + 1] == quote &&
            src[i + 2] == quote) {
          return i + 3;
        }
      } else if (src[i] == quote) {
        return i + 1;
      }
      i++;
    }
    return src.length;
  }

  /// The index just past the `}` that closes the interpolation opening at the
  /// `{` at [from].
  int _endOfInterpolation(int from) {
    var i = from + 1;
    var depth = 1;
    while (i < src.length) {
      final c = src[i];
      if (c == "'" || c == '"') {
        i = _endOfString(i);
        continue;
      }
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return src.length;
  }
}
