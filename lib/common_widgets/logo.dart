import 'dart:async';
import 'package:apexo/common_widgets/dialogs/changelog_dialog.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Use this widget to display the logo and name of your app
class AppLogo extends StatefulWidget {
  const AppLogo({super.key, this.compact = false});

  /// Pane-header size: a smaller mark, with the name and version still beside it.
  final bool compact;

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
    unawaited(showChangelogDialog(context));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final materials = FluentMaterials.of(context);
    final versionStyle = theme.typography.caption?.copyWith(
      color: materials.textTertiary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: materials.textTertiary,
    );
    return Center(
      key: WK.appLogo,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: _onVersionTap,
          // The logo also sits in the navigation pane header, which can be
          // narrower than the icon, name and version together.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              spacing: 8,
              children: [
                Image.asset(
                  "assets/app_icon.png",
                  height: widget.compact ? 24 : 50,
                ),
                Text(
                  "Apexo",
                  style: theme.typography.bodyStrong?.copyWith(
                    color: materials.textSecondary,
                  ),
                ),
                Text(version, style: versionStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
