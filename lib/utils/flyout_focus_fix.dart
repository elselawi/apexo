import 'package:fluent_ui/fluent_ui.dart';

Future<void> flyoutFocusFix(BuildContext? context) async {
  final primaryFocus = FocusManager.instance.primaryFocus;
  final bool isInputFocused =
      primaryFocus?.context?.widget.toString().contains("EditableText") ??
          false;

  final bool isKeyboardVisible =
      context != null ? MediaQuery.of(context).viewInsets.bottom > 0 : false;

  if (isInputFocused || isKeyboardVisible) {
    primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
