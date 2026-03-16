import 'package:fluent_ui/fluent_ui.dart';

Future<void> flyoutFocusFix() async {
  FocusManager.instance.primaryFocus?.unfocus();
  await Future.delayed(const Duration(milliseconds: 300));
}
