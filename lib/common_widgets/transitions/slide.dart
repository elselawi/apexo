import 'package:fluent_ui/fluent_ui.dart';

class SlideTransitionWrapper extends StatefulWidget {
  const SlideTransitionWrapper({
    super.key,
    required this.child,
    this.direction = Axis.vertical,
  });
  final Widget child;
  final Axis direction;

  @override
  SlideTransitionWrapperState createState() => SlideTransitionWrapperState();
}

class SlideTransitionWrapperState extends State<SlideTransitionWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400), // Adjust duration as needed
    );
    _slideAnimation = Tween<Offset>(
      begin: widget.direction == Axis.horizontal
          ? const Offset(-1, 0)
          : const Offset(0, 1), // Slide in from left
      end: Offset.zero,
    ).animate(_controller);

    // Start the slide-in animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }
}
