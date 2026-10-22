import 'dart:ui' show Offset;

import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/core/reactive/observable.dart';

/// Every window floating on its own, in the order they were opened.
///
/// A panel's windows are not here: they belong to its `PanelWorkspace` and leave
/// with it. This is for everything else — a window a table asked for, a scan, a
/// photo — so they can stack beside the app without owning the screen.
abstract final class WindowsManager {
  static final Map<String, FloatingWindow> _open = <String, FloatingWindow>{};

  /// The window the app last asked for, for the layer to bring forward. Cleared
  /// once read, so an unrelated change never re-raises a window the user has
  /// since pushed back.
  static String? _focus;

  /// Not an `ObservableState`: it holds no value, only the news that the set
  /// changed.
  static final ObservableBase<List<FloatingWindow>> _changes =
      ObservableBase<List<FloatingWindow>>();

  /// Emits whenever the set of floating windows changes.
  static Stream<List<FloatingWindow>> get stream => _changes.stream;

  static List<FloatingWindow> open() => _open.values.toList();

  static bool isOpen(FloatingWindow window) => _open.containsKey(window.key);

  /// Shows [window], replacing any window with the same key so a second request
  /// brings the same window forward instead of stacking a duplicate.
  ///
  /// Shows [window], or brings the window it duplicates to the front.
  ///
  /// A window that is already up is moved to the end rather than rebuilt: the
  /// draft it holds is the user's, and asking for the same editor again must not
  /// throw away what has been typed into it. It is also the window to bring
  /// forward, which the layer does from [takeFocus].
  ///
  /// A window with **nothing** typed into it is not the user's: keeping it would
  /// show the record as it was when the window first opened, under the store's
  /// newer copy. Asking for it again is asking for the record now, so the fresh
  /// [window] takes its place.
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

  /// The window to bring in front of the others, once — null when there is no
  /// such request waiting.
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

  /// Closes every window that belongs to [scope] — the record a panel is about
  /// to be opened for, whose windows the panel now holds.
  ///
  /// A window still holding unsaved work is left alone: throwing the work away
  /// to make room for the panel would be worse than having both on screen, and
  /// it is the same rule a phone follows when a panel takes over.
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

  /// The work the windows of [scope] still hold, written over [stored] in the
  /// order they were opened — and those windows put away, the caller carrying
  /// it from here.
  ///
  /// Null when no window of the scope has anything to give. The record handed in
  /// is not changed: the answer is a new map for the caller to build its draft
  /// from.
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

  /// The baselines the windows of [scope] took when they opened, for an owner
  /// that tracks several records by JSON — and those windows put away.
  ///
  /// Null when no window of the scope has anything to give.
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

  /// Shows [window] on its own, with a Close that closes exactly it.
  ///
  /// The usual way to open a window that stands alone: a list or table asked
  /// for it, a record was opened with it, a scan.
  ///
  /// [origin] is where it should appear — the tap that asked for it, by default —
  /// so a window a row asked for comes from that row. [onOpenRecord] gives it
  /// the way back to the panel that holds the record it edits.
  static FloatingWindow showStandalone(
    PanelWindow window, {
    String scope = '',
    Future<void> Function()? onSave,
    bool Function()? hasChanges,
    Future<void> Function()? onOpenRecord,
    Map<String, dynamic> Function(Map<String, dynamic> stored)? transfer,
    Map<String, String> Function()? baselines,
    Offset? origin,
  }) {
    late final FloatingWindow floating;
    floating = FloatingWindow(
      window: window,
      scope: scope,
      origin: origin ?? WindowOrigin.last,
      // A window asked for with no panel behind it is standing on its own over
      // the app, and a phone's panel replaces it.
      root: PanelsManager.active().isEmpty,
      onSave: onSave,
      hasChanges: hasChanges,
      onOpenRecord: onOpenRecord,
      transfer: transfer,
      baselines: baselines,
      onClose: () => close(floating),
    );
    return show(floating);
  }

  /// Shows [focus] on the panel that is already open for a record, and brings
  /// that panel to the front.
  ///
  /// The record's editor is the panel's own: a second one would give the
  /// record two drafts, and whichever was saved last would win. So the panel
  /// is asked for the window the caller wanted, and the work a window of the
  /// record still holds is taken in by it — the panel's draft becomes the
  /// record's one draft, and the panel opens dirty on it.
  ///
  /// The windows of the record that hold nothing are put away: the panel holds
  /// them now. One that still holds work is left alone — it is the user's, and
  /// the panel cannot take it in.
  static void showOnPanel(
    Panel panel, {
    required String scope,
    String? focus,
  }) {
    final carried = adoptWork(scope, panel.draftJson);
    if (carried != null) panel.adoptDraft(carried);
    closeScope(scope);
    if (focus != null && panel.floatingWindows.any((w) => w.id == focus)) {
      panel.workspace.show(focus);
    }
    final index = PanelsManager.active().indexOf(panel);
    if (index > -1) PanelsManager.bringToFront(index);
  }

  static void _notify() => _changes.notifyObservers(open());
}
