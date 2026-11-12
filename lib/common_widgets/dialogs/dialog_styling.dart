import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:fluent_ui/fluent_ui.dart';

ContentDialogThemeData dialogStyling(BuildContext context, bool danger,
    [bool withLowerPadding = false]) {
  final materials = FluentMaterials.of(context);
  final theme = FluentTheme.of(context);
  return ContentDialogThemeData(
    decoration: BoxDecoration(
      borderRadius: FluentMaterials.overlayRadius,
      color: materials.acrylic,
      border: Border.all(
        color: danger
            ? theme.resources.systemFillColorCritical.withValues(alpha: 0.45)
            : materials.flyoutStroke,
        width: FluentMaterials.hairlineWidth,
      ),
      boxShadow: materials.overlayShadow,
    ),
    titleStyle: theme.typography.subtitle?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    bodyStyle: theme.typography.body,
    padding: EdgeInsets.fromLTRB(20, 20, 20, withLowerPadding ? 20 : 0),
  );
}
