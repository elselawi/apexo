import 'dart:async';

import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Builds the items of a context menu.
///
/// [controller] is the menu's own controller: it closes it, and it can show a
/// follow-up flyout after it (a delete confirmation, for instance) — anchor it
/// to the same row by reusing the controller instead of creating a new target.
typedef ContextMenuItemsBuilder = List<MenuFlyoutItemBase> Function(
  BuildContext context,
  FlyoutController controller,
);

/// Opens a context menu for [child] on long press (touch) or right click
/// (mouse, trackpad, pen), anchored at the pointer.
///
/// The long press also triggers the platform feedback (Android vibration, iOS
/// impact plus click) so the gesture can be felt, and the menu follows the
/// reading direction: it unfolds to the right in LTR and to the left in RTL.
///
/// The browser's own context menu is turned off on web (see `main.dart`), so a
/// right click opens this menu there too — the same as on every other
/// platform, and the only way in where the long press belongs to a drag.
///
/// The menu itself is a regular [MenuFlyout], so it closes on click outside,
/// on `Esc`, and repositions when there is no room below the pointer.
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.items,
    required this.child,
    this.longPress = true,
  });

  final ContextMenuItemsBuilder items;
  final Widget child;

  /// Whether a long press opens the menu too. False where the region's own
  /// widget needs that gesture — a timeline chip that is dragged by long press —
  /// which leaves right click as the way in.
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

/// The title of a context menu item that also says how much is behind it, or
/// whether it is there at all.
///
/// [suffix] sits a fixed gap after [title] — one gap for every item, whatever
/// the title's length — which is the "suffix" a plain string cannot give: glued
/// onto the title, the space depends on whether the join added one, a colon or
/// nothing at all. A null suffix leaves the title exactly as it was.
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

/// How many things the item opens, for [menuTitleSuffix]. Counts read as a
/// parenthesised aside, never as part of the title itself.
Widget menuCountSuffix(int count) =>
    Text('($count)', style: const TextStyle(fontSize: 12));

/// Whether the thing the item opens is there — the labwork order, the patient's
/// web page — for [menuTitleSuffix]. A check says here; a hollow ring says
/// absent, which is not the same statement as an error, so nothing here is
/// drawn in red or crossed out.
Widget menuPresenceSuffix(bool present) => Icon(
      present ? FluentIcons.check_mark : FluentIcons.circle_ring,
      size: 13,
      color: present ? Colors.green : Colors.grey,
    );
