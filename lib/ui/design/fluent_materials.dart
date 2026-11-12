import 'package:fluent_ui/fluent_ui.dart';

/// The WinUI material model as plain values.
///
/// A Fluent window is not one flat fill. It is Mica — the desktop wallpaper,
/// blurred and tinted — with translucent layers stacked over it, and every edge
/// is a hairline stroke at a fraction of the foreground rather than a shadow.
/// Those layer, stroke and interaction colours already live in fluent_ui's
/// [ResourceDictionary]; this exposes them next to the pieces it does not have:
/// the Mica base, the acrylic fills and the elevation the OS would otherwise
/// draw.
@immutable
class FluentMaterials {
  const FluentMaterials._(this.brightness);

  factory FluentMaterials.of(BuildContext context) =>
      FluentMaterials.from(FluentTheme.of(context).brightness);

  factory FluentMaterials.from(Brightness brightness) =>
      FluentMaterials._(brightness);

  final Brightness brightness;

  bool get dark => brightness == Brightness.dark;

  ResourceDictionary get resources =>
      dark ? const ResourceDictionary.dark() : const ResourceDictionary.light();

  // ── Mica ─────────────────────────────────────────────────────────────────
  //
  // Only painted when the window cannot sample the desktop itself. The values
  // are the neutral stand-in WinUI falls back to, plus two very soft washes
  // that stand in for a blurred wallpaper's colour bleed.

  Color get micaBase =>
      dark ? const Color(0xFF1A1A1E) : const Color(0xFFF0F0F3);

  Color get micaWashPrimary =>
      dark ? const Color(0x245B9BD5) : const Color(0x2E7A9CC8);

  Color get micaWashSecondary =>
      dark ? const Color(0x1AA67CC8) : const Color(0x1FC9A87A);

  Color get micaTint =>
      dark ? const Color(0xB31E1E22) : const Color(0xCCFAFAFC);

  /// A last, thin layer over the window's own Mica, keeping a warm or busy
  /// wallpaper from tinting the whole app. DWM already blends the wallpaper
  /// down; this only steadies the hue.
  Color get micaVeil =>
      dark ? const Color(0x1A000000) : const Color(0x2EFFFFFF);

  // ── Layers ───────────────────────────────────────────────────────────────

  /// Content that sits on the Mica base: 50% white in light, and its dark
  /// counterpart, so the tint underneath always reads through.
  Color get layer => resources.layerFillColorDefault;

  /// [layer] flattened onto Mica: the same tone, with nothing behind it
  /// reading through. For a surface that covers other content — a panel that
  /// overlays the app bar on a phone — where the translucent layer would show
  /// whatever it covers instead of hiding it.
  Color get layerOpaque => Color.alphaBlend(layer, micaBase);

  Color get card => resources.cardBackgroundFillColorDefault;

  Color get cardSecondary => resources.cardBackgroundFillColorSecondary;

  /// A flyout, dialog or floating window: acrylic, so it is denser than a
  /// layer but never fully opaque.
  Color get acrylic => dark ? const Color(0xF22B2B30) : const Color(0xF2FBFBFC);

  /// The same acrylic with more of the backdrop showing, for bars that should
  /// feel like glass rather than paper.
  Color get acrylicBar =>
      dark ? const Color(0xD92A2A2E) : const Color(0xD9FAFAFC);

  Color get glassTint => dark
      ? const Color.fromARGB(12, 255, 255, 255)
      : const Color.fromARGB(12, 0, 0, 0);

  Color get controlFill => resources.controlFillColorDefault;

  // ── Strokes ──────────────────────────────────────────────────────────────

  /// The 1px edge of a card or control: 6% of the foreground.
  Color get hairline => resources.cardStrokeColorDefault;

  Color get stroke => resources.controlStrokeColorDefault;

  Color get strongStroke => resources.surfaceStrokeColorDefault;

  Color get flyoutStroke => resources.surfaceStrokeColorFlyout;

  Color get divider => resources.dividerStrokeColorDefault;

  // ── Interaction ──────────────────────────────────────────────────────────

  Color get hover => resources.subtleFillColorSecondary;

  Color get pressed => resources.subtleFillColorTertiary;

  Color get selected => resources.controlAltFillColorTertiary;

  Color get accent => dark ? const Color(0xFF60CDFF) : const Color(0xFF0F6CBD);

  Color get textPrimary => resources.textFillColorPrimary;

  Color get textSecondary => resources.textFillColorSecondary;

  Color get textTertiary => resources.textFillColorTertiary;

  // ── Shape & elevation ────────────────────────────────────────────────────

  static const double radiusControl = 4;

  /// Cards, layers and windows — the Windows 11 corner.
  static const double radiusSurface = 8;

  /// Dialogs and flyouts.
  static const double radiusOverlay = 8;

  static const double hairlineWidth = 1;

  /// The soft theme shadow WinUI draws under a flyout or a raised window.
  List<BoxShadow> get overlayShadow => [
        BoxShadow(
          color: dark ? const Color(0x66000000) : const Color(0x24000000),
          offset: const Offset(0, 8),
          blurRadius: 24,
          spreadRadius: -4,
        ),
        BoxShadow(
          color: dark ? const Color(0x4D000000) : const Color(0x14000000),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
      ];

  /// A floated window has to read as closer than the content behind it.
  List<BoxShadow> get windowShadow => [
        BoxShadow(
          color: dark ? const Color(0x7A000000) : const Color(0x2E000000),
          offset: const Offset(0, 12),
          blurRadius: 32,
          spreadRadius: -6,
        ),
        BoxShadow(
          color: dark ? const Color(0x3D000000) : const Color(0x0F000000),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
      ];

  List<BoxShadow> get windowShadowInactive => [
        BoxShadow(
          color: dark ? const Color(0x59000000) : const Color(0x1A000000),
          offset: const Offset(0, 0),
          blurRadius: 18,
          spreadRadius: -6,
        ),
      ];

  static BorderRadius get controlRadius => BorderRadius.circular(radiusControl);

  static BorderRadius get surfaceRadius => BorderRadius.circular(radiusSurface);

  static BorderRadius get overlayRadius => BorderRadius.circular(radiusOverlay);
}
