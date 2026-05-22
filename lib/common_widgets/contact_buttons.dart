import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailButton extends StatelessWidget {
  const EmailButton({
    super.key,
    required this.email,
  });

  final String email;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: txt("sendEmail"),
      child: IconButton(
        style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(
                FluentTheme.of(context).inactiveBackgroundColor)),
        icon: Icon(
          WindowsIcons.mail,
          color: FluentTheme.of(context).inactiveColor,
        ),
        onPressed: () {
          launchUrl(Uri.parse('mailto:$email'));
        },
      ),
    );
  }
}

class PhoneNumberButton extends StatefulWidget {
  PhoneNumberButton({
    super.key,
    required this.phoneNumber,
  });

  final String phoneNumber;

  @override
  State<PhoneNumberButton> createState() => PhoneNumberButtonState();
}

class PhoneNumberButtonState extends State<PhoneNumberButton> {
  final flyoutCtrl = FlyoutController();

  String fullPhoneNumber(String num) {
    if (num.startsWith("+")) {
      return num.trim();
    }
    return "${globalSettings.get("country_code___").value}${num.trim()}";
  }

  bool get singlePhoneNumber {
    return !widget.phoneNumber.trim().contains(" ");
  }

  List<String> get phoneNumbers {
    return widget.phoneNumber.trim().split(" ");
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: txt("contact"),
      child: FlyoutTarget(
        controller: flyoutCtrl,
        child: IconButton(
          style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                  FluentTheme.of(context).inactiveBackgroundColor)),
          icon: Icon(
            WindowsIcons.phone,
            color: FluentTheme.of(context).inactiveColor,
          ),
          onPressed: showFlyout,
        ),
      ),
    );
  }

  showFlyout() {
    flyoutCtrl.showFlyout(
        barrierDismissible: true,
        dismissOnPointerMoveAway: false,
        dismissWithEsc: true,
        builder: (ctx) {
          return MenuFlyout(
              items: singlePhoneNumber
                  ? [
                      MenuFlyoutItem(
                        selected: true,
                        text: Text(widget.phoneNumber),
                        leading: const Icon(FluentIcons.number_field),
                        onPressed: () {},
                      ),
                      const MenuFlyoutSeparator(),
                      ...communicationActions(widget.phoneNumber)
                    ]
                  : phoneNumbers
                      .map((singleNumber) => MenuFlyoutSubItem(
                          showBehavior: SubItemShowAction.press,
                          text: Text(singleNumber),
                          items: (ctx) => communicationActions(singleNumber)))
                      .toList());
        });
  }

  List<MenuFlyoutItem> communicationActions(String num) {
    return [
      MenuFlyoutItem(
        text: Txt(txt("call")),
        leading: const Icon(FluentIcons.phone),
        onPressed: () {
          launchUrl(Uri.parse("tel:${fullPhoneNumber(num)}"));
        },
        closeAfterClick: true,
      ),
      MenuFlyoutItem(
        text: Txt(txt("text")),
        leading: const Icon(FluentIcons.message),
        onPressed: () {
          launchUrl(Uri.parse("sms:${fullPhoneNumber(num)}"));
        },
        closeAfterClick: true,
      ),
      MenuFlyoutItem(
        text: Txt(txt("whatsapp")),
        leading: const Icon(WindowsIcons.message),
        onPressed: () {
          launchUrl(Uri.parse("https://wa.me/${fullPhoneNumber(num)}"));
        },
        closeAfterClick: true,
      ),
      MenuFlyoutItem(
        text: Txt(txt("telegram")),
        leading: const Icon(FluentIcons.send),
        onPressed: () {
          launchUrl(Uri.parse("https://t.me/${fullPhoneNumber(num)}"));
        },
        closeAfterClick: true,
      ),
    ];
  }
}
