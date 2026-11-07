part of 'windows_layer.dart';

class _WindowEntry {
  const _WindowEntry.standalone(this.floating)
      : window = null,
        group = null;

  const _WindowEntry.hosted(this.window, this.group) : floating = null;

  final FloatingWindow? floating;
  final PanelWindow? window;

  /// The record this window belongs to: the panel's own, or the visit it carries.
  final WindowGroup? group;

  /// The window's id inside its record, for minimizing it.
  String get id => window?.id ?? floating?.key ?? '';

  /// The window's identity across records: a patient and a visit both offer
  /// `gallery`, so the group prefixes it.
  String get key => floating?.key ?? group!.keyOf(window!);

  bool get isHosted => floating == null;

  PanelWindow get model => floating?.window ?? window!;

  /// The record this window edits — the one whose Save it carries.
  WindowRecordSession? get session => group?.session;

  double widthIn(double available, double panelWidth) =>
      windowWidth(model, available, panelWidth: panelWidth);
}

final class _AreaMetrics {
  const _AreaMetrics({
    required this.panelWidth,
    required this.bounds,
    required this.room,
  });

  final double panelWidth;

  final WindowBounds bounds;

  final double room;

  double get maxHeight => math.max(120.0, room - 16);
}
