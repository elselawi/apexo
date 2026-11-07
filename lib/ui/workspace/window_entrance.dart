part of 'windows_layer.dart';

class _WindowEntrance extends StatefulWidget {
  const _WindowEntrance({
    super.key,
    required this.child,
    required this.leaving,
    required this.onLeft,
    required this.from,
    this.animateEntrance = true,
  });

  final bool animateEntrance;

  final Widget child;

  /// True while the window it draws is folding away.
  final bool leaving;

  /// Called once the fold-away finishes, so the owner can drop the window.
  final VoidCallback onLeft;

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
      // Replaced before its first frame: nothing to animate, and onLeft must
      // wait for a frame rather than fire during build.
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLeft();
      });
    } else if (widget.animateEntrance) {
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _value,
      builder: (context, child) {
        final value =
            reduceMotion ? (widget.leaving ? 0.0 : 1.0) : _value.value;
        // Opacity alone does not stop hit tests, so an invisible window must
        // ignore the pointer or it blocks the app behind it.
        return IgnorePointer(
          ignoring: widget.leaving || value <= 0,
          child: vertical
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
      child: ExcludeFocus(
        excluding: widget.leaving,
        child: ExcludeSemantics(
          excluding: widget.leaving,
          child: widget.child,
        ),
      ),
    );
  }
}
