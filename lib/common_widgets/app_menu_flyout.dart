import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A [MenuFlyout] that reads as a WinUI flyout rather than as a translucent
/// card: the acrylic fill is opaque enough to stay light over any backdrop,
/// the corner and stroke match the other overlays, and the shadow is light
/// enough that the menu does not sit on a dark rim.
class AppMenuFlyout extends StatelessWidget {
  const AppMenuFlyout({
    super.key,
    required this.items,
    this.constraints,
  });

  final List<MenuFlyoutItemBase> items;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final materials = FluentMaterials.of(context);
    return MenuFlyout(
      items: items,
      constraints: constraints,
      color: materials.acrylic,
      // Sub-menus inherit these, so keep them on the flyout itself. A full
      // black shadow at this elevation reads as a dark rim next to the OS's own
      // menus; the alpha brings it down to the theme shadow's softness.
      shadowColor: Colors.black.withValues(alpha: materials.dark ? 0.5 : 0.3),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: FluentMaterials.overlayRadius,
        side: BorderSide(
          color: materials.flyoutStroke,
          width: FluentMaterials.hairlineWidth,
        ),
      ),
    );
  }
}
