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
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withAlpha(20),
            color.withAlpha(60),
          ],
        ),
      ),
      child: Txt(
        "${txt("appliesTo")}: ${scope == Scope.app ? txt("all") : scope == Scope.system ? txt("system") : txt("you")}",
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
