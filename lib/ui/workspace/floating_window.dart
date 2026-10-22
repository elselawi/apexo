import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

/// A window the app floats on its own — a panel's window shown without its
/// panel, or one that belongs to no panel at all (a scan, a photo).
///
/// A [PanelWindow] says what to draw; this adds the half a panel would otherwise
/// provide: [onSave] and [onClose]. A window opened *for* a record the panel
/// would have saved carries both; a window that is only looked at carries
/// [onClose] alone, and that is what decides whether its card shows a Save
/// button.
final class FloatingWindow {
  const FloatingWindow({
    required this.window,
    this.scope = '',
    this.origin,
    this.root = false,
    this.onSave,
    this.onClose,
    this.hasChanges,
    this.onOpenRecord,
    this.transfer,
    this.baselines,
  });

  final PanelWindow window;

  /// The record this window belongs to (`patient:<id>`, `appointment:<id>`).
  /// Windows of one record are replaced, not duplicated, and opening a record's
  /// panel closes the windows the panel itself now holds.
  final String scope;

  /// Where on the screen it was asked for: the tap that opened it. The layer
  /// puts it there rather than at the panel's side of the screen.
  final Offset? origin;

  /// Whether it was opened while the app had no panel — a list standing on its
  /// own, say. On a phone a panel takes the whole screen, so a window like this
  /// steps aside when one opens: it is what the panel replaced.
  final bool root;

  /// Writes the draft the window edits. Null for a window that reads rather than
  /// writes — a list, a scan, a photo.
  final Future<void> Function()? onSave;

  final VoidCallback? onClose;

  /// Whether the draft has unsaved work, for the Close confirmation. Only asked
  /// of a window that can save.
  final bool Function()? hasChanges;

  /// Opens the record this window belongs to — the panel that holds it — and
  /// makes way for it. Null for a window with no record behind it: a photo, a
  /// scan the user picked from a file, a list of everything.
  ///
  /// The card asks [hasChanges] first: leaving a window for its panel must not
  /// be a way to lose what was typed into it.
  final Future<void> Function()? onOpenRecord;

  /// Whether this window brings its own Save and Close.
  bool get standalone => onClose != null;
  bool get canSave => onSave != null;

  /// Whether this window can hand its work to the record's panel: it has the
  /// merge the panel would adopt.
  ///
  /// A window that only reads has nothing to hand over, and neither has one
  /// whose owner tracks several records — that one hands over its
  /// [baselines] instead, which the panel takes in the same way.
  bool get canAdopt => transfer != null || baselines != null;

  /// The work this window holds, written over the record as it is stored — the
  /// same merge its own Save would do.
  ///
  /// A panel that opens over the window takes this instead of leaving two drafts
  /// of one record on screen: the panel carries the work, starts dirty on it,
  /// and its own Save is the only write. Null for a window with nothing to
  /// merge — one that only reads, or one whose owner tracks several records
  /// ([baselines] is its shape of the same idea).
  final Map<String, dynamic> Function(Map<String, dynamic> stored)? transfer;

  /// Each record's JSON as this window found it, for an owner that tracks
  /// several records by JSON rather than one model — the orders panel, whose
  /// write is a list of orders.
  final Map<String, String> Function()? baselines;

  /// Identity: one window per editor per record.
  String get key => '$scope#${window.id}';
}
