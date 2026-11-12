import 'dart:ui' as ui;

import 'package:apexo/services/backdrop.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The material the whole shell is painted on.
///
/// On Windows the window itself is translucent, so there is nothing to paint:
/// DWM composes Mica and the layers above it carry the tint. Everywhere else
/// this stands in for it with two very soft washes under the Mica tint, which
/// is what gives a Fluent app its sense of depth instead of a flat grey page.
class MicaBackdrop extends StatelessWidget {
  const MicaBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final materials = FluentMaterials.of(context);
    if (Backdrop.native) {
      return Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: ColoredBox(color: materials.micaVeil)),
          child,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: materials.micaBase),
        _MicaWash(
          color: materials.micaWashPrimary,
          center: const Alignment(-0.85, -0.95),
          radius: 1.35,
        ),
        _MicaWash(
          color: materials.micaWashSecondary,
          center: const Alignment(0.95, 1.05),
          radius: 1.2,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                materials.micaTint,
                Color.lerp(materials.micaTint, materials.micaBase, 0.45)!,
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _MicaWash extends StatelessWidget {
  const _MicaWash({
    required this.color,
    required this.center,
    required this.radius,
  });

  final Color color;
  final Alignment center;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: center,
          radius: radius,
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// A translucent surface: acrylic over whatever is behind it, framed by the
/// 1px flyout stroke WinUI uses instead of a heavy shadow.
class AcrylicSurface extends StatelessWidget {
  const AcrylicSurface({
    super.key,
    required this.child,
    this.radius = FluentMaterials.radiusSurface,
    this.blur = 18,
    this.color,
    this.borderColor,
    this.shadows,
    this.padding,
  });

  final Widget child;
  final double radius;

  /// Whether — and how hard — to blur the content behind the surface. Bars that
  /// sit on a still backdrop gain nothing from it.
  final double blur;

  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final materials = FluentMaterials.of(context);
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows ?? const <BoxShadow>[],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blur > 0
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: _buildFill(materials, borderRadius, content),
              )
            : _buildFill(materials, borderRadius, content),
      ),
    );
  }

  Widget _buildFill(
    FluentMaterials materials,
    BorderRadius borderRadius,
    Widget content,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? materials.acrylic,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? materials.flyoutStroke,
          width: FluentMaterials.hairlineWidth,
        ),
      ),
      child: content,
    );
  }
}

/// A layer card: the translucent fill WinUI puts on top of Mica, with a
/// hairline edge. No blur — content behind it is meant to stay readable.
class FluentSurface extends StatelessWidget {
  const FluentSurface({
    super.key,
    required this.child,
    this.color,
    this.radius = FluentMaterials.radiusSurface,
    this.borderColor,
    this.shadows,
    this.padding,
  });

  final Widget child;
  final Color? color;
  final double radius;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final materials = FluentMaterials.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? materials.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? materials.hairline,
          width: FluentMaterials.hairlineWidth,
        ),
        boxShadow: shadows ?? const <BoxShadow>[],
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
}
