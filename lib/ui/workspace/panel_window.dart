import 'package:fluent_ui/fluent_ui.dart';

/// The shortest a window can be drawn before its chrome must scroll.
const double kWindowMinRowHeight = 300.0;

/// One editor a panel offers; the panel keeps its first inline and floats the rest.
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

  /// The window or panel this is an attachment of; drawn as a chip on that frame,
  /// never as a row window. Null means a row window.
  final String? attachedTo;

  /// Whether a record with no remembered layout opens this window by default.
  final bool byDefault;

  /// Buttons drawn beside the title, for actions on the record rather than fields.
  final List<Widget> headerActions;

  /// Buttons drawn in the footer beside Save and Close (e.g. a delete).
  final List<Widget> footerActions;

  /// What an attachment's chip shows beside its name, built on each draw so live
  /// record changes reach it. Null for row windows and chips with nothing to add.
  final Widget? Function()? chipPreview;

  /// [attachedTo] for the panel itself, e.g. a patient's photos and page.
  static const String panelAttachment = 'panel';

  /// [attachedTo] for the record's band: drawn in the band's attachment tray and
  /// again on the record's card (a visit's post-op).
  static const String bandAttachment = 'band';

  bool get isAttachment => attachedTo != null;

  /// Editors in a replacement group swap content without re-animating the frame.
  final String? replacementGroup;

  /// Stable name, not an index, so reordering cannot point callers at the wrong editor.
  final String id;

  /// Localization key (translated on draw) or a plain title.
  final String title;

  /// Second line under the title, read on build (a patient's name, a visit's date).
  final String Function()? subtitle;

  final IconData icon;

  /// The editor itself.
  final Widget body;

  /// Content pinned under the body, inside the window's frame.
  final Widget? footer;

  final double padding;

  /// Whether the window can be opened only once the record is saved.
  final bool onlyIfSaved;

  /// Whether the host scrolls the body; false for a self-scrolling body (a list).
  final bool scrollable;

  /// Whether the window edits its record: only then does it get its own Save and
  /// Close, writing through the owning session.
  final bool editsRecord;

  /// Localization key for this window's Save, since two records can be open at
  /// once ("Save visit" vs "Save patient"); null means the plain "save".
  final String? saveLabel;

  /// Defaults to the panel's width; false for windows that need more room.
  final bool matchesPanelWidth;

  /// Width asked for when [matchesPanelWidth] is false.
  final double preferredWidth;

  /// Tallest it grows, so a list does not become a wall of empty space.
  final double maxHeight;

  /// Shortest it stays usable at; below this its body would scroll, so the layout
  /// leaves it in the dock instead. Content-sized windows compute this.
  final double minHeight;
}
