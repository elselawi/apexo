/// Cutting a string by *code units* splits a surrogate pair in half, and half of
/// one is not valid UTF-16: `RenderParagraph` refuses it
/// (`Invalid argument(s): string is not well-formed UTF-16`) and the frame the
/// text was in is lost — with no app frame in the stack, so it reds whatever
/// test happens to be running.
///
/// Every place that shortens user data instead of using `substring` should call
/// this. Two things are worth knowing about it:
///
/// * it counts **code points**, so an emoji is one character, not two;
/// * it does not join grapheme clusters, so a family emoji (`👨‍👩‍👧`) can still
///   lose its tail. That is a cosmetic loss, not a crash — half a surrogate pair
///   is the only thing Flutter's text layer cannot draw.
library;

/// The first [max] code points of [text] (all of it, when it is shorter).
String clipCodePoints(String text, int max) {
  if (max <= 0) return "";
  // The common case: no surrogate pair can straddle `max` when every unit is a
  // whole code point, so `substring` is exact and allocates less.
  if (text.length <= max) return text;
  // `runes.length` is O(n) either way; the `String.fromCharCodes` below is what
  // keeps the cut on a code-point boundary.
  return String.fromCharCodes(text.runes.take(max));
}

/// Whether [text] fits in [max] code points — the "should I clip it at all?"
/// half of [clipCodePoints], which the callers show as `…`.
bool fitsInCodePoints(String text, int max) => text.runes.length <= max;
