import 'package:flutter/material.dart';

class RotatingWrapper extends StatefulWidget {
  const RotatingWrapper({super.key, required this.child, this.rotate = false});
  final Widget child;
  final bool rotate;

  @override
  RotatingWrapperState createState() => RotatingWrapperState();
}

class RotatingWrapperState extends State<RotatingWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(minutes: 5),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 360).animate(_controller);

    if (widget.rotate) {
      _controller.repeat(); // Start rotation animation
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotationAnimation,
      child: widget.child,
    );
  }
}
