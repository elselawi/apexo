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
    this.saveLabel,
    this.matchesPanelWidth = true,
    this.preferredWidth = 460,
    this.maxHeight = double.infinity,
    this.minHeight = kWindowMinRowHeight,
    this.replacementGroup,
    this.attachedTo,
    this.byDefault = true,
    this.headerActions = const <Widget>[],
    this.footerActions = const <Widget>[],
    this.chipPreview,
  });

  /// The window — or panel — this one is an **attachment** of.
  ///
  /// An attachment is not a row window: it never takes a place beside the panel
  /// and is never a first pick. It is drawn as a chip on the frame it belongs to
  /// (or in the panel's own attachment tray, for [panelAttachment]) and opens its
  /// editor as a side window when the chip is switched on.
  ///
  /// This is how a visit's labwork and photos hang off its band — and off the
  /// post-op card inside its chart, which draws the same tray — and how a
  /// patient's photos and page hang off the patient's panel: everything that is
  /// *about* a record rather than *of* it. Null means the window is a row window.
  final String? attachedTo;

  /// Whether a record with no remembered arrangement opens this window by itself.
  ///
  /// A record's workspace does; a list or a secondary editor does not — it is one
  /// click away, behind its own control (a header button, an attachment chip).
  /// Only row windows are ever first picks; an attachment is never one.
  final bool byDefault;

  /// Buttons the window draws beside its title.
  ///
  /// A chart's way into the record's lists, a report's way to print — the things
  /// that act *on* the record rather than edit it, so they do not compete with
  /// the window's own Save. Built by the feature that owns the window; the host
  /// only places them.
  final List<Widget> headerActions;

  /// Buttons the window draws in its **footer**, in the row with its Save and
  /// Close.
  ///
  /// A window's own delete lives here rather than in the form above it: the
  /// record's actions sit together, and a button that takes the record away is
  /// not one more field to fill in. Built by the feature that owns the window;
  /// the host only places them.
  final List<Widget> footerActions;

  /// What this window's attachment chip shows beside its name, built whenever
  /// the chip is drawn: a gallery's first pictures, whether an order exists.
  ///
  /// Only an attachment draws a chip, so a row window leaves this null — and so
  /// does an attachment with nothing to add, so its chip stays a plain label
  /// rather than a label beside a gap. A builder rather than a widget because
  /// the record it previews is live: a photo uploaded while the tray is on
  /// screen must reach the chip without the record being rebuilt.
  final Widget? Function()? chipPreview;

  /// The [attachedTo] value that means "attached to the panel itself" rather
  /// than to one of its windows — a patient's photos and page.
  static const String panelAttachment = 'panel';

  /// The [attachedTo] value that means "attached to the record's band" — a
  /// visit's labwork and photos, which are reachable from the record's band
  /// whatever its windows are doing. The band draws them in its attachment tray,
  /// and the record's own card (the visit's post-op card) draws the same one.
  static const String bandAttachment = 'band';

  /// Whether this window hangs off something else rather than taking a place in
  /// the row.
  bool get isAttachment => attachedTo != null;

  /// Editors in a group replace content in the same slot without animating
  /// the window's frame again; the editor owns its content transition.
  final String? replacementGroup;

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
  /// **owning session's** own write — one record has one write — and Close puts
  /// the window back in its dock with the draft still there.
  ///
  /// False for a window that only reads (a list of the record's visits) or one
  /// that writes as it goes (a gallery, a page): a Save button there would write
  /// something the window does not show.
  final bool editsRecord;

  /// The localization key for this window's Save, or null for the plain "save".
  ///
  /// A panel may carry two records at once, and a Save that does not say which
  /// record it writes is exactly the misunderstanding this redesign removes:
  /// "Save visit" and "Save patient" are different writes (plan §4.4, §4.5).
  ///
  /// The window does **not** name the session that writes — its group does. Two
  /// owners for one fact is the class of bug this deletes.
  final String? saveLabel;

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
