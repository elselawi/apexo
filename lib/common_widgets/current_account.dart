import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../services/login.dart';

class CurrentAccount extends StatelessWidget {
  const CurrentAccount({super.key});

  /// The narrowest header that can hold the account icon, a shortened name and
  /// the logout button. Below it the header draws nothing at all (see [build]).
  static const double _minWidth = 150;

  @override
  Widget build(BuildContext context) {
    // A **minimal** pane — a phone layout, or a 300px window — lays this header
    // out in the ~26px strip the hamburger occupies, and there is no arrangement
    // of a name and a logout button that fits: the row reported
    // `A RenderFlex overflowed by 214 pixels on the right` with a fixed 130px
    // name box, and by 61px once the name could shrink and only the button was
    // left (it cannot be narrower than its label). Below a width that can hold
    // both, the header draws nothing; the logout it holds is also on the
    // dashboard's command bar.
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
            // The name shrinks with an ellipsis rather than overflowing: a pane
            // that is compact but still drawn (a panel open on a 1280px window)
            // has room for the icon and a truncated name, never for both full.
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
