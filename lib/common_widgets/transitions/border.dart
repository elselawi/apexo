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
    )..repeat(reverse: true);

    _colorAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.transparent,
    ).animate(_controller);
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
