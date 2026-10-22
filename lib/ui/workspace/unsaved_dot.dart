import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The dot that says "there is work here that has not been stored".
///
/// One widget for the two places it belongs: on the badge of the record's kind in
/// a panel's header — where it reads as *this record* has unsaved changes, above
/// everything else in the panel — and beside a window's own title, for the
/// windows that stand on their own.
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
        // A ring in the surface's own colour keeps the dot readable over a
        // badge, an emoji or a title, whichever it lands on.
        border: Border.all(
          color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
          width: 1,
        ),
      ),
    );
  }
}
