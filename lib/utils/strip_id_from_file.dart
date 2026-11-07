/// pocketbase-specific function to strip the id from the file name
String stripIDFromFileName(String fileName) {
  final RegExp identifierPattern = RegExp(r'_[a-zA-Z0-9]+(?=\.[^.]+$)');
  return fileName.replaceAll(identifierPattern, '');
}

/// One PocketBase suffix: `_` plus at least six alphanumerics before a dot, in a
/// name that may contain several dots.
final RegExp _storedFileSuffix = RegExp(r'_[A-Za-z0-9]{6,}(?=\.)');

/// [name] with one PocketBase suffix removed, or null when it has none. The
/// suffix can precede any dot: a preview is `x_ab12cd34ef_0cizfojiej.dcm.png`.
String? withoutStoredFileSuffix(String name) {
  final match = _storedFileSuffix.firstMatch(name);
  return match == null ? null : name.replaceRange(match.start, match.end, '');
}

/// Whether [a] and [b] name the same stored file once PocketBase's random suffix
/// is stripped from either side; the token is ambiguous with real name parts
/// (`report_20240101.pdf`), so callers must try an exact match first.
bool sameStoredFileName(String a, String b) {
  if (a == b) return true;
  final strippedA = withoutStoredFileSuffix(a);
  final strippedB = withoutStoredFileSuffix(b);
  if (strippedB != null && strippedB == a) return true;
  if (strippedA != null && strippedA == b) return true;
  return false;
}
