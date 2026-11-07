import 'package:flutter/material.dart';

/// Without a mouse, long-press stands in for [onEnter] and an outside tap for
/// [onExit].
class AdaptiveHoverWidget extends StatefulWidget {
  const AdaptiveHoverWidget({
    super.key,
    required this.child,
    this.onEnter,
    this.onExit,
    this.cursor = SystemMouseCursors.click,
  });
  final Widget child;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final MouseCursor cursor;

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
