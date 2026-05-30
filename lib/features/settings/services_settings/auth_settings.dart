import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';

class AuthSettings extends StatefulWidget {
  const AuthSettings({super.key});

  @override
  State<AuthSettings> createState() => _AuthSettingsState();
}

class _AuthSettingsState extends State<AuthSettings> {
  final TextEditingController _usersDurationController =
      TextEditingController();
  final TextEditingController _superusersDurationController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final users = await login.pb!.collections.getOne("users");
      final superusers = await login.pb!.collections.getOne("_superusers");
      final usersSec = users.authToken?.duration ?? 0;
      final superusersSec = superusers.authToken?.duration ?? 0;
      _usersDurationController.text =
          usersSec > 0 ? (usersSec ~/ 86400).toString() : "";
      _superusersDurationController.text =
          superusersSec > 0 ? (superusersSec ~/ 86400).toString() : "";
    } catch (e) {
      // Controllers remain empty on error
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    try {
      final userDays =
          (int.tryParse(_usersDurationController.text) ?? 14).clamp(1, 36500);
      final superuserDays =
          (int.tryParse(_superusersDurationController.text) ?? 14)
              .clamp(1, 36500);
      await login.pb!.collections.update("users", body: {
        "authToken": {"duration": userDays * 86400}
      });
      await login.pb!.collections.update("_superusers", body: {
        "authToken": {"duration": superuserDays * 86400}
      });
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, false, true),
            title: Txt(txt("success")),
            content: Txt(txt("auth_save_success")),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: Txt(txt("close")),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, true, true),
            title: Txt(txt("fail")),
            content: Txt("${txt("auth_save_fail")}: $e"),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: Txt(txt("close")),
              )
            ],
          ),
        );
      }
    }
  }

  Widget _buildSuffix(TextEditingController controller) {
    final days = int.tryParse(controller.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Text(
        days == 1 ? txt("day") : txt("days"),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usersDurationController.dispose();
    _superusersDurationController.dispose();
    super.dispose();
  }

  Widget _hint(String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        txt(key),
        style: TextStyle(fontSize: 11, color: Colors.grey.withAlpha(180)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: const Icon(FluentIcons.authenticator_app),
        header: Txt(txt("auth_settings")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoBar(
                title: Txt(txt("auth_info_title")),
                severity: InfoBarSeverity.info,
                content: Txt(txt("auth_info_desc")),
              ),
              const SizedBox(height: 15),
              ResponsiveRow(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("auth_users_duration")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: _usersDurationController,
                      placeholder: "14",
                      keyboardType: TextInputType.number,
                      suffix: _buildSuffix(_usersDurationController),
                    ),
                    _hint("auth_users_duration_hint"),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("auth_superusers_duration")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: _superusersDurationController,
                      placeholder: "14",
                      keyboardType: TextInputType.number,
                      suffix: _buildSuffix(_superusersDurationController),
                    ),
                    _hint("auth_superusers_duration_hint"),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton(
                    onPressed: _saveSettings,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.save),
                        const SizedBox(width: 8),
                        Txt(txt("save")),
                      ],
                    ),
                  ),
                ],
              ),
            ]
                .map((e) => [e, const SizedBox(height: 5)])
                .expand((e) => e)
                .toList(),
          ),
        ),
      ),
    );
  }
}
