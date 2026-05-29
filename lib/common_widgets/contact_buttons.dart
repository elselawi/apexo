import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:country_flags/country_flags.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

ButtonStyle darkIconButtonStyle(BuildContext context, [Color? color]) {
  return ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(
      color ?? FluentTheme.of(context).inactiveColor.withAlpha(30),
    ),
  );
}

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
        style: darkIconButtonStyle(context),
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
  const PhoneNumberButton({
    super.key,
    required this.phoneNumbers,
    this.onlyIcon = true,
  });

  final List<ParsedPhoneNumber> phoneNumbers;
  final bool onlyIcon;

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
    return widget.phoneNumbers.length == 1;
  }

  @override
  void dispose() {
    flyoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: txt("contact"),
      child: FlyoutTarget(
        controller: flyoutCtrl,
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            IconButton(
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  FluentTheme.of(context).inactiveColor.withAlpha(30),
                ),
              ),
              icon: widget.onlyIcon
                  ? const Icon(WindowsIcons.phone)
                  : Row(
                      textDirection: TextDirection.ltr,
                      spacing: 5,
                      children: [
                        const Icon(WindowsIcons.phone),
                        CountryFlag.fromCountryCode(
                          widget.phoneNumbers.first.isoCode,
                          theme: const ImageTheme(height: 20, width: 20),
                        ),
                        Text(
                          widget.phoneNumbers.first.toInternationalFormat(),
                          textDirection: TextDirection.ltr,
                          style: FluentTheme.of(context).typography.bodyStrong,
                        )
                      ],
                    ),
              onPressed: showMenu,
            ),
          ],
        ),
      ),
    );
  }

  showMenu() async {
    await flyoutFocusFix(context);
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
                        text: Text(
                          widget.phoneNumbers.first.toInternationalFormat(),
                          textDirection: TextDirection.ltr,
                        ),
                        leading: const Icon(FluentIcons.number_field),
                        onPressed: () {},
                      ),
                      const MenuFlyoutSeparator(),
                      ...communicationActions(widget.phoneNumbers.first.e164)
                    ]
                  : widget.phoneNumbers
                      .map((singleNumber) => MenuFlyoutSubItem(
                          showBehavior: SubItemShowAction.press,
                          text: Text(singleNumber.toInternationalFormat()),
                          items: (ctx) =>
                              communicationActions(singleNumber.e164)))
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
