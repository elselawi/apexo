import 'package:fluent_ui/fluent_ui.dart';

/// The shortest a window may be drawn and still be a window: below this its own
/// chrome and its first line of content no longer fit, so it would scroll.
///
/// It is the default for [PanelWindow.minHeight], which a window overrides when
/// its content needs more (the dental chart, a list of visits).
const double kWindowMinRowHeight = 300.0;

/// One editor a panel offers — what used to be a tab.
///
/// The panel keeps its **first** window inline, as its own body, so the panel
/// never becomes a list of buttons with nothing in it. Every window after it is
/// something the panel can float beside itself (`Panel.floatingWindows`), in a
/// card the size of its content.
///
/// A window is not a panel and holds no record: it is a labelled editor with the
/// size it likes to be shown at. The host draws the label, the owner line and
/// the chrome (`WindowShell`), so a window only says what it is, whose it is and
/// what it edits.
///
/// A view-model only — the [Panel] implementations build it; nothing persists
/// through it.
final class PanelWindow {
  const PanelWindow({
    required this.id,
    required this.title,
    required this.icon,
    required this.body,
    this.subtitle,
    this.footer,
    this.padding = 10,
    this.onlyIfSaved = false,
    this.scrollable = true,
    this.editsRecord = false,
    this.matchesPanelWidth = true,
    this.preferredWidth = 460,
    this.maxHeight = double.infinity,
    this.minHeight = kWindowMinRowHeight,
  });

  /// What this window is, for good: a window is named rather than counted, so
  /// adding or reordering one cannot point a caller at the wrong editor.
  final String id;

  /// The window's label as a localization *key*, translated where it is drawn —
  /// so a language switch relabels a window that is already open. A title that
  /// is not a key passes through `txt` unchanged.
  final String title;

  /// A second line under the title, read on build. Lets a window that belongs
  /// to a record say something more specific than its label (a patient's name,
  /// a visit's date).
  final String Function()? subtitle;

  final IconData icon;

  /// The editor itself.
  final Widget body;

  /// Content pinned under the body, inside the window's frame.
  final Widget? footer;

  final double padding;

  /// Whether the window only makes sense once the record exists: a window for
  /// something not stored yet cannot be opened.
  final bool onlyIfSaved;

  /// Whether the host must scroll the body. A body that scrolls itself — a list
  /// with its own scroll view — says `false`.
  final bool scrollable;

  /// Whether this window edits the record it belongs to.
  ///
  /// True gives it its **own Save and Close** in its footer: a window is where
  /// the editing happens, so it is also where saving must be, rather than
  /// sending the user hunting for the panel's bottom bar. The Save is the
  /// panel's own ([Panel.save]) — one record has one write — and Close puts the
  /// window back in the panel's dock with the draft — and whatever else was
  /// typed — still there.
  ///
  /// False for a window that only reads (a list of the record's visits) or one
  /// that writes as it goes (a gallery, a page): a Save button there would write
  /// something the window does not show.
  final bool editsRecord;

  /// Whether this window is drawn at the panel's own width — the default, so a
  /// panel and its windows read as one column of the screen. A window that
  /// genuinely needs more room (the dental chart's arches) sets this to `false`
  /// and asks for [preferredWidth] instead.
  final bool matchesPanelWidth;

  /// The width it asks for when [matchesPanelWidth] is `false`. Floating
  /// windows never take more than the room they are given.
  final double preferredWidth;

  /// The tallest it grows to. A window is as tall as its content; one whose body
  /// fills whatever it is given — a list — says here how much room it actually
  /// wants, so it does not become a wall of empty space. The screen is always the
  /// outer limit.
  final double maxHeight;

  /// The shortest it stays usable at: below this its body has to scroll, which
  /// is the one thing a floating window may not do. `computeWindowsLayout` reads
  /// it before opening the window: a screen with no room to show it whole leaves
  /// it in the dock instead.
  ///
  /// A window whose size depends on its content says so here by computing it
  /// (the visits list: one card per appointment).
  final double minHeight;
}
