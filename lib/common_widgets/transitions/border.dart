import 'package:fluent_ui/fluent_ui.dart';

class BorderColorTransition extends StatefulWidget {
  const BorderColorTransition({
    super.key,
    required this.child,
    required this.animate,
    this.duration = const Duration(milliseconds: 500),
  });
  final Widget child;
  final Duration duration;
  final bool animate;

  @override
  BorderColorTransitionState createState() => BorderColorTransitionState();
}

class BorderColorTransitionState extends State<BorderColorTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _colorAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.transparent,
    ).animate(_controller);
    _followAnimate();
  }

  @override
  void didUpdateWidget(covariant BorderColorTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) _followAnimate();
  }

  /// Repeats only while the border is meant to pulse: a controller left running
  /// behind `animate: false` repaints the whole subtree forever for a border
  /// nobody sees.
  void _followAnimate() {
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: widget.animate
                    ? (_colorAnimation.value ?? Colors.red)
                    : Colors.transparent,
                width: 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}
