import 'package:flutter/material.dart';

class KeyboardAwareView extends StatelessWidget {
  final Widget child;

  const KeyboardAwareView({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1. Make the scaffold invisible so the dialog barrier shows through
      backgroundColor: Colors.transparent,
      // 2. Leverage the native keyboard-avoidance engine
      resizeToAvoidBottomInset: true,
      // 3. Center the dialog in the remaining visible screen space
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: child,
        ),
      ),
    );
  }
}
