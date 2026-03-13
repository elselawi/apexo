import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SmallLabel extends StatelessWidget {
  const SmallLabel({
    super.key,
    required this.label,
    required this.textColor,
    required this.bgColor,
    required this.icon,
  });

  final String label;
  final Color textColor;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Txt(
            label,
            style: theme.typography.caption?.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}