import 'package:fluent_ui/fluent_ui.dart';

class SwipeDetector extends StatelessWidget {
  final Widget child;
  final void Function() onSwipePrev;
  final void Function() onSwipeNext;

  const SwipeDetector({
    super.key,
    required this.onSwipePrev,
    required this.onSwipeNext,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.velocity.pixelsPerSecond.dx > 0) {
          Directionality.of(context) == TextDirection.ltr
              ? onSwipePrev()
              : onSwipeNext();
        } else if (details.velocity.pixelsPerSecond.dx < 0) {
          Directionality.of(context) == TextDirection.ltr
              ? onSwipeNext()
              : onSwipePrev();
        }
      },
      child: child,
    );
  }
}
