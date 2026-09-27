import 'package:fluent_ui/fluent_ui.dart';

/// One tab of a panel: the label and icon in the tab strip, the editor [body],
/// and an optional [footer] pinned beneath it.
///
/// A view-model only — it holds no record and no persistence policy. The host
/// (`panel_screen.dart`) draws it; the [Panel] implementations build it.
final class PanelTab {
  PanelTab({
    required this.title,
    required this.icon,
    required this.body,
    this.footer,
    this.onlyIfSaved = false,
    this.padding = 10,
  });

  /// The tab's label as a localization *key*, translated by the host when it
  /// draws the tab — so a language switch relabels a panel that is already open.
  /// A title that is not a key passes through `txt` unchanged, so a caller may
  /// hand in a real name.
  final String title;
  final IconData icon;
  final Widget body;
  final double padding;
  final bool onlyIfSaved;
  final Widget? footer;
}
