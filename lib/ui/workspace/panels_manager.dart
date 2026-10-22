import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/core/reactive/observable.dart';

abstract class PanelsManager {
  static final ObservableState<List<Panel>> active = ObservableState([]);

  static final minimize = ObservableState(false);

  /// Shows [panel], or brings the panel it duplicates to the front, and returns
  /// the panel now on screen.
  static Panel open(Panel panel) {
    final foundPanel = active()
        .indexWhere((element) => element.identifier == panel.identifier);
    if (foundPanel > -1) {
      final kept = active()[foundPanel];
      // The caller may have asked for a window this time (a table cell that
      // means "the appointments of this patient"), so honour it on the panel
      // that is already open. The panel's first window is inline, so only a
      // floating one has anything to bring back.
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

  /// The panel already showing [identifier], if there is one.
  ///
  /// The same rule [open] uses, so "is this record's panel already open?" and
  /// "open it" can never disagree — an opener that answered this question
  /// before it built a panel must get the same answer [open] would.
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

  /// Takes the matching panels off the screen, settling each one: a removed
  /// panel will never be saved.
  static void close(String targetToClose) {
    for (final panel in active().toList()) {
      if (_matches(panel, targetToClose)) panel.settle();
    }
    active(active()..removeWhere((p) => _matches(p, targetToClose)));
  }

  /// Closes every panel — logout, and the tests' clean slate. Each is settled.
  static void closeAll() {
    for (final panel in active()) {
      panel.settle();
    }
    minimize(false);
    active([]);
  }

  /// How the caller names a panel: by the record it edits, or by its identifier
  /// while the record is not stored yet.
  static bool _matches(Panel panel, String target) =>
      panel.itemId == target || target == panel.identifier;
}
