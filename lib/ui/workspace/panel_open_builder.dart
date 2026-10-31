import 'package:apexo/core/multi_stream_builder.dart';
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
    this.carries,
  });

  /// The record the row is about.
  final String itemId;

  /// Whether [panel] is showing [itemId] as a record it **carries**, not as the
  /// one it edits — a visit attached to its patient's panel.
  ///
  /// A visit does not become a panel, so "is this visit open?" is no longer a
  /// question about `panel.itemId`; it is a question about what the open panels
  /// are carrying (plan §7.2). Null for a row whose record is always a panel.
  final bool Function(Panel panel)? carries;

  final Widget Function(BuildContext context, int? panelIndex) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Panel>>(
      stream: PanelsManager.active.stream,
      builder: (context, _) => MStreamBuilder(
        streams: [
          if (carries != null)
            for (final panel in PanelsManager.active()) panel.attachments.stream,
        ],
        builder: (context, _) {
          final index = PanelsManager.active().indexWhere((panel) =>
              panel.itemId == itemId || (carries?.call(panel) ?? false));
          return builder(context, index == -1 ? null : index);
        },
      ),
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
