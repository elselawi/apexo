import 'dart:async';

import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Builds the items of a context menu. Reuse [controller] for follow-up
/// flyouts so they anchor to the same row.
typedef ContextMenuItemsBuilder = List<MenuFlyoutItemBase> Function(
  BuildContext context,
  FlyoutController controller,
);

/// Opens a context menu on long press or right click, anchored at the pointer;
/// on web the browser's own menu is disabled, so right click opens this too.
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.items,
    required this.child,
    this.longPress = true,
  });

  final ContextMenuItemsBuilder items;
  final Widget child;

  /// Whether long press opens the menu too. False where the child needs that
  /// gesture itself (a chip dragged by long press), leaving right click.
  final bool longPress;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final FlyoutController controller = FlyoutController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> open(Offset position, {bool withFeedback = false}) async {
    if (withFeedback) unawaited(Feedback.forLongPress(context));
    await flyoutFocusFix(context);
    if (!mounted) return;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    unawaited(controller.showFlyout<void>(
      position: position,
      autoModeConfiguration: FlyoutAutoConfiguration(
        preferredMode: isRtl
            ? FlyoutPlacementMode.bottomRight
            : FlyoutPlacementMode.bottomLeft,
      ),
      // A context menu should not veil the screen it belongs to.
      barrierColor: Colors.transparent,
      builder: (context) => MenuFlyout(
        items: widget.items(context, controller),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // `opaque` keeps the gesture alive over the transparent gaps of rows whose
    // children do not paint the whole area (padded list tiles, dividers).
    return FlyoutTarget(
      controller: controller,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: widget.longPress
            ? (details) =>
                unawaited(open(details.globalPosition, withFeedback: true))
            : null,
        onSecondaryTapDown: (details) =>
            unawaited(open(details.globalPosition)),
        child: widget.child,
      ),
    );
  }
}

/// Puts [suffix] a fixed gap after [title], so suffixes line up across items.
Widget menuTitleSuffix(Widget title, Widget? suffix) {
  if (suffix == null) return title;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      title,
      const SizedBox(width: 8),
      suffix,
    ],
  );
}

Widget menuCountSuffix(int count) =>
    Text('($count)', style: const TextStyle(fontSize: 12));

/// Absent is not an error: a hollow ring, with no red and no cross-out.
Widget menuPresenceSuffix(bool present) => Icon(
      present ? FluentIcons.check_mark : FluentIcons.circle_ring,
      size: 13,
      color: present ? Colors.green : Colors.grey,
    );
