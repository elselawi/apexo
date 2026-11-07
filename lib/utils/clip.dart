/// Clips on code-point boundaries: a cut by code units can split a surrogate
/// pair, which Flutter's text layer rejects ("string is not well-formed UTF-16").
/// Grapheme clusters (a family emoji) may still lose their tail — cosmetic only.
library;

/// The first [max] code points of [text] (all of it, when it is shorter).
String clipCodePoints(String text, int max) {
  if (max <= 0) return "";
  if (text.length <= max) return text;
  return String.fromCharCodes(text.runes.take(max));
}

bool fitsInCodePoints(String text, int max) => text.runes.length <= max;
