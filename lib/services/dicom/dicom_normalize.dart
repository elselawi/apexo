// Aggressive name normalization for DICOM ↔ Apexo patient matching.
//
// Dental sensors store patient names in many forms:
//   `SMITH^JOHN`  ·  `Smith, John`  ·  `JOHN A SMITH`  ·  `Dr John Smith`
//
// This normalizer reduces all of these to the same token set by:
//   1. Replacing `^`, `,`, `.`, `;`, `:` with space.
//   2. Collapsing multiple spaces.
//   3. Stripping honorifics (`Dr`, `Mr`, `Mrs`, `Ms`, `Prof`, Arabic `د.`
//      / `د` / `استاذ` / `الاستاذ`).
//   4. Lowercasing (case-folding explicit).
//   5. Applying Arabic normalization (`أ|إ → ا`) — mirrors the existing
//      `Patient.searchString` normalization in the codebase.
//   6. Tokenizing on whitespace → `Set<String>`.

final _separators = RegExp(r'[\^,\.;:]');
final _multiSpace = RegExp(r'\s+');

/// Honorifics to strip (lowercase). Includes Latin (`dr`, `mr`, etc.) and
/// Arabic (`د`, `استاذ`, `الاستاذ`). Matched as whole tokens after
/// tokenization — avoids `\b` word-boundary issues with Arabic characters.
const _honorifics = {
  'dr',
  'mr',
  'mrs',
  'ms',
  'prof',
  'د',
  'ا',
  'أ',
  '.د',
  '.ا',
  '.أ',
  'استاذ',
  'الاستاذ',
};

/// Normalizes a raw patient name string into a set of lowercase tokens.
///
/// Order-insensitive — `"Smith^John"` and `"John Smith"` produce the same
/// set `{"john", "smith"}`.
Set<String> nameTokens(String raw) {
  // 1. Replace DICOM/punctuation separators with space.
  var s = raw.replaceAll(_separators, ' ');
  // 2. Collapse multiple spaces + trim.
  s = s.replaceAll(_multiSpace, ' ').trim();
  // 3. Lowercase (explicit case-folding).
  s = s.toLowerCase();
  // 4. Arabic normalization — mirrors Patient.searchString.
  s = s.replaceAll(RegExp('أ|إ'), 'ا');
  // 5. Tokenize on whitespace.
  final tokens = s.split(' ').where((t) => t.isNotEmpty).toSet();
  // 6. Strip honorifics (token-level — avoids \b issues with Arabic).
  tokens.removeAll(_honorifics);
  return tokens;
}

/// Jaccard similarity (0.0–1.0) over the token sets of two names.
///
/// `|A ∩ B| / |A ∪ B|` — 1.0 means identical token sets, 0.0 means no
/// shared tokens. Order-insensitive.
double nameSimilarity(String dicomName, String apexoName) {
  final a = nameTokens(dicomName);
  final b = nameTokens(apexoName);
  if (a.isEmpty && b.isEmpty) return 1.0; // both empty = match
  if (a.isEmpty || b.isEmpty) return 0.0; // one empty = no match

  final intersection = a.intersection(b).length;
  final union = a.union(b).length;
  if (union == 0) return 0.0;
  return intersection / union;
}
