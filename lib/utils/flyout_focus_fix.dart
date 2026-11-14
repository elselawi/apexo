import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';

Future<void> flyoutFocusFix(BuildContext? context) async {
  final primaryFocus = FocusManager.instance.primaryFocus;

  final bool isInputFocused =
      primaryFocus?.context?.widget.toString().contains("EditableText") ??
          false;

  // The caller's context can be gone by the time a scheduled handler runs.
  final view = context != null && context.mounted
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
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } finally {
        WidgetsBinding.instance.removeObserver(observer);
      }
    } else {
      await Future.microtask(() {});
    }
  }
}

/// Signals [onClosed] when the given view's bottom inset reaches zero; metric
/// updates are global, so the observer checks its own view.
class _KeyboardObserver extends WidgetsBindingObserver {
  _KeyboardObserver({required this.view, required this.onClosed});
  final FlutterView view;
  final VoidCallback onClosed;

  @override
  void didChangeMetrics() {
    if (view.viewInsets.bottom == 0) {
      onClosed();
    }
  }
}
