import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Builds a row's controls knowing whether the row's record is open in a panel,
/// and where that panel sits in the stack.
///
/// A row reads this **live**: reading `PanelsManager.active()` while building is
/// not enough, because a row is only rebuilt when its own list changes — so
/// every row whose record was opened kept showing the "open in panel" button
/// long after the panel had been closed.
///
/// [builder] is called with the index of the panel open for [itemId], or `null`
/// when there is none. The index is what "bring it to the front" needs.
class PanelOpenBuilder extends StatelessWidget {
  const PanelOpenBuilder({
    super.key,
    required this.itemId,
    required this.builder,
  });

  /// The record the row is about.
  final String itemId;

  final Widget Function(BuildContext context, int? panelIndex) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Panel>>(
      stream: PanelsManager.active.stream,
      builder: (context, _) {
        final index = PanelsManager.active()
            .indexWhere((panel) => panel.itemId == itemId);
        return builder(context, index == -1 ? null : index);
      },
    );
  }
}

/// The button a row shows in place of its own control while the record is open
/// in a panel: pressing it brings that panel to the front.
class OpenInPanelButton extends StatelessWidget {
  const OpenInPanelButton({super.key, required this.panelIndex});

  final int panelIndex;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(FluentIcons.open_in_new_tab),
      onPressed: () => PanelsManager.bringToFront(panelIndex),
    );
  }
}
