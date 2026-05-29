import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';

Future<void> flyoutFocusFix(BuildContext? context) async {
  final primaryFocus = FocusManager.instance.primaryFocus;

  final bool isInputFocused =
      primaryFocus?.context?.widget.toString().contains("EditableText") ??
          false;

  final view = context != null
      ? View.maybeOf(context)
      : WidgetsBinding.instance.platformDispatcher.implicitView;

  final bool isKeyboardVisible = (view?.viewInsets.bottom ?? 0) > 0;

  if (isInputFocused || isKeyboardVisible) {
    primaryFocus?.unfocus();

    if (view != null && view.viewInsets.bottom > 0) {
      final completer = Completer<void>();

      final observer = _KeyboardObserver(
        view: view,
        onClosed: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      WidgetsBinding.instance.addObserver(observer);

      try {
        await completer.future;
        await Future.delayed(const Duration(milliseconds: 50));
      } finally {
        WidgetsBinding.instance.removeObserver(observer);
      }
    } else {
      await Future.microtask(() {});
    }
  }
}

/// Standalone observer that listens to platform metric updates
/// and signals when the specific view's bottom inset hits zero.
class _KeyboardObserver extends WidgetsBindingObserver {
  final FlutterView view;
  final VoidCallback onClosed;

  _KeyboardObserver({required this.view, required this.onClosed});

  @override
  void didChangeMetrics() {
    if (view.viewInsets.bottom == 0) {
      onClosed();
    }
  }
}
