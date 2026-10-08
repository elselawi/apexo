import 'package:apexo/app/panels/panel.dart';
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
      kept.selectedTab(panel.selectedTab());
      bringToFront(foundPanel);
      panel.settle();
      return kept;
    } else {
      active(active()..add(panel));
      minimize(false);
      return panel;
    }
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
