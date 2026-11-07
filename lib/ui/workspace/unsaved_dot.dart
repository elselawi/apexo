import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class UnsavedDot extends StatelessWidget {
  const UnsavedDot({this.size = 7, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: WK.unsavedDot,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
        // A surface-coloured ring keeps the dot readable on badges, emoji and
        // titles.
        border: Border.all(
          color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
          width: 1,
        ),
      ),
    );
  }
}
