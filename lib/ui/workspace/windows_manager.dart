import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/core/reactive/observable.dart';

/// Every standalone floating window, in the order opened. A panel's windows are
/// not here: `PanelWorkspace` owns them and they leave with it.
abstract final class WindowsManager {
  static final Map<String, FloatingWindow> _open = <String, FloatingWindow>{};

  /// Window the layer should bring forward next; [takeFocus] clears it so an
  /// unrelated change never re-raises a window the user pushed back.
  static String? _focus;

  /// Not an `ObservableState`: it holds no value, only the news that the set changed.
  static final ObservableBase<List<FloatingWindow>> _changes =
      ObservableBase<List<FloatingWindow>>();

  /// Emits whenever the set of floating windows changes.
  static Stream<List<FloatingWindow>> get stream => _changes.stream;

  static List<FloatingWindow> open() => _open.values.toList();

  static bool isOpen(FloatingWindow window) => _open.containsKey(window.key);

  /// Shows [window], or moves the open window with the same key to the front. A
  /// window holding unsaved work keeps its draft; an untouched one is replaced.
  static FloatingWindow show(FloatingWindow window) {
    final existing = _open.remove(window.key);
    final shown = existing != null && (existing.hasChanges?.call() ?? false)
        ? existing
        : window;
    _open[window.key] = shown;
    _focus = shown.key;
    _notify();
    return shown;
  }

  /// Dismisses the sheet a phone is showing; null on a wide screen.
  static bool Function()? dismissSheet;

  static String? takeFocus() {
    final focus = _focus;
    _focus = null;
    return focus;
  }

  static void close(FloatingWindow window) {
    final removed = _open.remove(window.key) != null;
    if (_focus == window.key) _focus = null;
    if (removed) _notify();
  }

  /// Closes the windows of [scope]. A window still holding unsaved work is left
  /// alone rather than thrown away.
  static void closeScope(String scope) {
    if (scope.isEmpty) return;
    final before = _open.length;
    _open.removeWhere((_, window) =>
        window.scope == scope && !(window.hasChanges?.call() ?? false));
    // A window that is gone cannot be the one to bring forward.
    if (_focus != null && !_open.containsKey(_focus)) _focus = null;
    if (_open.length != before) _notify();
  }

  static void closeAll() {
    _focus = null;
    if (_open.isEmpty) return;
    _open.clear();
    _notify();
  }

  /// Merges the unsaved work of [scope]'s windows over [stored], in the order they
  /// opened, and closes them; [stored] itself is not changed. Null when none.
  static Map<String, dynamic>? adoptWork(
    String scope,
    Map<String, dynamic> stored,
  ) {
    if (scope.isEmpty) return null;
    Map<String, dynamic>? merged;
    final adopted = <FloatingWindow>[];
    for (final window in _open.values.toList()) {
      final transfer = window.transfer;
      if (window.scope != scope || transfer == null) continue;
      if (!(window.hasChanges?.call() ?? false)) continue;
      merged = transfer(merged ?? stored);
      adopted.add(window);
    }
    for (final window in adopted) {
      close(window);
    }
    return merged;
  }

  /// Merges the baselines of [scope]'s windows and closes them; null when none.
  static Map<String, String>? adoptBaselines(String scope) {
    if (scope.isEmpty) return null;
    Map<String, String>? merged;
    final adopted = <FloatingWindow>[];
    for (final window in _open.values.toList()) {
      final baselines = window.baselines;
      if (window.scope != scope || baselines == null) continue;
      if (!(window.hasChanges?.call() ?? false)) continue;
      merged = {...?merged, ...baselines()};
      adopted.add(window);
    }
    for (final window in adopted) {
      close(window);
    }
    return merged;
  }

  /// Shows [window] standing on its own, with a Close that closes exactly it;
  /// [origin] defaults to the last tap, so it appears where it was asked for.
  static FloatingWindow showStandalone(
    PanelWindow window, {
    String scope = '',
    Future<void> Function()? onSave,
    bool Function()? hasChanges,
    Future<void> Function()? onOpenRecord,
    Map<String, dynamic> Function(Map<String, dynamic> stored)? transfer,
    Map<String, String> Function()? baselines,
    WindowRecordSession? recordSession,
    Offset? origin,
  }) {
    late final FloatingWindow floating;
    floating = FloatingWindow(
      window: window,
      scope: scope,
      origin: origin ?? WindowOrigin.last,
      // No panel behind it: it stands over the app, and a phone's panel replaces it.
      root: PanelsManager.active().isEmpty,
      onSave: onSave,
      hasChanges: hasChanges,
      onOpenRecord: onOpenRecord,
      transfer: transfer,
      baselines: baselines,
      recordSession: recordSession,
      onClose: () => close(floating),
    );
    return show(floating);
  }

  /// Shows [focus] on [panel] and brings it forward. The panel is the record's
  /// only draft, so the windows' work is adopted before they are closed.
  static void showOnPanel(
    Panel panel, {
    required String scope,
    String? focus,
  }) {
    final carried = adoptWork(scope, panel.draftJson);
    if (carried != null) panel.adoptDraft(carried);
    closeScope(scope);
    if (focus != null && panel.floatingWindows.any((w) => w.id == focus)) {
      // Force the named window into the plan so the panel does not dock it again.
      panel.showWindow(focus);
    }
    final index = PanelsManager.active().indexOf(panel);
    if (index > -1) PanelsManager.bringToFront(index);
  }

  static void _notify() => _changes.notifyObservers(open());
}
