import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:fluent_ui/fluent_ui.dart' show Color;

/// Stable row slots. Remembered layouts are keyed by slot, not by record id.
const String kAttachedSlot = 'attached';
const String kHostSlot = 'host';

/// The key a window has in the row: its slot and its own id. A window id is
/// unique within a record, so the slot namespaces records that share the row.
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

  /// The panel for the host group, the record's session for an attached one.
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

  /// Windows left open in this slot; null never chose, an empty list chose none.
  final List<String>? remembered;

  /// The key [window] has in the row.
  String keyOf(PanelWindow window) => rowKey(slot, window.id);
}
