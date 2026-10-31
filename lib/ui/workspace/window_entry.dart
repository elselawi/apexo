part of 'windows_layer.dart';

class _WindowEntry {
  const _WindowEntry.standalone(this.floating)
      : window = null,
        group = null;

  const _WindowEntry.hosted(this.window, this.group) : floating = null;

  final FloatingWindow? floating;
  final PanelWindow? window;

  /// The record whose window this is: the panel's own record, or the visit it
  /// carries beside itself.
  final WindowGroup? group;

  /// The window's id inside its record, for minimizing it.
  String get id => window?.id ?? floating?.key ?? '';

  /// What the window is on screen, across records: a patient and a visit both
  /// offer a `gallery`, so the row names each by its group.
  String get key => floating?.key ?? group!.keyOf(window!);

  bool get isHosted => floating == null;

  PanelWindow get model => floating?.window ?? window!;

  /// The record this window edits — the one whose Save it carries.
  WindowRecordSession? get session => group?.session;

  /// The width it is drawn at in an area [available] wide beside a panel
  /// [panelWidth] wide.
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

  /// The column windows live in: beside the panel when one is open, the screen
  /// when none is.
  final WindowBounds bounds;

  /// The height between the top and the bottom, less a margin: the tallest a
  /// window is drawn.
  final double room;

  double get maxHeight => math.max(120.0, room - 16);
}
