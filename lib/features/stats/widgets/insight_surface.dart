import 'package:fluent_ui/fluent_ui.dart';

/// A softly lit surface; decorative lighting never changes chart geometry.
class InsightSurface extends StatefulWidget {
  const InsightSurface({
    super.key,
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 4,
  });

  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  State<InsightSurface> createState() => _InsightSurfaceState();
}

class _InsightSurfaceState extends State<InsightSurface> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = theme.resources.solidBackgroundFillColorBase;
    final color = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                  color.withValues(alpha: dark ? 0.14 : 0.055), base),
              base,
              Color.alphaBlend(
                  color.withValues(alpha: dark ? 0.07 : 0.025), base),
            ],
            stops: const [0, 0.55, 1],
          ),
          border: Border.all(
              color: color.withValues(
                  alpha: hovered
                      ? 0.42
                      : dark
                          ? 0.23
                          : 0.16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.2 : 0.045),
              blurRadius: hovered ? 26 : 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: color.withValues(alpha: hovered ? 0.11 : 0.035),
              blurRadius: 32,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius - 1),
          child: Stack(children: [
            PositionedDirectional(
              top: -120,
              end: -80,
              child: IgnorePointer(
                  child: Container(
                width: 320,
                height: 260,
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [
                    color.withValues(alpha: dark ? 0.13 : 0.08),
                    color.withValues(alpha: 0),
                  ]),
                ),
              )),
            ),
            Positioned(
              top: 0,
              left: 20,
              right: 20,
              child: IgnorePointer(
                  child: Container(
                height: 1,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: dark ? 0.25 : 0.95),
                  Colors.white.withValues(alpha: 0),
                ])),
              )),
            ),
            Padding(padding: widget.padding, child: widget.child),
          ]),
        ),
      ),
    );
  }
}
