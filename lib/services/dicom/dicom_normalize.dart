// Normalizes sensor-written names (`SMITH^JOHN`, `Dr John Smith`) into a token
// set for patient matching: separators to spaces, honorifics stripped, Arabic
// normalized, lowercased.

final _separators = RegExp(r'[\^,\.;:]');
final _multiSpace = RegExp(r'\s+');

/// Honorifics stripped as whole tokens (Latin and Arabic), avoiding `\b` issues.
const _honorifics = {
  'dr',
  'mr',
  'mrs',
  'ms',
  'prof',
  'د',
  'استاذ',
  'الاستاذ',
};

/// Lowercase token set; order-insensitive.
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

/// Jaccard similarity over the token sets: 1.0 identical, 0.0 no overlap.
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
