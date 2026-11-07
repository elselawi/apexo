import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/core/reactive/observable.dart';

abstract class PanelsManager {
  static final ObservableState<List<Panel>> active = ObservableState([]);

  static final minimize = ObservableState(false);

  /// Shows [panel], or focuses and returns the already-open panel that duplicates
  /// it.
  static Panel open(Panel panel) {
    final foundPanel = active()
        .indexWhere((element) => element.identifier == panel.identifier);
    if (foundPanel > -1) {
      final kept = active()[foundPanel];
      // The caller may have asked for a window this time; only a floating one can
      // be brought back, because the first window is inline.
      final requested = panel.initialWindow;
      if (requested != null &&
          kept.floatingWindows.any((w) => w.id == requested)) {
        kept.workspace.show(requested);
      }
      bringToFront(foundPanel);
      panel.settle();
      return kept;
    } else {
      active(active()..add(panel));
      minimize(false);
      return panel;
    }
  }

  /// The panel already showing [identifier]. Same rule as [open], so a caller
  /// that asks before building a panel gets the answer [open] would give.
  static Panel? find(String identifier) {
    for (final panel in active()) {
      if (panel.identifier == identifier) return panel;
    }
    return null;
  }

  static void bringToFront(int index) {
    active(active()..add(active().removeAt(index)));
    minimize(false);
  }

  /// Removal is teardown, not detach: the panel settles and its sessions are
  /// released, so nothing it carried is saved; `detachVisits` keeps a draft.
  static void close(String targetToClose) {
    for (final panel in active().toList()) {
      if (_matches(panel, targetToClose)) {
        panel.releaseSessions();
        panel.settle();
      }
    }
    active(active()..removeWhere((p) => _matches(p, targetToClose)));
  }

  /// Closes every panel without asking — logout, and the tests' clean slate.
  /// `CloseAllButton` is the UI path that confirms unsaved work first.
  static void closeAll() {
    for (final panel in active()) {
      panel.releaseSessions();
      panel.settle();
    }
    minimize(false);
    active([]);
  }

  /// Matches by stored record id, or by identifier while the record is new.
  static bool _matches(Panel panel, String target) =>
      panel.itemId == target || target == panel.identifier;
}
