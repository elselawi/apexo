import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:fluent_ui/fluent_ui.dart' show Color;

/// The two slots a panel's row can hold.
///
/// A **slot** is stable for the life of the app and is what a remembered layout
/// is keyed by (`kind/slot`); a group's **id** names one record and is only ever
/// used for identity. Conflating the two is what would make the remembered
/// layout per-visit (plan §6.2-4).
const String kAttachedSlot = 'attached';
const String kHostSlot = 'host';

/// The key a window has in the row: its slot and its own id.
///
/// A window's [PanelWindow.id] is unique inside its record, not across records —
/// a patient and a visit both offer a `gallery` — so the row, which draws both,
/// names them by slot as well. Two groups never share a slot.
String rowKey(String slot, String windowId) => '$slot/$windowId';

/// The slot `key` says, for a key that names a window in the row.
String slotOfRowKey(String key) {
  final slash = key.indexOf('/');
  return slash < 0 ? kHostSlot : key.substring(0, slash);
}

/// The window id `key` says, for a key that names a window in the row.
String windowIdOfRowKey(String key) {
  final slash = key.indexOf('/');
  return slash < 0 ? key : key.substring(slash + 1);
}

/// One record's windows, as one block of the row.
///
/// A patient panel draws two groups: its own record (the **host**), and the
/// visit it carries beside itself (the **attached** one). They are laid out
/// together and told apart by [slot], [label] and [accent] — the row is one row,
/// and a window in it always says whose it is (plan §3).
final class WindowGroup {
  const WindowGroup({
    required this.slot,
    required this.id,
    required this.session,
    required this.windows,
    required this.label,
    required this.kind,
    this.accent,
    this.glyph,
    this.remembered,
  });

  /// Which block of the row this is: [kAttachedSlot] or [kHostSlot].
  final String slot;

  /// The record this group is about, e.g. `patient:<id>` — identity only.
  final String id;

  /// The record's owner: the panel for the host group, the record's session for
  /// an attached one.
  final WindowRecordSession session;

  /// The windows the record offers, in its own priority order.
  final List<PanelWindow> windows;

  /// Whose block this is, read on build: a renamed patient relabels their dock.
  final String Function() label;

  /// The record's kind, for the layout preferences — `patient`, `appointment`.
  final String kind;

  /// The colour the kind is known by.
  final Color? accent;

  /// The glyph that marks the kind — 📅 for a visit, 👤 for a patient.
  final String? glyph;

  /// The windows the user left open in this slot, or null when they never did.
  /// An empty list is a choice: the group opens nothing by itself.
  final List<String>? remembered;

  /// The key [window] has in the row.
  String keyOf(PanelWindow window) => rowKey(slot, window.id);
}
