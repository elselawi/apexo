import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

const greyButtonStyle = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.grey),
  foregroundColor: WidgetStatePropertyAll(Colors.white),
);

filledButtonStyle(Color color) => ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(color),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
    );

class ButtonContent extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const ButtonContent(this.icon, this.txt, {this.size, super.key});

  final String txt;
  final IconData icon;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 5,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size),
        Txt(txt, style: TextStyle(fontSize: size))
      ],
    );
  }
}
