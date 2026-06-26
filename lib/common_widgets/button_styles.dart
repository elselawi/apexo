import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

const greyButtonStyle = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.grey),
  foregroundColor: WidgetStatePropertyAll(Colors.white),
);

ButtonStyle filledButtonStyle(Color color) => ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(color),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
    );

class ButtonContent extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const ButtonContent(
    this.icon,
    this.txt, {
    this.size,
    super.key,
    this.inProgress = false,
  });

  final String txt;
  final IconData icon;
  final double? size;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 5,
      mainAxisSize: MainAxisSize.min,
      children: [
        inProgress
            ? const SizedBox(
                height: 20,
                width: 20,
                child: ProgressRing(
                  strokeWidth: 4,
                ))
            : Icon(icon, size: size),
        Txt(
          txt,
          style: TextStyle(
            fontSize: size,
            color: inProgress
                ? FluentTheme.of(context).inactiveColor.withValues(alpha: 0.3)
                : null,
          ),
        )
      ],
    );
  }
}
