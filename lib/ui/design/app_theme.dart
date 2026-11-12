import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Segoe UI Variable is the Windows 11 text face. The fallbacks are the closest
/// equivalents on the platforms that do not ship it; Flutter skips a family it
/// cannot resolve.
const _textFamily = 'Segoe UI Variable Text';
const _textFallback = <String>[
  'Segoe UI Variable',
  'Segoe UI',
  'SF Pro Text',
  'Segoe UI Variable Display',
  'Roboto',
  'Noto Sans',
];

/// The app's single theme.
///
/// Everything that makes the app read as WinUI rather than as a Material app
/// with square corners is set here: the accent ramp, WinUI's translucent
/// control fills, the 8px overlay corner, the type ramp, a pane that shows the
/// Mica behind it, and secondary text that is actually secondary.
FluentThemeData appTheme({required Brightness brightness}) {
  final materials = FluentMaterials.from(brightness);
  final resources = materials.resources;
  final typography = _typography(brightness, resources);

  return FluentThemeData(
    brightness: brightness,
    typography: typography,
    accentColor: _accent(materials),
    // Fluent draws its own surfaces at every level; a page-wide fill would
    // cover the Mica the window is made of.
    scaffoldBackgroundColor: Colors.transparent,
    micaBackgroundColor: Colors.transparent,
    acrylicBackgroundColor: materials.acrylic,
    acrylicFallbackColor: materials.acrylic,
    acrylicTintOpacity: 0.55,
    acrylicLuminosityOpacity: materials.dark ? 0.92 : 0.88,
    menuColor: materials.acrylic,
    cardColor: materials.card,
    inactiveColor: resources.textFillColorSecondary,
    shadowColor: Colors.black,
    selectionColor: materials.accent.withValues(alpha: 0.3),
    iconTheme: IconThemeData(color: resources.textFillColorPrimary, size: 18),
    navigationPaneTheme: _paneTheme(materials, typography),
    scrollbarTheme: ScrollbarThemeData(
      thickness: 3,
      hoveringThickness: 12,
      backgroundColor: Colors.transparent,
      scrollbarColor:
          materials.dark ? const Color(0x59FFFFFF) : const Color(0x59000000),
      scrollbarPressingColor: materials.accent,
      radius: const Radius.circular(99),
      hoveringRadius: const Radius.circular(4),
    ),
    dialogTheme: ContentDialogThemeData(
      decoration: BoxDecoration(
        color: materials.acrylic,
        borderRadius: FluentMaterials.overlayRadius,
        border: Border.all(
          color: materials.flyoutStroke,
          width: FluentMaterials.hairlineWidth,
        ),
        boxShadow: materials.overlayShadow,
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      titleStyle: typography.subtitle?.copyWith(fontWeight: FontWeight.w600),
      bodyStyle: typography.body,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color:
            materials.dark ? const Color(0xFF2B2B30) : const Color(0xFAF9F9FB),
        borderRadius: FluentMaterials.controlRadius,
        border: Border.all(
          color: materials.flyoutStroke,
          width: FluentMaterials.hairlineWidth,
        ),
        boxShadow: materials.overlayShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      textStyle: typography.caption?.copyWith(
        color: resources.textFillColorPrimary,
      ),
    ),
  );
}

/// The accent ramp. Light keeps a mid blue so white sits on it; dark uses the
/// pale WinUI accent, which is paired with black text by the resource
/// dictionary.
AccentColor _accent(FluentMaterials materials) {
  final normal = materials.accent;
  return AccentColor.swatch({
    'darkest': Color.alphaBlend(Colors.black.withValues(alpha: 0.55), normal),
    'darker': Color.alphaBlend(Colors.black.withValues(alpha: 0.35), normal),
    'dark': Color.alphaBlend(Colors.black.withValues(alpha: 0.18), normal),
    'normal': normal,
    'light': Color.alphaBlend(Colors.white.withValues(alpha: 0.18), normal),
    'lighter': Color.alphaBlend(Colors.white.withValues(alpha: 0.42), normal),
    'lightest': Color.alphaBlend(Colors.white.withValues(alpha: 0.66), normal),
  });
}

Typography _typography(Brightness brightness, ResourceDictionary resources) {
  final base = Typography.fromBrightness(
    brightness: brightness,
    color: resources.textFillColorPrimary,
  );
  TextStyle? withFace(TextStyle? style) => style?.copyWith(
        fontFamily: _textFamily,
        fontFamilyFallback: _textFallback,
      );
  return Typography.raw(
    display: withFace(base.display),
    titleLarge: withFace(base.titleLarge),
    title: withFace(base.title),
    subtitle: withFace(base.subtitle),
    bodyLarge: withFace(base.bodyLarge),
    bodyStrong: withFace(base.bodyStrong),
    body: withFace(base.body),
    caption: withFace(base.caption),
  );
}

NavigationPaneThemeData _paneTheme(
  FluentMaterials materials,
  Typography typography,
) {
  final resources = materials.resources;
  return NavigationPaneThemeData(
    // The pane is glass: Mica shows through, and only the tiles have a fill.
    backgroundColor: Colors.transparent,
    overlayBackgroundColor: materials.acrylicBar,
    highlightColor: materials.accent,
    tileColor: WidgetStateProperty.resolveWith((states) {
      if (states.isPressed) return materials.pressed;
      if (states.isHovered) return materials.hover;
      return Colors.transparent;
    }),
    selectedTextStyle: WidgetStatePropertyAll(
      typography.body?.copyWith(
        color: resources.textFillColorPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
    unselectedTextStyle: WidgetStatePropertyAll(
      typography.body?.copyWith(color: resources.textFillColorPrimary),
    ),
    selectedIconColor: WidgetStatePropertyAll(resources.textFillColorPrimary),
    unselectedIconColor: WidgetStatePropertyAll(
      resources.textFillColorSecondary,
    ),
    itemHeaderTextStyle: typography.caption?.copyWith(
      color: resources.textFillColorSecondary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    headerPadding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
    iconPadding: const EdgeInsetsDirectional.only(start: 12, end: 12),
    labelPadding: const EdgeInsetsDirectional.only(end: 12),
  );
}
