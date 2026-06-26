import 'package:apexo/common_widgets/dialogs/changelog_dialog.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Use this widget to display the logo and name of your app
class AppLogo extends StatefulWidget {
  const AppLogo({super.key});

  @override
  State<AppLogo> createState() => _AppLogoState();
}

String savedVersion = "";

class _AppLogoState extends State<AppLogo> {
  String version = savedVersion;

  @override
  void initState() {
    if (version.isEmpty) {
      PackageInfo.fromPlatform().then((p) {
        if (mounted) {
          setState(() {
            version = p.version;
            savedVersion = p.version;
          });
        }
      }).ignore();
    }
    super.initState();
  }

  void _onVersionTap() {
    showChangelogDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
        color: (FluentTheme.of(context).iconTheme.color ?? Colors.grey)
            .withValues(alpha: 0.4),
        fontSize: 12);
    final versionStyle = textStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );
    return Center(
      key: WK.appLogo,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GestureDetector(
          onTap: _onVersionTap,
          child: Row(
            children: [
              Image.asset(
                "assets/app_icon.png",
                height: 50,
              ),
              const SizedBox(width: 5),
              Text("Apexo", style: textStyle),
              const SizedBox(width: 5),
              Text(version, style: versionStyle),
            ],
          ),
        ),
      ),
    );
  }
}
