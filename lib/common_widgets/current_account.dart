import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/login.dart';

class CurrentAccount extends StatelessWidget {
  const CurrentAccount({super.key});

  /// Narrowest width that still fits the icon, a shortened name and logout.
  static const double _minWidth = 150;

  @override
  Widget build(BuildContext context) {
    // Below [_minWidth] nothing is drawn; logout is also on the dashboard's
    // command bar.
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < _minWidth) return const SizedBox.shrink();
      return Container(
        decoration: BoxDecoration(
            border: BoxBorder.fromLTRB(
                bottom: BorderSide(
                    color: FluentTheme.of(context).inactiveBackgroundColor))),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(FluentIcons.contact),
                  const SizedBox(width: 5),
                  Flexible(
                    child:
                        Txt(login.currentName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            const LogoutButton()
          ],
        ),
      );
    });
  }
}

class LogoutButton extends StatelessWidget {
  const LogoutButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      key: WK.btnLogout,
      onPressed: () {
        login.logout(false);
      },
      child: ButtonContent(FluentIcons.sign_out, txt("logout")),
    );
  }
}
