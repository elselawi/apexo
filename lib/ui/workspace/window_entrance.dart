part of 'windows_layer.dart';

class _WindowEntrance extends StatefulWidget {
  const _WindowEntrance({
    super.key,
    required this.child,
    required this.leaving,
    required this.onLeft,
    required this.from,
  });

  final Widget child;

  /// True while the window it draws is folding away.
  final bool leaving;

  /// Called once the window has finished folding away, so its owner can forget
  /// it.
  final VoidCallback onLeft;

  /// The corner it grows out of: the top-trailing one, where the dock's buttons
  /// sit, or the top centre on a phone.
  final AlignmentGeometry from;

  @override
  State<_WindowEntrance> createState() => _WindowEntranceState();
}

class _WindowEntranceState extends State<_WindowEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _openDuration,
    reverseDuration: _closeDuration,
    value: widget.leaving ? 0 : 1,
  );
  late final Animation<double> _value = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.leaving) {
      // Drawn already on its way out — a window that was replaced before its
      // first frame: nothing to animate, and it must not shrink the tree while
      // it is being built.
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLeft();
      });
    } else {
      // Arriving: grow out of the dock's corner.
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _WindowEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving != oldWidget.leaving) {
      if (widget.leaving) {
        unawaited(_controller.reverse().whenComplete(() {
          if (mounted) widget.onLeft();
        }));
      } else {
        _controller.forward();
      }
    } else if (!widget.leaving &&
        _controller.status == AnimationStatus.dismissed) {
      // Never leave a live window drawn at nothing.
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.from == AlignmentDirectional.topCenter;
    return AnimatedBuilder(
      animation: _value,
      builder: (context, child) {
        final value = _value.value;
        // A window drawn at nothing must not take clicks: it is not there, and
        // the app behind it has to keep working. Opacity alone does not stop a
        // hit test, so the pointer is ignored while the window is invisible.
        return IgnorePointer(
          ignoring: value <= 0,
          child: vertical
              // A sheet drops in from the top edge rather than growing from a
              // corner.
              ? Opacity(
                  opacity: value,
                  child: FractionalTranslation(
                    translation: Offset(0, -0.06 * (1 - value)),
                    child: child,
                  ),
                )
              : Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * value,
                    alignment: widget.from,
                    child: child,
                  ),
                ),
        );
      },
      child: widget.child,
    );
  }
}
