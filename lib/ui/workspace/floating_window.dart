import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

/// A window the app floats without its panel: [PanelWindow] says what to draw,
/// and [onSave]/[onClose] stand in for the panel. No [onSave] means no Save.
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
    this.recordSession,
  });

  final PanelWindow window;

  /// The shared draft owner; workspace close counts and saves it once, not once
  /// per editor.
  final WindowRecordSession? recordSession;

  /// The record it belongs to (`patient:<id>`, `appointment:<id>`). Windows of
  /// one record are replaced, not duplicated.
  final String scope;

  final Offset? origin;

  /// Opened with no panel behind it. On a phone a panel takes the whole screen,
  /// so a root window steps aside when one opens.
  final bool root;

  /// Writes the window's draft; null for a read-only window (a list, a scan).
  final Future<void> Function()? onSave;

  final VoidCallback? onClose;

  /// Unsaved-work check for the Close confirmation; only asked when [canSave].
  final bool Function()? hasChanges;

  /// Opens the panel holding this window's record and makes way for it; null
  /// when no record is behind the window. The card confirms [hasChanges] first.
  final Future<void> Function()? onOpenRecord;

  /// Whether this window brings its own Save and Close.
  bool get standalone => onClose != null;
  bool get canSave => onSave != null;

  /// Whether it has work to hand to the record's panel: a single-record
  /// [transfer], or multi-record [baselines].
  bool get canAdopt => transfer != null || baselines != null;

  /// The window's work as a merge over the stored JSON. A panel opening over the
  /// window adopts it, starts dirty on it, and does the only write.
  final Map<String, dynamic> Function(Map<String, dynamic> stored)? transfer;

  /// Each record's JSON as the window found it, for an owner that tracks several
  /// records by JSON — the orders panel, whose write is a list of orders.
  final Map<String, String> Function()? baselines;

  /// Identity: one window per editor per record.
  String get key => '$scope#${window.id}';
}
