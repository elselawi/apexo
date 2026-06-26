import 'package:flutter/services.dart' show rootBundle;

/// Represents a single version entry in the changelog.
class ChangelogVersion {
  final String version;
  final List<String> changes;

  const ChangelogVersion({required this.version, required this.changes});
}

/// Parses CHANGELOG.md without a markdown parser — uses regex to extract
/// version headers and their bullet-point changes.
class ChangelogService {
  static const _changelogAsset = 'CHANGELOG.md';

  String? _rawContent;
  List<ChangelogVersion>? _versions;

  /// Loads and parses the changelog from assets. Safe to call multiple times —
  /// subsequent calls return the cached result.
  Future<List<ChangelogVersion>> load() async {
    if (_versions != null) return _versions!;

    _rawContent ??= await rootBundle.loadString(_changelogAsset);
    _versions = _parse(_rawContent!);
    return _versions!;
  }

  /// Returns the changelog entry for [version], or null if not found.
  Future<ChangelogVersion?> forVersion(String version) async {
    final versions = await load();
    for (final v in versions) {
      if (v.version == version) return v;
    }
    return null;
  }

  /// Returns the changelog entry for the latest version (first in the file).
  Future<ChangelogVersion?> latest() async {
    final versions = await load();
    return versions.isNotEmpty ? versions.first : null;
  }

  // --- Parsing ---

  static final _versionHeaderRE = RegExp(
    r'^###\s*_{3,}([0-9]+\.[0-9]+\.[0-9]+)_{3,}',
    multiLine: true,
  );

  static List<ChangelogVersion> _parse(String md) {
    // Normalize Windows line endings so that $ works correctly in regex below.
    final normalized = md.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final results = <ChangelogVersion>[];

    // Split by version headers
    final matches = _versionHeaderRE.allMatches(normalized).toList();

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final version = match.group(1)!;

      // Everything from this match to the next match (or end of file)
      final start = match.end;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : normalized.length;
      final section = normalized.substring(start, end);

      final changes = _extractBullets(section);
      results.add(ChangelogVersion(version: version, changes: changes));
    }

    return results;
  }

  /// Extracts bullet points from a section. Nested bullets (indented)
  /// are prefixed with a dash so they read naturally in the dialog.
  static List<String> _extractBullets(String section) {
    final bullets = <String>[];
    final lines = section.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Match lines starting with "- " (any indentation)
      final bulletMatch = RegExp(r'^(\s*)-\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        final indent = bulletMatch.group(1)!.length;
        final text = bulletMatch.group(2)!.trim();
        // For nested bullets (indented), add a visual indicator
        if (indent >= 4) {
          bullets.add('    • $text');
        } else {
          bullets.add('• $text');
        }
      }
    }

    return bullets;
  }
}

/// Singleton instance.
final changelog = ChangelogService();
