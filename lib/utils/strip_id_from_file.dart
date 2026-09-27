/// pocketbase-specific function to strip the id from the file name
String stripIDFromFileName(String fileName) {
  final RegExp identifierPattern = RegExp(r'_[a-zA-Z0-9]+(?=\.[^.]+$)');
  return fileName.replaceAll(identifierPattern, '');
}

/// One PocketBase suffix: `_` plus at least six alphanumerics immediately
/// before a `.` — the last extension for a normal upload, the first dot of the
/// extension chain for a compound name.
final RegExp _storedFileSuffix = RegExp(r'_[A-Za-z0-9]{6,}(?=\.)');

/// [name] with one PocketBase suffix taken off, or `null` when it has none.
///
/// Unlike [stripIDFromFileName] this looks for the suffix before **any** dot,
/// not only before the final extension, because a preview is named after the
/// original's *suffixed* name: `x_ab12cd34ef.dcm` is uploaded as
/// `x_ab12cd34ef.dcm.png` and PocketBase suffixes it again, giving
/// `x_ab12cd34ef_0cizfojiej.dcm.png` — the second suffix sits before `.dcm`,
/// not before `.png`.
String? withoutStoredFileSuffix(String name) {
  final match = _storedFileSuffix.firstMatch(name);
  return match == null ? null : name.replaceRange(match.start, match.end, '');
}

/// Whether [a] and [b] name the same stored file, allowing for the random
/// suffix PocketBase appends.
///
/// PocketBase never keeps the name a file was uploaded under: it inserts random
/// characters before the extension (`xray.jpg` → `xray_ab12cd34ef.jpg`). A
/// record's filename column can therefore hold *either* spelling of the same
/// file — the name from before the upload was reported back, or PocketBase's —
/// so comparing two names by equality alone declares a file that is right there
/// to be missing, and the image cannot be read or drawn at all.
///
/// One suffix is taken off either side before comparing, which covers a plain
/// upload and the doubly-suffixed preview above.
///
/// The rule cannot tell PocketBase's random token from a name part that merely
/// looks like one (`report_20240101.pdf`), so a caller must match exactly first
/// and treat this as the fallback — which is what the attachment module does,
/// and the convention [stripIDFromFileName] already applies to display names.
bool sameStoredFileName(String a, String b) {
  if (a == b) return true;
  final strippedA = withoutStoredFileSuffix(a);
  final strippedB = withoutStoredFileSuffix(b);
  if (strippedB != null && strippedB == a) return true;
  if (strippedA != null && strippedA == b) return true;
  return strippedA != null && strippedA == strippedB;
}
