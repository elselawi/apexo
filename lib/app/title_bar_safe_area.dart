import 'package:fluent_ui/fluent_ui.dart';

/// Holds the shell's title bar under the status bar.
///
/// [TitleBar] pads itself with a [SafeArea] and *also* adds
/// `MediaQuery.padding.top` to its own height, so wherever a real status bar
/// exists it renders a whole status bar too tall: its content ends up half an
/// inset low and the bar hangs over the body below it. Applying the inset once
/// here — and handing the view a padding-free [MediaQuery] — puts the bar back
/// under the status bar with the body right beneath it.
class TitleBarSafeArea extends StatelessWidget {
  const TitleBarSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    if (inset == 0) return child;
    return Padding(
      padding: EdgeInsets.only(top: inset),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: child,
      ),
    );
  }
}
