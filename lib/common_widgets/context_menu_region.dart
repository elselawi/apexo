import 'dart:async';

import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
/// On web the browser keeps right click (its context menu is enabled by
/// default) and the long press opens the menu instead.
///
/// The menu itself is a regular [MenuFlyout], so it closes on click outside,
/// on `Esc`, and repositions when there is no room below the pointer.
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.items,
    required this.child,
  });

  final ContextMenuItemsBuilder items;
  final Widget child;

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
        onLongPressStart: (details) =>
            unawaited(open(details.globalPosition, withFeedback: true)),
        // The browser's own context menu owns right click on web, and two menus
        // at once is worse than one: there the long press opens the menu.
        onSecondaryTapDown: kIsWeb
            ? null
            : (details) => unawaited(open(details.globalPosition)),
        child: widget.child,
      ),
    );
  }
}
