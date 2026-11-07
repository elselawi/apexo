import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Builds a row's controls with the index of the panel open for [itemId]. A row
/// does not rebuild on panel changes, so this listens to the panel streams.
class PanelOpenBuilder extends StatelessWidget {
  const PanelOpenBuilder({
    super.key,
    required this.itemId,
    required this.builder,
    this.carries,
  });

  /// The record the row is about.
  final String itemId;

  /// Whether [panel] carries [itemId] rather than editing it — a visit attached
  /// to its patient's panel. Null for a row whose record is always a panel.
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
