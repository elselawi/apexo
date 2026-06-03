import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/login.dart';

class CurrentAccount extends StatelessWidget {
  const CurrentAccount({super.key});
  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              const Icon(FluentIcons.contact),
              const SizedBox(width: 5),
              SizedBox(
                width: 130,
                child: Txt(login.currentName, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const LogoutButton()
        ],
      ),
    );
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
