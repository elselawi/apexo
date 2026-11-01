import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum Scope { device, app, system }

class AppliesToIndicator extends StatelessWidget {
  const AppliesToIndicator({super.key, required this.scope});

  final Scope scope;

  @override
  Widget build(BuildContext context) {
    final color = scope == Scope.device
        ? Colors.blue
        : scope == Scope.system
            ? Colors.red
            : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: 0.08),
      ),
      child: Txt(
        "${txt("appliesTo")}: ${scope == Scope.app ? txt("all") : scope == Scope.system ? txt("system") : txt("you")}",
        style: TextStyle(
          fontSize: 11,
          color: FluentTheme.of(context).resources.textFillColorSecondary,
        ),
      ),
    );
  }
}
