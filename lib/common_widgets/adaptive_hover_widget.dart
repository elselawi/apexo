import 'package:flutter/material.dart';

/// A platform-adaptive hover widget.
///
/// On desktop (mouse connected), it behaves like [MouseRegion]:
/// [onEnter] fires when the pointer enters, [onExit] fires when it leaves.
///
/// On touch devices (no mouse), [onEnter] fires on long-press and
/// [onExit] fires when the user taps outside the widget.
class AdaptiveHoverWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final MouseCursor cursor;

  const AdaptiveHoverWidget({
    super.key,
    required this.child,
    this.onEnter,
    this.onExit,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<AdaptiveHoverWidget> createState() => _AdaptiveHoverWidgetState();
}

class _AdaptiveHoverWidgetState extends State<AdaptiveHoverWidget> {
  bool _isActive = false;

  bool get _hasMouse => WidgetsBinding.instance.mouseTracker.mouseIsConnected;

  void _enter() {
    if (!_isActive) {
      _isActive = true;
      widget.onEnter?.call();
    }
  }

  void _exit() {
    if (_isActive) {
      _isActive = false;
      widget.onExit?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasMouse) {
      return MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _exit(),
        cursor: widget.cursor,
        child: widget.child,
      );
    }
    return GestureDetector(
      onLongPress: _enter,
      child: TapRegion(
        onTapOutside: (_) => _exit(),
        child: widget.child,
      ),
    );
  }
}
